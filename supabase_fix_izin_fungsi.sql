-- ============================================================
-- WASHORA — PERBAIKAN IZIN FUNGSI INTERNAL (jalankan sekali)
-- Fungsi-fungsi ini hanya untuk trigger/RPC internal. Secara bawaan PostgreSQL
-- mengizinkan PUBLIC (termasuk pengunjung tanpa login) menjalankannya.
-- Aman dijalankan berulang.
-- ============================================================
REVOKE ALL ON FUNCTION public.send_push(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.shop_owner_of(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ensure_shop_wallet(TEXT) FROM PUBLIC, anon, authenticated;

-- Izin tabel fcm_tokens (sempat hilang)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fcm_tokens TO authenticated;
GRANT ALL ON public.fcm_tokens TO service_role;
REVOKE ALL ON public.fcm_tokens FROM anon;
