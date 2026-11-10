-- ============================================================
-- WASHORA — SALDO KOMISI MITRA + QRIS DINAMIS
-- Jalankan SETELAH supabase_langganan.sql. Aman dijalankan berulang.
--
-- Model: uang pelanggan masuk langsung ke QRIS mitra. Komisi Washora dipotong
-- dari "saldo komisi" mitra saat pesanan aplikasi mulai diproses (Menunggu → Dicuci).
--   • Saldo boleh minus sampai batas kredit; lewat batas → outlet berhenti menerima
--     pesanan aplikasi baru (pesanan berjalan tetap bisa diselesaikan).
--   • Masa pengenalan (commission_active = false): komisi Rp 0, tetap dicatat.
--   • Pesanan walk-in (tanpa akun pelanggan) tidak dikenai komisi.
--   • Isi saldo: bayar ke QRIS Washora (nominal + kode unik), unggah bukti,
--     admin mengubah status jadi 'approved' di Table Editor → saldo bertambah.
-- Pengaturan admin: Table Editor → platform_settings (1 baris).
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. PENGATURAN PLATFORM
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.platform_settings (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  commission_amount INT NOT NULL DEFAULT 2000 CHECK (commission_amount >= 0),
  commission_active BOOLEAN NOT NULL DEFAULT FALSE,   -- FALSE = masa pengenalan (gratis)
  default_credit_limit INT NOT NULL DEFAULT 20000 CHECK (default_credit_limit >= 0),
  welcome_credit INT NOT NULL DEFAULT 20000 CHECK (welcome_credit >= 0),
  qris_payload TEXT NOT NULL DEFAULT '',              -- teks QRIS statis milik Washora
  qris_note TEXT NOT NULL DEFAULT ''
);
INSERT INTO public.platform_settings (id) VALUES (TRUE) ON CONFLICT DO NOTHING;

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated view platform settings" ON public.platform_settings;
CREATE POLICY "Authenticated view platform settings" ON public.platform_settings
  FOR SELECT TO authenticated USING (TRUE);
GRANT SELECT ON public.platform_settings TO authenticated;

-- QRIS statis outlet (untuk QRIS dinamis pembayaran pesanan)
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS qris_payload TEXT NOT NULL DEFAULT '';


