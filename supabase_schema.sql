-- ============================================================
-- SUPABASE SCHEMA untuk Washora App
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

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
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'washing', 'drying', 'done', 'delivered')),
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
CREATE POLICY "Users can view own profile" ON public.users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- Shops: semua user yang login bisa melihat toko
CREATE POLICY "Anyone can view shops" ON public.shops
  FOR SELECT USING (auth.role() = 'authenticated');

-- Orders: user hanya bisa lihat pesanannya sendiri
CREATE POLICY "Users can view own orders" ON public.orders
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create orders" ON public.orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ──────────────────────────────────────────
-- 5. REALTIME (untuk stream orders)
-- ──────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
