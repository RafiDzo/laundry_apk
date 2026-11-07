-- ============================================================
-- WASHORA — FOTO PROFIL OUTLET
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- Aman dijalankan berulang (idempotent).
--
-- Bucket publik 'shop-photos' (foto outlet memang tampil untuk semua pelanggan).
-- Path: {shop_id}/profile_{waktu}.jpg — hanya pemilik outlet yang boleh
-- mengunggah / mengganti / menghapus foto di folder outletnya.
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('shop-photos', 'shop-photos', TRUE, 3145728, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- is_shop_owner(TEXT) sudah dibuat di supabase_install_all.sql; dibuat ulang di sini agar mandiri
CREATE OR REPLACE FUNCTION public.is_shop_owner(p_shop_id TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id::text = p_shop_id AND owner_id = auth.uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

DROP POLICY IF EXISTS "Anyone can view shop photos" ON storage.objects;
CREATE POLICY "Anyone can view shop photos" ON storage.objects
  FOR SELECT USING (bucket_id = 'shop-photos');

DROP POLICY IF EXISTS "Owner uploads shop photos" ON storage.objects;
CREATE POLICY "Owner uploads shop photos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'shop-photos' AND public.is_shop_owner((storage.foldername(name))[1]));

DROP POLICY IF EXISTS "Owner updates shop photos" ON storage.objects;
CREATE POLICY "Owner updates shop photos" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'shop-photos' AND public.is_shop_owner((storage.foldername(name))[1]));

DROP POLICY IF EXISTS "Owner deletes shop photos" ON storage.objects;
CREATE POLICY "Owner deletes shop photos" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'shop-photos' AND public.is_shop_owner((storage.foldername(name))[1]));
