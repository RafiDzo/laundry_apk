-- ============================================================
-- WASHORA — LANGGANAN MEMBER (BRONZE / SILVER / GOLD) — TAHAP 1
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- Aman dijalankan berulang (idempotent).
--
-- Alur tahap 1 (pembayaran manual):
--   1. Pelanggan memilih paket, membayar via transfer/QRIS, lalu mengunggah bukti.
--      → baris memberships berstatus 'pending'.
--   2. Admin membuka Table Editor → memberships, cek bukti (bucket membership-proofs),
--      lalu ubah status menjadi 'active' (atau 'rejected' + isi admin_note).
--      → trigger mengisi starts_at / ends_at dan mengirim notifikasi ke pelanggan.
--   3. Isi info rekening/QRIS Washora di tabel membership_payment_info (1 baris).
-- Benefit otomatis saat checkout (gratis ongkir, poin, dll.) menyusul di tahap 2.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. PAKET
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.membership_plans (
  id TEXT PRIMARY KEY CHECK (id IN ('bronze', 'silver', 'gold')),
  name TEXT NOT NULL,
  price_monthly INT NOT NULL CHECK (price_monthly > 0),
  price_yearly INT NOT NULL CHECK (price_yearly > 0),
  free_delivery_quota INT,          -- per bulan; NULL = tanpa batas (wajar pakai)
  points_pct NUMERIC(4,1) NOT NULL DEFAULT 0,
  member_discount_pct INT NOT NULL DEFAULT 0, -- di outlet Mitra Member (tahap 3)
  claim_window_hours INT NOT NULL DEFAULT 48,
  express_quota INT NOT NULL DEFAULT 0,
  priority_queue BOOLEAN NOT NULL DEFAULT FALSE,
  birthday_voucher BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0
);

-- Tahunan = harga 10 bulan
INSERT INTO public.membership_plans
  (id, name, price_monthly, price_yearly, free_delivery_quota, points_pct, member_discount_pct,
   claim_window_hours, express_quota, priority_queue, birthday_voucher, sort_order)
VALUES
  ('bronze', 'Bronze', 19000, 190000, 4,    1.0, 0,  48,  0, FALSE, FALSE, 1),
  ('silver', 'Silver', 49000, 490000, 10,   2.0, 5,  72,  1, TRUE,  TRUE,  2),
  ('gold',   'Gold',   99000, 990000, NULL, 3.0, 10, 168, 3, TRUE,  TRUE,  3)
ON CONFLICT (id) DO NOTHING;   -- harga yang sudah diubah admin tidak ditimpa

ALTER TABLE public.membership_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view membership plans" ON public.membership_plans;
CREATE POLICY "Anyone can view membership plans" ON public.membership_plans FOR SELECT USING (TRUE);
GRANT SELECT ON public.membership_plans TO anon, authenticated;

-- Info pembayaran Washora (diisi admin; aplikasi menampilkan apa adanya)
CREATE TABLE IF NOT EXISTS public.membership_payment_info (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  bank_name TEXT NOT NULL DEFAULT '',
  account_number TEXT NOT NULL DEFAULT '',
  account_name TEXT NOT NULL DEFAULT '',
  qris_image_url TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT ''
);
INSERT INTO public.membership_payment_info (id) VALUES (TRUE) ON CONFLICT DO NOTHING;
ALTER TABLE public.membership_payment_info ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated view payment info" ON public.membership_payment_info;
CREATE POLICY "Authenticated view payment info" ON public.membership_payment_info
  FOR SELECT TO authenticated USING (TRUE);
