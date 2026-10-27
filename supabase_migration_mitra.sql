-- ============================================================
-- MIGRASI: Dukungan Dashboard Mitra / Owner
-- Jalankan SETELAH supabase_schema.sql & supabase_trigger.sql
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query
-- Aman dijalankan ulang (idempotent).
-- ============================================================

-- ──────────────────────────────────────────
-- 1. PEMILIK TOKO
-- ──────────────────────────────────────────
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS shops_owner_id_idx ON public.shops(owner_id);

-- ──────────────────────────────────────────
-- 2. DATA PELANGGAN DI PESANAN
--    - customer_name / customer_phone: supaya owner bisa melihat nama
--      pelanggan tanpa perlu akses ke tabel users.
--    - user_id boleh kosong untuk pesanan walk-in (kasir) yang
--      pelanggannya tidak punya akun.
-- ──────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE public.orders ALTER COLUMN user_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS orders_shop_id_idx ON public.orders(shop_id);

-- Jenis pengiriman: 'pickup' (dijemput kurir) atau 'dropoff' (antar sendiri ke outlet).
-- Dipakai halaman Lacak & Riwayat untuk membuka tampilan pelacakan yang sesuai.
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_type TEXT NOT NULL DEFAULT 'pickup';

-- Tambah status 'cancelled' (fitur Batalkan Pesanan di dashboard mitra)
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'washing', 'drying', 'done', 'delivered', 'cancelled'));

-- Isi customer_name otomatis dari profil user saat pesanan dibuat
CREATE OR REPLACE FUNCTION public.fill_order_customer_name()
RETURNS trigger AS $$
BEGIN
  IF NEW.customer_name IS NULL AND NEW.user_id IS NOT NULL THEN
    SELECT name INTO NEW.customer_name FROM public.users WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_order_fill_customer ON public.orders;
CREATE TRIGGER on_order_fill_customer
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.fill_order_customer_name();

-- Isi nama untuk pesanan lama
UPDATE public.orders o
SET customer_name = u.name
FROM public.users u
WHERE o.user_id = u.id AND o.customer_name IS NULL;

-- ──────────────────────────────────────────
-- 3. HELPER: apakah user yang login adalah pemilik toko ini?
--    (shop_id di orders bertipe TEXT, jadi dibandingkan sebagai teks)
-- ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_shop_owner(p_shop_id TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id::text = p_shop_id AND owner_id = auth.uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- ──────────────────────────────────────────
-- 4. RLS: ORDERS untuk owner
-- ──────────────────────────────────────────
DROP POLICY IF EXISTS "Owner can view shop orders" ON public.orders;
CREATE POLICY "Owner can view shop orders" ON public.orders
  FOR SELECT USING (public.is_shop_owner(shop_id));

DROP POLICY IF EXISTS "Owner can update shop orders" ON public.orders;
CREATE POLICY "Owner can update shop orders" ON public.orders
  FOR UPDATE USING (public.is_shop_owner(shop_id))
  WITH CHECK (public.is_shop_owner(shop_id));

-- Owner boleh input pesanan walk-in untuk tokonya sendiri
DROP POLICY IF EXISTS "Owner can create shop orders" ON public.orders;
CREATE POLICY "Owner can create shop orders" ON public.orders
  FOR INSERT WITH CHECK (public.is_shop_owner(shop_id));

-- Owner boleh menghapus pesanan yang dibatalkan di tokonya sendiri
DROP POLICY IF EXISTS "Owner can delete shop orders" ON public.orders;
CREATE POLICY "Owner can delete shop orders" ON public.orders
  FOR DELETE USING (public.is_shop_owner(shop_id));

-- ──────────────────────────────────────────
-- 5. RLS: SHOPS — owner boleh mengubah data tokonya sendiri
-- ──────────────────────────────────────────
DROP POLICY IF EXISTS "Owner can update own shop" ON public.shops;
CREATE POLICY "Owner can update own shop" ON public.shops
  FOR UPDATE USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- Mitra boleh mendaftarkan outlet atas namanya sendiri (form "Daftarkan Outlet")
DROP POLICY IF EXISTS "Owner can create own shop" ON public.shops;
CREATE POLICY "Owner can create own shop" ON public.shops
  FOR INSERT WITH CHECK (
    owner_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'owner')
  );