-- ════════════════════════════════════════════════════════════
-- 2. SALDO, BUKU SALDO, ISI SALDO
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.shop_wallets (
  shop_id TEXT PRIMARY KEY,
  balance INT NOT NULL DEFAULT 0,
  credit_limit INT NOT NULL DEFAULT 20000 CHECK (credit_limit >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.wallet_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id TEXT NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  type TEXT NOT NULL CHECK (type IN ('welcome', 'topup', 'commission', 'commission_waived', 'refund', 'adjust')),
  amount INT NOT NULL,          -- bertanda: + menambah saldo, − memotong
  balance_after INT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS wallet_ledger_shop_idx ON public.wallet_ledger (shop_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS wallet_ledger_order_once ON public.wallet_ledger (order_id, type)
  WHERE order_id IS NOT NULL AND type IN ('commission', 'commission_waived');

CREATE TABLE IF NOT EXISTS public.wallet_topups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id TEXT NOT NULL,
  owner_id UUID NOT NULL DEFAULT auth.uid(),
  amount INT NOT NULL CHECK (amount >= 10000 AND amount <= 5000000),
  unique_code INT NOT NULL DEFAULT 0 CHECK (unique_code BETWEEN 0 AND 999),
  payable INT NOT NULL DEFAULT 0,   -- amount + unique_code; jumlah ini yang masuk saldo
  proof_path TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS wallet_topups_pending_idx ON public.wallet_topups (status, created_at) WHERE status = 'pending';
CREATE UNIQUE INDEX IF NOT EXISTS wallet_topups_one_pending ON public.wallet_topups (shop_id) WHERE status = 'pending';

ALTER TABLE public.shop_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_topups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner views own wallet" ON public.shop_wallets;
CREATE POLICY "Owner views own wallet" ON public.shop_wallets FOR SELECT USING (public.is_shop_owner(shop_id));
DROP POLICY IF EXISTS "Owner views own wallet ledger" ON public.wallet_ledger;
CREATE POLICY "Owner views own wallet ledger" ON public.wallet_ledger FOR SELECT USING (public.is_shop_owner(shop_id));
DROP POLICY IF EXISTS "Owner views own topups" ON public.wallet_topups;
CREATE POLICY "Owner views own topups" ON public.wallet_topups FOR SELECT USING (public.is_shop_owner(shop_id));
DROP POLICY IF EXISTS "Owner requests topup" ON public.wallet_topups;
CREATE POLICY "Owner requests topup" ON public.wallet_topups
  FOR INSERT WITH CHECK (owner_id = auth.uid() AND public.is_shop_owner(shop_id) AND status = 'pending');

GRANT SELECT ON public.shop_wallets, public.wallet_ledger TO authenticated;
GRANT SELECT, INSERT ON public.wallet_topups TO authenticated;


-- Buat dompet saat pertama dibutuhkan (dengan saldo awal gratis)
CREATE OR REPLACE FUNCTION public.ensure_shop_wallet(p_shop_id TEXT)
RETURNS public.shop_wallets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  w public.shop_wallets%ROWTYPE;
  s public.platform_settings%ROWTYPE;
BEGIN
  SELECT * INTO w FROM public.shop_wallets WHERE shop_id = p_shop_id FOR UPDATE;
  IF FOUND THEN RETURN w; END IF;
  SELECT * INTO s FROM public.platform_settings LIMIT 1;
  INSERT INTO public.shop_wallets (shop_id, balance, credit_limit)
  VALUES (p_shop_id, COALESCE(s.welcome_credit, 0), COALESCE(s.default_credit_limit, 20000))
  ON CONFLICT (shop_id) DO NOTHING;
  SELECT * INTO w FROM public.shop_wallets WHERE shop_id = p_shop_id FOR UPDATE;
  IF COALESCE(s.welcome_credit, 0) > 0 THEN
    INSERT INTO public.wallet_ledger (shop_id, type, amount, balance_after, note)
    VALUES (p_shop_id, 'welcome', s.welcome_credit, w.balance, 'Saldo awal gratis untuk mitra baru');
  END IF;
  RETURN w;
END;
$$;


-- Hanya dipakai trigger & RPC internal, tidak boleh dipanggil langsung dari aplikasi
REVOKE ALL ON FUNCTION public.ensure_shop_wallet(TEXT) FROM PUBLIC, anon, authenticated;


-- ════════════════════════════════════════════════════════════
-- 3. POTONG KOMISI SAAT PESANAN MULAI DIPROSES
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.orders_commission()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  s public.platform_settings%ROWTYPE;
  w public.shop_wallets%ROWTYPE;
  v_new INT;
BEGIN
  -- Hanya pesanan aplikasi (punya akun pelanggan), saat Menunggu → Dicuci
  IF NEW.user_id IS NULL OR OLD.status <> 'pending' OR NEW.status <> 'washing' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO s FROM public.platform_settings LIMIT 1;
  w := public.ensure_shop_wallet(NEW.shop_id);

  IF COALESCE(s.commission_active, FALSE) AND COALESCE(s.commission_amount, 0) > 0 THEN
    v_new := w.balance - s.commission_amount;
    INSERT INTO public.wallet_ledger (shop_id, order_id, type, amount, balance_after, note)
    VALUES (NEW.shop_id, NEW.id, 'commission', -s.commission_amount, v_new, 'Komisi Washora')
    ON CONFLICT DO NOTHING;
    IF FOUND THEN
      UPDATE public.shop_wallets SET balance = v_new, updated_at = NOW() WHERE shop_id = NEW.shop_id;
    END IF;
  ELSE
    INSERT INTO public.wallet_ledger (shop_id, order_id, type, amount, balance_after, note)
    VALUES (NEW.shop_id, NEW.id, 'commission_waived', 0, w.balance,
            'Gratis masa pengenalan (normal Rp ' || COALESCE(s.commission_amount, 0) || ')')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS orders_commission ON public.orders;
CREATE TRIGGER orders_commission
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_commission();


-- Outlet menerima pesanan aplikasi selama saldo belum melewati batas kredit
CREATE OR REPLACE FUNCTION public.shop_accepting_orders(p_shop_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
    WHEN NOT COALESCE((SELECT commission_active FROM public.platform_settings LIMIT 1), FALSE) THEN TRUE
    ELSE COALESCE((
      SELECT w.balance - (SELECT commission_amount FROM public.platform_settings LIMIT 1) >= -w.credit_limit
      FROM public.shop_wallets w WHERE w.shop_id = p_shop_id), TRUE)
  END;
$$;
GRANT EXECUTE ON FUNCTION public.shop_accepting_orders(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.orders_check_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND NEW.user_id = auth.uid() AND NOT public.shop_accepting_orders(NEW.shop_id) THEN
    RAISE EXCEPTION 'Outlet sedang tidak menerima pesanan aplikasi. Coba outlet lain.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS orders_check_wallet ON public.orders;
CREATE TRIGGER orders_check_wallet
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_check_wallet();


-- ════════════════════════════════════════════════════════════
-- 4. ISI SALDO
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.wallet_topups_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  is_admin BOOLEAN := auth.uid() IS NULL;  -- Table Editor / service role
  w public.shop_wallets%ROWTYPE;
  v_new INT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT is_admin THEN
      NEW.status := 'pending'; NEW.decided_at := NULL; NEW.admin_note := NULL;
      -- Kode unik dibuat aplikasi saat QR ditampilkan (mitra membayar amount + kode);
      -- admin tetap mencocokkan nominal yang benar-benar masuk sebelum menyetujui.
      IF NEW.proof_path IS NULL OR NEW.proof_path NOT LIKE NEW.shop_id || '/%' THEN
        RAISE EXCEPTION 'Unggah bukti pembayaran terlebih dahulu' USING ERRCODE = '22023';
      END IF;
    END IF;
    NEW.payable := NEW.amount + NEW.unique_code;
    RETURN NEW;
  END IF;

  -- UPDATE: hanya admin yang boleh memutuskan
  IF NOT is_admin THEN RAISE EXCEPTION 'Akses ditolak' USING ERRCODE = '42501'; END IF;
  NEW.amount := OLD.amount; NEW.unique_code := OLD.unique_code; NEW.payable := OLD.payable;
  NEW.shop_id := OLD.shop_id; NEW.owner_id := OLD.owner_id;
  IF NEW.status IS DISTINCT FROM OLD.status AND OLD.status = 'pending' THEN
    NEW.decided_at := NOW();
    IF NEW.status = 'approved' THEN
      w := public.ensure_shop_wallet(NEW.shop_id);
      v_new := w.balance + NEW.payable;
      UPDATE public.shop_wallets SET balance = v_new, updated_at = NOW() WHERE shop_id = NEW.shop_id;
      INSERT INTO public.wallet_ledger (shop_id, type, amount, balance_after, note)
      VALUES (NEW.shop_id, 'topup', NEW.payable, v_new, 'Isi saldo dikonfirmasi');
    END IF;
    INSERT INTO public.notifications (user_id, status, title, body)
    VALUES (NEW.owner_id,
            CASE WHEN NEW.status = 'approved' THEN 'wallet_topup_ok' ELSE 'wallet_topup_rejected' END,
            CASE WHEN NEW.status = 'approved' THEN 'Isi saldo komisi berhasil' ELSE 'Isi saldo komisi ditolak' END,
            CASE WHEN NEW.status = 'approved'
                 THEN 'Saldo bertambah Rp ' || REPLACE(TO_CHAR(NEW.payable, 'FM999,999,999'), ',', '.') || '.'
                 ELSE COALESCE(NULLIF(NEW.admin_note, ''), 'Bukti pembayaran tidak sesuai.') END);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Pengajuan ini sudah diputuskan' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS wallet_topups_guard ON public.wallet_topups;
CREATE TRIGGER wallet_topups_guard
  BEFORE INSERT OR UPDATE ON public.wallet_topups
  FOR EACH ROW EXECUTE FUNCTION public.wallet_topups_guard();

-- Bukti isi saldo (privat): {shop_id}/{waktu}.jpg
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('wallet-proofs', 'wallet-proofs', FALSE, 3145728, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Owner uploads wallet proof" ON storage.objects;
CREATE POLICY "Owner uploads wallet proof" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'wallet-proofs' AND public.is_shop_owner((storage.foldername(name))[1]));
DROP POLICY IF EXISTS "Owner views wallet proof" ON storage.objects;
CREATE POLICY "Owner views wallet proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'wallet-proofs' AND public.is_shop_owner((storage.foldername(name))[1]));


-- ════════════════════════════════════════════════════════════
-- 5. RINGKASAN DOMPET UNTUK DASHBOARD MITRA
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.my_wallet(p_shop_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  w public.shop_wallets%ROWTYPE;
  s public.platform_settings%ROWTYPE;
  v_waived INT;
  v_month INT;
BEGIN
  IF NOT public.is_shop_owner(p_shop_id) THEN
    RAISE EXCEPTION 'Akses ditolak' USING ERRCODE = '42501';
  END IF;
  w := public.ensure_shop_wallet(p_shop_id);
  SELECT * INTO s FROM public.platform_settings LIMIT 1;
  SELECT COUNT(*) INTO v_waived FROM public.wallet_ledger WHERE shop_id = p_shop_id AND type = 'commission_waived';
  SELECT COUNT(*) INTO v_month FROM public.wallet_ledger
  WHERE shop_id = p_shop_id AND type IN ('commission', 'commission_waived')
    AND created_at >= date_trunc('month', NOW() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta';
  RETURN jsonb_build_object(
    'balance', w.balance,
    'credit_limit', w.credit_limit,
    'commission_amount', s.commission_amount,
    'commission_active', s.commission_active,
    'accepting_orders', public.shop_accepting_orders(p_shop_id),
    'waived_orders', v_waived,
    'waived_amount', v_waived * s.commission_amount,
    'orders_this_month', v_month
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.my_wallet(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