GRANT SELECT ON public.membership_payment_info TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 2. LANGGANAN PELANGGAN
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.users(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL REFERENCES public.membership_plans(id),
  period TEXT NOT NULL DEFAULT 'monthly' CHECK (period IN ('monthly', 'yearly')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'rejected', 'cancelled')),
  amount INT NOT NULL DEFAULT 0,
  payment_method TEXT NOT NULL DEFAULT 'transfer' CHECK (payment_method IN ('transfer', 'qris')),
  proof_path TEXT,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  free_delivery_used INT NOT NULL DEFAULT 0,
  express_used INT NOT NULL DEFAULT 0,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS memberships_user_idx ON public.memberships (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS memberships_pending_idx ON public.memberships (status, created_at) WHERE status = 'pending';
-- Satu pengajuan yang menunggu konfirmasi per pelanggan
CREATE UNIQUE INDEX IF NOT EXISTS memberships_one_pending ON public.memberships (user_id) WHERE status = 'pending';

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customer views own memberships" ON public.memberships;
CREATE POLICY "Customer views own memberships" ON public.memberships
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Customer requests membership" ON public.memberships;
CREATE POLICY "Customer requests membership" ON public.memberships
  FOR INSERT WITH CHECK (user_id = auth.uid() AND status = 'pending');

-- Pelanggan hanya boleh mengatur "berhenti di akhir periode" (dijaga trigger)
DROP POLICY IF EXISTS "Customer updates own membership" ON public.memberships;
CREATE POLICY "Customer updates own membership" ON public.memberships
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.memberships TO authenticated;


-- Harga & status ditentukan server, bukan aplikasi
CREATE OR REPLACE FUNCTION public.memberships_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p public.membership_plans%ROWTYPE;
  v_from TIMESTAMPTZ;
  is_admin BOOLEAN := auth.uid() IS NULL;  -- Table Editor / service role tidak punya auth.uid()
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO p FROM public.membership_plans WHERE id = NEW.plan_id;
    NEW.amount := CASE WHEN NEW.period = 'yearly' THEN p.price_yearly ELSE p.price_monthly END;
    IF NOT is_admin THEN
      NEW.status := 'pending';
      NEW.starts_at := NULL; NEW.ends_at := NULL;
      NEW.free_delivery_used := 0; NEW.express_used := 0; NEW.admin_note := NULL;
      IF NEW.proof_path IS NULL OR NEW.proof_path NOT LIKE NEW.user_id::text || '/%' THEN
        RAISE EXCEPTION 'Unggah bukti pembayaran terlebih dahulu' USING ERRCODE = '22023';
      END IF;
    END IF;
  ELSE
    IF NOT is_admin THEN
      -- Pelanggan: semua kolom kembali seperti semula kecuali cancel_at_period_end
      NEW.plan_id := OLD.plan_id; NEW.period := OLD.period; NEW.status := OLD.status;
      NEW.amount := OLD.amount; NEW.payment_method := OLD.payment_method; NEW.proof_path := OLD.proof_path;
      NEW.starts_at := OLD.starts_at; NEW.ends_at := OLD.ends_at;
      NEW.free_delivery_used := OLD.free_delivery_used; NEW.express_used := OLD.express_used;
      NEW.admin_note := OLD.admin_note; NEW.user_id := OLD.user_id; NEW.created_at := OLD.created_at;
    END IF;
    -- Admin mengaktifkan: mulai sekarang, atau setelah langganan aktif sebelumnya berakhir (perpanjangan)
    IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' AND NEW.starts_at IS NULL THEN
      SELECT GREATEST(NOW(), COALESCE(MAX(ends_at), NOW())) INTO v_from
      FROM public.memberships
      WHERE user_id = NEW.user_id AND status = 'active' AND id <> NEW.id AND ends_at > NOW();
      NEW.starts_at := COALESCE(v_from, NOW());
      NEW.ends_at := NEW.starts_at + CASE WHEN NEW.period = 'yearly' THEN INTERVAL '365 days' ELSE INTERVAL '30 days' END;
    END IF;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS memberships_guard ON public.memberships;
CREATE TRIGGER memberships_guard
  BEFORE INSERT OR UPDATE ON public.memberships
  FOR EACH ROW EXECUTE FUNCTION public.memberships_guard();

-- Notifikasi ke pelanggan saat admin mengaktifkan / menolak
CREATE OR REPLACE FUNCTION public.memberships_notify()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NULL; END IF;
  SELECT name INTO v_name FROM public.membership_plans WHERE id = NEW.plan_id;
  IF NEW.status = 'active' THEN
    INSERT INTO public.notifications (user_id, status, title, body)
    VALUES (NEW.user_id, 'membership_active', 'Langganan ' || v_name || ' aktif',
            'Berlaku sampai ' || to_char(NEW.ends_at AT TIME ZONE 'Asia/Jakarta', 'DD/MM/YYYY') || '.');
  ELSIF NEW.status = 'rejected' THEN
    INSERT INTO public.notifications (user_id, status, title, body)
    VALUES (NEW.user_id, 'membership_rejected', 'Pembayaran langganan ' || v_name || ' ditolak',
            COALESCE(NULLIF(NEW.admin_note, ''), 'Bukti pembayaran tidak sesuai. Silakan ajukan ulang.'));
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS memberships_notify ON public.memberships;
CREATE TRIGGER memberships_notify
  AFTER UPDATE ON public.memberships
  FOR EACH ROW EXECUTE FUNCTION public.memberships_notify();


-- Tingkat member pelanggan sebuah pesanan — untuk struk & prioritas di dashboard mitra.
-- Hanya pemilik outlet pesanan itu (atau pelanggannya sendiri) yang boleh bertanya.
CREATE OR REPLACE FUNCTION public.member_tier_for_order(p_order_id UUID)
RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o RECORD;
  v TEXT;
BEGIN
  SELECT id, user_id, shop_id INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR o.user_id IS NULL THEN RETURN NULL; END IF;
  IF auth.uid() IS DISTINCT FROM o.user_id AND NOT public.is_shop_owner(o.shop_id) THEN RETURN NULL; END IF;
  SELECT plan_id INTO v FROM public.memberships
  WHERE user_id = o.user_id AND status = 'active' AND NOW() BETWEEN starts_at AND ends_at
  ORDER BY ends_at DESC LIMIT 1;
  RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION public.member_tier_for_order(UUID) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 3. BUKTI PEMBAYARAN (privat; pelanggan hanya di foldernya sendiri)
--    Path: {user_id}/{waktu}.jpg — admin melihatnya di Storage dashboard.
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('membership-proofs', 'membership-proofs', FALSE, 3145728, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Customer uploads own payment proof" ON storage.objects;
CREATE POLICY "Customer uploads own payment proof" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'membership-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Customer views own payment proof" ON storage.objects;
CREATE POLICY "Customer views own payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'membership-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);


-- ════════════════════════════════════════════════════════════
-- 4. STRUK: status bayar pesanan (dipakai Cetak Resi)
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cash_received INT;

NOTIFY pgrst, 'reload schema';
