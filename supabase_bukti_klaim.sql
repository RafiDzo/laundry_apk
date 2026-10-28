-- ============================================================
-- WASHORA — BUKTI FOTO, SERAH TERIMA & KLAIM KERUSAKAN
-- Jalankan SETELAH supabase_install_all.sql & supabase_notifications.sql.
-- Aman dijalankan berulang (idempotent).
--
-- Alur:
--   1. Penerimaan  : mitra wajib foto cucian sebelum status bisa diproses
--   2. Serah terima: status "Diantar" hanya lewat kode 4 digit milik
--                    pelanggan (+ foto) atau konfirmasi pelanggan sendiri
--   3. Klaim       : maks. 2x24 jam setelah diterima, pelanggan lapor
--                    kerusakan + foto; mitra verifikasi; pelanggan bisa banding
-- Semua aturan dikunci di database, tidak hanya di tampilan aplikasi.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. KOLOM BARU DI ORDERS
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS intake_note TEXT;          -- catatan kondisi saat diterima
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS intake_item_count INT;     -- jumlah item saat diterima
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS intake_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS done_at TIMESTAMPTZ;       -- kapan status jadi 'done'
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;   -- kapan pelanggan menerima
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS received_by TEXT;          -- 'code' | 'customer' | 'walkin' | 'auto'