-- ──────────────────────────────────────────
-- 6. TABEL PETTY CASH (kas kecil per toko)
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.petty_cash (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL CHECK (type IN ('in', 'out')),
  amount INT NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.petty_cash ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner can view petty cash" ON public.petty_cash;
CREATE POLICY "Owner can view petty cash" ON public.petty_cash
  FOR SELECT USING (public.is_shop_owner(shop_id::text));

DROP POLICY IF EXISTS "Owner can add petty cash" ON public.petty_cash;
CREATE POLICY "Owner can add petty cash" ON public.petty_cash
  FOR INSERT WITH CHECK (public.is_shop_owner(shop_id::text));

-- Owner juga boleh mengoreksi / menghapus catatan kas yang salah input
DROP POLICY IF EXISTS "Owner can update petty cash" ON public.petty_cash;
CREATE POLICY "Owner can update petty cash" ON public.petty_cash
  FOR UPDATE USING (public.is_shop_owner(shop_id::text))
  WITH CHECK (public.is_shop_owner(shop_id::text));

DROP POLICY IF EXISTS "Owner can delete petty cash" ON public.petty_cash;
CREATE POLICY "Owner can delete petty cash" ON public.petty_cash
  FOR DELETE USING (public.is_shop_owner(shop_id::text));

-- ──────────────────────────────────────────
-- 7. IZIN TABEL (GRANT)
--    Tanpa ini, user yang login mendapat error 42501
--    "permission denied for table ..." sebelum RLS sempat dicek.
--    Akses per-baris tetap dibatasi oleh policy RLS di atas.
-- ──────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.shops TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.petty_cash TO authenticated;

-- ──────────────────────────────────────────
-- 8. SEED DATA AWAL (idempotent)
--    Policy INSERT shops hanya mengizinkan owner, sehingga seeding tidak
--    bisa dilakukan dari aplikasi (ditolak RLS). Seed dijalankan di sini
--    dengan hak akses SQL Editor sehingga lolos RLS.
-- ──────────────────────────────────────────
INSERT INTO public.shops
  (name, rating, distance, queue_text, address, open_hours, image_url, price_per_kg, services)
SELECT
  v.name, v.rating, v.distance, v.queue_text, v.address, v.open_hours, v.image_url, v.price_per_kg, v.services
FROM (VALUES
  (
    'CleanPro Kemang',
    4.9,
    '350m',
    'ANTRIAN: 2 (CEPAT)',
    'Jl. Kemang Raya No. 12A',
    '08:00 - 21:00',
    'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=500&auto=format&fit=crop&q=80',
    10000,
    '[{"id":"s1","name":"Cuci Kiloan","description":"Regular wash & fold","price":10000,"unit":"/ kg","iconName":"local_laundry_service"},{"id":"s2","name":"Cuci Express","description":"Selesai dalam 4 jam","price":25000,"unit":"/ kg","iconName":"bolt"}]'::jsonb
  ),
  (
    'Lavender Laundry',
    4.2,
    '450m',
    'ANTRIAN: 8 (SIBUK)',
    'Jl. Pangeran Antasari No. 88',
    '07:00 - 22:00',
    'https://images.unsplash.com/photo-1521656693074-0ef32e80a5d5?w=500&auto=format&fit=crop&q=80',
    8500,
    '[{"id":"s3","name":"Cuci Kiloan Hemat","description":"Regular wash (3 hari)","price":8500,"unit":"/ kg","iconName":"local_laundry_service"},{"id":"s4","name":"Setrika Saja","description":"Layanan setrika rapi","price":6000,"unit":"/ kg","iconName":"iron"}]'::jsonb
  ),
  (
    'QuickWash Express',
    4.9,
    '150m',
    'ANTRIAN: 1 (LANCAR)',
    'Jl. Bangka Raya No. 15',
    '24 Jam',
    'https://images.unsplash.com/photo-1517677208171-0bc6725a3e60?w=500&auto=format&fit=crop&q=80',
    12000,
    '[{"id":"s5","name":"Cuci Kiloan Premium","description":"Deterjen premium & pelembut ekstra","price":12000,"unit":"/ kg","iconName":"local_laundry_service"},{"id":"s6","name":"Cuci Satuan","description":"Cuci jas, gaun, boneka, dll.","price":35000,"unit":"/ pcs","iconName":"dry_cleaning"}]'::jsonb
  )
) AS v(name, rating, distance, queue_text, address, open_hours, image_url, price_per_kg, services)
WHERE NOT EXISTS (
  SELECT 1 FROM public.shops s WHERE s.name = v.name
);

-- ──────────────────────────────────────────
-- 9. (OPSIONAL) HUBUNGKAN AKUN MITRA KE TOKO YANG SUDAH ADA
--    Tidak perlu jika mitra mendaftarkan outlet lewat form "Daftarkan
--    Outlet" di aplikasi. Pakai ini hanya untuk menautkan toko lama.
-- ──────────────────────────────────────────
-- UPDATE public.shops
-- SET owner_id = (SELECT id FROM public.users WHERE email = 'email-mitra@contoh.com')
-- WHERE name = 'CleanPro Kemang';
