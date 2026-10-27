-- ============================================================
-- WASHORA — INSTALASI DATABASE LENGKAP (SATU FILE)
-- Gabungan: supabase_schema.sql + supabase_trigger.sql + supabase_migration_mitra.sql
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- Hasil yang diharapkan: "Success. No rows returned".
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- BAGIAN 1: SCHEMA
-- ════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────
-- 1. TABEL USERS (profil pengguna)
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'owner')),
  membership_level TEXT DEFAULT 'Bronze' CHECK (membership_level IN ('Bronze', 'Silver', 'Gold')),
  total_orders INT DEFAULT 0,
  points INT DEFAULT 0,
  active_vouchers INT DEFAULT 0,
  profile_image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ──────────────────────────────────────────
-- 2. TABEL SHOPS (toko laundry)
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL DEFAULT '',
  rating FLOAT DEFAULT 0.0,
  distance TEXT DEFAULT '',
  queue_text TEXT DEFAULT '',
  address TEXT DEFAULT '',
  open_hours TEXT DEFAULT '',
  image_url TEXT DEFAULT '',
  price_per_kg INT DEFAULT 0,
  services JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ──────────────────────────────────────────
-- 3. TABEL ORDERS (pesanan)
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  shop_id TEXT NOT NULL DEFAULT '',
  shop_name TEXT DEFAULT '',
  items JSONB DEFAULT '[]'::jsonb,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'washing', 'drying', 'done', 'delivered', 'cancelled')),
  total_price INT DEFAULT 0,
  service_fee INT DEFAULT 0,
  notes TEXT,
  payment_method TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ──────────────────────────────────────────
-- 4. ROW LEVEL SECURITY (RLS)
-- ──────────────────────────────────────────
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Users: hanya bisa lihat dan edit profil sendiri
DROP POLICY IF EXISTS "Users can view own profile" ON public.users;
CREATE POLICY "Users can view own profile" ON public.users
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
CREATE POLICY "Users can update own profile" ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- Shops: semua user yang login bisa melihat toko
DROP POLICY IF EXISTS "Anyone can view shops" ON public.shops;
CREATE POLICY "Anyone can view shops" ON public.shops
  FOR SELECT USING (auth.role() = 'authenticated');

-- Orders: user hanya bisa lihat pesanannya sendiri
DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
CREATE POLICY "Users can view own orders" ON public.orders
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create orders" ON public.orders;
CREATE POLICY "Users can create orders" ON public.orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ──────────────────────────────────────────
-- 5. REALTIME (untuk stream orders)
-- ──────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- BAGIAN 2: TRIGGER (auto-create profil user saat sign up)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, name, email, role)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    COALESCE(new.raw_user_meta_data->>'role', 'customer')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ════════════════════════════════════════════════════════════
-- BAGIAN 3: MIGRASI DUKUNGAN DASHBOARD MITRA / OWNER
-- ════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────
-- 3.1 PEMILIK TOKO
-- ──────────────────────────────────────────
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS shops_owner_id_idx ON public.shops(owner_id);

-- ──────────────────────────────────────────
-- 3.2 DATA PELANGGAN DI PESANAN
-- ──────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE public.orders ALTER COLUMN user_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS orders_shop_id_idx ON public.orders(shop_id);

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_type TEXT NOT NULL DEFAULT 'pickup';

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'washing', 'drying', 'done', 'delivered', 'cancelled'));

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
-- 3.3 HELPER: apakah user yang login adalah pemilik toko ini?
-- ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_shop_owner(p_shop_id TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id::text = p_shop_id AND owner_id = auth.uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- ──────────────────────────────────────────
-- 3.4 RLS: ORDERS untuk owner
-- ──────────────────────────────────────────
DROP POLICY IF EXISTS "Owner can view shop orders" ON public.orders;
CREATE POLICY "Owner can view shop orders" ON public.orders
  FOR SELECT USING (public.is_shop_owner(shop_id));

DROP POLICY IF EXISTS "Owner can update shop orders" ON public.orders;
CREATE POLICY "Owner can update shop orders" ON public.orders
  FOR UPDATE USING (public.is_shop_owner(shop_id))
  WITH CHECK (public.is_shop_owner(shop_id));

DROP POLICY IF EXISTS "Owner can create shop orders" ON public.orders;
CREATE POLICY "Owner can create shop orders" ON public.orders
  FOR INSERT WITH CHECK (public.is_shop_owner(shop_id));

-- Owner boleh menghapus pesanan yang dibatalkan di tokonya sendiri
DROP POLICY IF EXISTS "Owner can delete shop orders" ON public.orders;
CREATE POLICY "Owner can delete shop orders" ON public.orders
  FOR DELETE USING (public.is_shop_owner(shop_id));

-- ──────────────────────────────────────────
-- 3.5 RLS: SHOPS — owner boleh mengubah data tokonya sendiri
-- ──────────────────────────────────────────
DROP POLICY IF EXISTS "Owner can update own shop" ON public.shops;
CREATE POLICY "Owner can update own shop" ON public.shops
  FOR UPDATE USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Owner can create own shop" ON public.shops;
CREATE POLICY "Owner can create own shop" ON public.shops
  FOR INSERT WITH CHECK (
    owner_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'owner')
  );

-- ──────────────────────────────────────────
-- 3.6 TABEL PETTY CASH (kas kecil per toko)
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

DROP POLICY IF EXISTS "Owner can update petty cash" ON public.petty_cash;
CREATE POLICY "Owner can update petty cash" ON public.petty_cash
  FOR UPDATE USING (public.is_shop_owner(shop_id::text))
  WITH CHECK (public.is_shop_owner(shop_id::text));

DROP POLICY IF EXISTS "Owner can delete petty cash" ON public.petty_cash;
CREATE POLICY "Owner can delete petty cash" ON public.petty_cash
  FOR DELETE USING (public.is_shop_owner(shop_id::text));

-- ──────────────────────────────────────────
-- 3.7 IZIN TABEL (GRANT)
-- ──────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.shops TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.petty_cash TO authenticated;

-- ──────────────────────────────────────────
-- 3.8 SEED DATA AWAL (idempotent)
--     Policy INSERT shops hanya mengizinkan owner, sehingga seeding
--     tidak bisa dilakukan dari aplikasi (ditolak RLS). Seed dijalankan
--     di sini dengan hak akses SQL Editor sehingga lolos RLS.
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