-- ════════════════════════════════════════════════════════════
-- 2. HELPER AKSES
-- ════════════════════════════════════════════════════════════
-- Pemilik pesanan atau mitra pemilik outletnya
CREATE OR REPLACE FUNCTION public.can_access_order(p_order_id TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id::text = p_order_id
      AND (o.user_id = auth.uid() OR public.is_shop_owner(o.shop_id))
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- Foto penerimaan & serah terima: hanya mitra.
-- Foto klaim: hanya pelanggan, dan hanya dalam 2x24 jam setelah diterima.
CREATE OR REPLACE FUNCTION public.can_upload_order_photo(p_order_id TEXT, p_stage TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id::text = p_order_id
      AND (
        (p_stage IN ('intake', 'handover') AND public.is_shop_owner(o.shop_id))
        OR (p_stage = 'claim'
            AND o.user_id = auth.uid()
            AND o.status = 'delivered'
            AND o.received_at > NOW() - INTERVAL '48 hours')
      )
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;


-- ════════════════════════════════════════════════════════════
-- 3. STORAGE: bucket privat untuk foto bukti
--    Path file: {order_id}/{intake|handover|claim}/{nama}.jpg
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('order-photos', 'order-photos', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Order photos: read" ON storage.objects;
CREATE POLICY "Order photos: read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'order-photos'
         AND public.can_access_order((storage.foldername(name))[1]));

DROP POLICY IF EXISTS "Order photos: upload" ON storage.objects;
CREATE POLICY "Order photos: upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'order-photos'
              AND public.can_upload_order_photo((storage.foldername(name))[1],
                                                (storage.foldername(name))[2]));
-- Sengaja TIDAK ada policy UPDATE/DELETE: foto bukti tidak bisa diubah/dihapus.


-- ════════════════════════════════════════════════════════════
-- 4. TABEL ORDER_PHOTOS (daftar foto bukti per pesanan)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.order_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  stage TEXT NOT NULL CHECK (stage IN ('intake', 'handover', 'claim')),
  storage_path TEXT NOT NULL,
  uploaded_by UUID DEFAULT auth.uid(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS order_photos_order_idx ON public.order_photos(order_id, stage);

ALTER TABLE public.order_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Order photos rows: read" ON public.order_photos;
CREATE POLICY "Order photos rows: read" ON public.order_photos
  FOR SELECT USING (public.can_access_order(order_id::text));

DROP POLICY IF EXISTS "Order photos rows: insert" ON public.order_photos;
CREATE POLICY "Order photos rows: insert" ON public.order_photos
  FOR INSERT WITH CHECK (uploaded_by = auth.uid()
                         AND public.can_upload_order_photo(order_id::text, stage));

GRANT SELECT, INSERT ON public.order_photos TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 5. KODE SERAH TERIMA (hanya bisa dilihat pelanggan, BUKAN mitra)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.order_handover_codes (
  order_id UUID PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  failed_attempts INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.order_handover_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Handover code: customer only" ON public.order_handover_codes;
CREATE POLICY "Handover code: customer only" ON public.order_handover_codes
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.user_id = auth.uid()
  ));

GRANT SELECT ON public.order_handover_codes TO authenticated;

CREATE OR REPLACE FUNCTION public.create_handover_code()
RETURNS trigger AS $$
BEGIN
  IF NEW.user_id IS NOT NULL THEN
    INSERT INTO public.order_handover_codes (order_id, code)
    VALUES (NEW.id, LPAD(FLOOR(RANDOM() * 10000)::INT::TEXT, 4, '0'))
    ON CONFLICT (order_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_order_create_handover_code ON public.orders;
CREATE TRIGGER on_order_create_handover_code
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.create_handover_code();

-- Kode untuk pesanan yang sudah ada
INSERT INTO public.order_handover_codes (order_id, code)
SELECT o.id, LPAD(FLOOR(RANDOM() * 10000)::INT::TEXT, 4, '0')
FROM public.orders o
WHERE o.user_id IS NOT NULL
ON CONFLICT (order_id) DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 6. PENJAGA STATUS PESANAN
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.guard_order_status()
RETURNS trigger AS $$
DECLARE
  v_handover_ok BOOLEAN := COALESCE(current_setting('washora.handover_ok', true), '') = 'on';
BEGIN
  -- a. Wajib foto penerimaan sebelum cucian diproses
  IF OLD.status = 'pending' AND NEW.status IN ('washing', 'drying', 'done', 'delivered')
     AND NOT EXISTS (SELECT 1 FROM public.order_photos
                     WHERE order_id = NEW.id AND stage = 'intake') THEN
    RAISE EXCEPTION 'INTAKE_PHOTO_REQUIRED'
      USING HINT = 'Foto kondisi cucian saat diterima wajib diunggah sebelum diproses.';
  END IF;

  -- b. "Diantar" & data penerimaan hanya lewat confirm_handover / confirm_received
  IF NOT v_handover_ok THEN
    IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' THEN
      RAISE EXCEPTION 'HANDOVER_REQUIRED'
        USING HINT = 'Gunakan kode serah terima dari pelanggan.';
    END IF;
    IF NEW.received_at IS DISTINCT FROM OLD.received_at
       OR NEW.received_by IS DISTINCT FROM OLD.received_by THEN
      RAISE EXCEPTION 'RECEIVED_FIELDS_LOCKED';
    END IF;
  END IF;

  -- c. Pesanan yang sudah diterima tidak bisa diubah statusnya lagi
  IF OLD.status = 'delivered' AND NEW.status IS DISTINCT FROM 'delivered' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_RECEIVED';
  END IF;

  -- d. Catat waktu selesai diproses (dasar konfirmasi otomatis 2x24 jam)
  IF NEW.status = 'done' AND OLD.status IS DISTINCT FROM 'done' THEN
    NEW.done_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_order_guard_status ON public.orders;
CREATE TRIGGER on_order_guard_status
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.guard_order_status();


-- ════════════════════════════════════════════════════════════
-- 7. RPC SERAH TERIMA
-- ════════════════════════════════════════════════════════════
-- Mitra: masukkan kode dari pelanggan (+ wajib sudah unggah foto serah terima).
-- Pesanan walk-in (tanpa akun) cukup foto serah terima.
-- Hasil: OK | NOT_ALLOWED | NOT_READY | PHOTO_REQUIRED | NO_CODE | LOCKED | WRONG_CODE
CREATE OR REPLACE FUNCTION public.confirm_handover(p_order_id UUID, p_code TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_code  public.order_handover_codes%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR NOT public.is_shop_owner(v_order.shop_id) THEN
    RETURN 'NOT_ALLOWED';
  END IF;
  IF v_order.status <> 'done' THEN
    RETURN 'NOT_READY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.order_photos
                 WHERE order_id = p_order_id AND stage = 'handover') THEN
    RETURN 'PHOTO_REQUIRED';
  END IF;

  IF v_order.user_id IS NOT NULL THEN
    SELECT * INTO v_code FROM public.order_handover_codes
    WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RETURN 'NO_CODE'; END IF;
    IF v_code.failed_attempts >= 5 THEN RETURN 'LOCKED'; END IF;
    IF v_code.code IS DISTINCT FROM TRIM(COALESCE(p_code, '')) THEN
      UPDATE public.order_handover_codes
      SET failed_attempts = failed_attempts + 1 WHERE order_id = p_order_id;
      RETURN 'WRONG_CODE';
    END IF;
  END IF;

  PERFORM set_config('washora.handover_ok', 'on', true);
  UPDATE public.orders
  SET status = 'delivered',
      received_at = NOW(),
      received_by = CASE WHEN v_order.user_id IS NULL THEN 'walkin' ELSE 'code' END
  WHERE id = p_order_id;
  PERFORM set_config('washora.handover_ok', 'off', true);
  RETURN 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Pelanggan: tekan "Sudah Diterima"
-- Hasil: OK | NOT_ALLOWED | NOT_READY
CREATE OR REPLACE FUNCTION public.confirm_received(p_order_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR v_order.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN 'NOT_ALLOWED';
  END IF;
  IF v_order.status <> 'done' THEN
    RETURN 'NOT_READY';
  END IF;

  PERFORM set_config('washora.handover_ok', 'on', true);
  UPDATE public.orders
  SET status = 'delivered', received_at = NOW(), received_by = 'customer'
  WHERE id = p_order_id;
  PERFORM set_config('washora.handover_ok', 'off', true);
  RETURN 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Konfirmasi otomatis: pesanan 'done' > 2x24 jam tanpa konfirmasi.
-- OPSIONAL — perlu dijadwalkan (Supabase Dashboard → Integrations → Cron),
-- misalnya tiap jam:  SELECT public.auto_confirm_received();
CREATE OR REPLACE FUNCTION public.auto_confirm_received()
RETURNS INT AS $$
DECLARE
  v_count INT;
BEGIN
  PERFORM set_config('washora.handover_ok', 'on', true);
  UPDATE public.orders
  SET status = 'delivered', received_at = NOW(), received_by = 'auto'
  WHERE status = 'done' AND done_at < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM set_config('washora.handover_ok', 'off', true);
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.auto_confirm_received() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_handover(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_received(UUID) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 8. KLAIM KERUSAKAN
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.damage_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Tanpa ON DELETE: pesanan yang punya klaim tidak bisa dihapus
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id),
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES public.users(id),
  shop_id TEXT NOT NULL,
  description TEXT NOT NULL CHECK (LENGTH(TRIM(description)) >= 10),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'appealed',
                      'appeal_approved', 'appeal_rejected')),
  resolution TEXT CHECK (resolution IN ('rewash', 'compensation')),
  compensation_amount INT CHECK (compensation_amount >= 0),
  owner_note TEXT,
  appeal_reason TEXT,
  admin_note TEXT,               -- diisi admin Washora saat memutuskan banding
  created_at TIMESTAMPTZ DEFAULT NOW(),
  decided_at TIMESTAMPTZ,
  appealed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS damage_claims_shop_idx ON public.damage_claims(shop_id, created_at DESC);

ALTER TABLE public.damage_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Claims: read" ON public.damage_claims;
CREATE POLICY "Claims: read" ON public.damage_claims
  FOR SELECT USING (user_id = auth.uid() OR public.is_shop_owner(shop_id));

-- Pelanggan: hanya pesanannya sendiri, status Diantar, maks. 2x24 jam setelah diterima,
-- dan wajib sudah unggah minimal 1 foto bukti klaim
DROP POLICY IF EXISTS "Claims: customer create" ON public.damage_claims;
CREATE POLICY "Claims: customer create" ON public.damage_claims
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.user_id = auth.uid()
        AND o.shop_id = damage_claims.shop_id
        AND o.status = 'delivered'
        AND o.received_at > NOW() - INTERVAL '48 hours'
    )
    AND EXISTS (SELECT 1 FROM public.order_photos p
                WHERE p.order_id = damage_claims.order_id AND p.stage = 'claim')
  );

-- Tidak ada policy UPDATE: perubahan klaim hanya lewat RPC di bawah
GRANT SELECT, INSERT ON public.damage_claims TO authenticated;

-- Mitra memutuskan klaim. Hasil: OK | NOT_ALLOWED | NOT_PENDING | INVALID
CREATE OR REPLACE FUNCTION public.decide_claim(
  p_claim_id UUID, p_approve BOOLEAN,
  p_resolution TEXT DEFAULT NULL, p_amount INT DEFAULT NULL, p_note TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
  v_claim public.damage_claims%ROWTYPE;
BEGIN
  SELECT * INTO v_claim FROM public.damage_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_shop_owner(v_claim.shop_id) THEN RETURN 'NOT_ALLOWED'; END IF;
  IF v_claim.status <> 'pending' THEN RETURN 'NOT_PENDING'; END IF;

  IF p_approve THEN
    IF p_resolution NOT IN ('rewash', 'compensation')
       OR (p_resolution = 'compensation' AND COALESCE(p_amount, 0) <= 0) THEN
      RETURN 'INVALID';
    END IF;
    UPDATE public.damage_claims
    SET status = 'approved', resolution = p_resolution,
        compensation_amount = CASE WHEN p_resolution = 'compensation' THEN p_amount END,
        owner_note = NULLIF(TRIM(COALESCE(p_note, '')), ''), decided_at = NOW()
    WHERE id = p_claim_id;
  ELSE
    -- Penolakan wajib disertai alasan
    IF LENGTH(TRIM(COALESCE(p_note, ''))) < 5 THEN RETURN 'INVALID'; END IF;
    UPDATE public.damage_claims
    SET status = 'rejected', owner_note = TRIM(p_note), decided_at = NOW()
    WHERE id = p_claim_id;
  END IF;
  RETURN 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Pelanggan mengajukan banding atas klaim yang ditolak.
-- Hasil: OK | NOT_ALLOWED | NOT_REJECTED | INVALID
CREATE OR REPLACE FUNCTION public.appeal_claim(p_claim_id UUID, p_reason TEXT)
RETURNS TEXT AS $$
DECLARE
  v_claim public.damage_claims%ROWTYPE;
BEGIN
  SELECT * INTO v_claim FROM public.damage_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR v_claim.user_id IS DISTINCT FROM auth.uid() THEN RETURN 'NOT_ALLOWED'; END IF;
  IF v_claim.status <> 'rejected' THEN RETURN 'NOT_REJECTED'; END IF;
  IF LENGTH(TRIM(COALESCE(p_reason, ''))) < 10 THEN RETURN 'INVALID'; END IF;

  UPDATE public.damage_claims
  SET status = 'appealed', appeal_reason = TRIM(p_reason), appealed_at = NOW()
  WHERE id = p_claim_id;
  RETURN 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.decide_claim(UUID, BOOLEAN, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.appeal_claim(UUID, TEXT) TO authenticated;

-- Admin Washora memutuskan banding (sementara lewat SQL Editor, Tahap 2 = dashboard admin):
--   UPDATE public.damage_claims
--   SET status = 'appeal_approved',  -- atau 'appeal_rejected'
--       resolution = 'compensation', compensation_amount = 50000,
--       admin_note = 'Bukti foto valid', decided_at = NOW()
--   WHERE id = '...';


-- ════════════════════════════════════════════════════════════
-- 9. NOTIFIKASI KLAIM (memakai tabel notifications yang sudah ada)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_claim_change()
RETURNS trigger AS $$
DECLARE
  v_title TEXT;
  v_body  TEXT;
  v_resolution TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_resolution := CASE NEW.resolution
    WHEN 'rewash' THEN 'Outlet akan mencuci ulang cucianmu tanpa biaya.'
    WHEN 'compensation' THEN 'Kamu akan menerima ganti rugi Rp '
                             || REPLACE(TO_CHAR(COALESCE(NEW.compensation_amount, 0), 'FM999,999,999'), ',', '.') || '.'
    ELSE ''
  END;

  CASE NEW.status
    WHEN 'pending' THEN
      v_title := 'Klaim kerusakan terkirim';
      v_body  := 'Outlet akan memeriksa foto bukti dan memberi keputusan.';
    WHEN 'approved' THEN
      v_title := 'Klaim disetujui';
      v_body  := v_resolution;
    WHEN 'rejected' THEN
      v_title := 'Klaim ditolak';
      v_body  := 'Alasan: ' || COALESCE(NEW.owner_note, '-') || '. Kamu bisa mengajukan banding.';
    WHEN 'appealed' THEN
      v_title := 'Banding diajukan';
      v_body  := 'Tim Washora akan meninjau bukti dari kedua pihak.';
    WHEN 'appeal_approved' THEN
      v_title := 'Banding disetujui';
      v_body  := v_resolution;
    WHEN 'appeal_rejected' THEN
      v_title := 'Banding ditolak';
      v_body  := 'Keputusan akhir: ' || COALESCE(NEW.admin_note, 'klaim tidak dapat diterima') || '.';
    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (user_id, order_id, status, title, body)
  VALUES (NEW.user_id, NEW.order_id, 'claim_' || NEW.status, v_title, v_body);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_claim_notify ON public.damage_claims;
CREATE TRIGGER on_claim_notify
  AFTER INSERT OR UPDATE OF status ON public.damage_claims
  FOR EACH ROW EXECUTE PROCEDURE public.notify_claim_change();


-- ════════════════════════════════════════════════════════════
-- 10. HAPUS PESANAN: hanya yang dibatalkan
--     (sebelumnya mitra bisa menghapus pesanan apa pun, termasuk yang
--      sudah diterima — itu bisa menghilangkan bukti foto)
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Owner can delete shop orders" ON public.orders;
CREATE POLICY "Owner can delete shop orders" ON public.orders
  FOR DELETE USING (public.is_shop_owner(shop_id) AND status = 'cancelled');


-- ════════════════════════════════════════════════════════════
-- 11. REALTIME
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
                   AND tablename = 'damage_claims') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.damage_claims;
  END IF;
END;
$$;
