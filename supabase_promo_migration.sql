-- ============================================================
-- WASHORA — MIGRASI FITUR PROMO OUTLET MITRA
-- Tabel, RLS, Helper Function & Realtime Publication
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- ============================================================

-- ──────────────────────────────────────────
-- 1. TABEL SHOP_PROMOS
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shop_promos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('discount_pct', 'discount_flat', 'free_delivery', 'cashback')),
  value INT NOT NULL DEFAULT 0,
  max_saving INT NOT NULL DEFAULT 0,
  min_order INT NOT NULL DEFAULT 0,
  code TEXT,
  quota INT DEFAULT NULL,
  used_count INT NOT NULL DEFAULT 0,
  start_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_at TIMESTAMPTZ,
  active_days JSONB DEFAULT '[1,2,3,4,5,6,7]'::jsonb,
  service_ids JSONB DEFAULT '[]'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index untuk performa query
CREATE INDEX IF NOT EXISTS shop_promos_shop_id_idx ON public.shop_promos(shop_id);
CREATE INDEX IF NOT EXISTS shop_promos_code_idx ON public.shop_promos(code);
CREATE INDEX IF NOT EXISTS shop_promos_active_idx ON public.shop_promos(is_active);

-- ──────────────────────────────────────────
-- 2. ROW LEVEL SECURITY (RLS)
-- ──────────────────────────────────────────
ALTER TABLE public.shop_promos ENABLE ROW LEVEL SECURITY;

-- Helper check if shop owner exists
CREATE OR REPLACE FUNCTION public.is_shop_owner(p_shop_id TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.shops
    WHERE id::text = p_shop_id AND owner_id = auth.uid()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- Pelanggan / authenticated: bisa melihat promo toko yang aktif, atau semua promo jika owner
DROP POLICY IF EXISTS "Anyone can view active shop promos" ON public.shop_promos;
CREATE POLICY "Anyone can view active shop promos" ON public.shop_promos
  FOR SELECT USING (
    is_active = true 
    OR public.is_shop_owner(shop_id::text)
  );

-- Owner: bisa buat promo untuk tokonya sendiri
DROP POLICY IF EXISTS "Owner can insert shop promos" ON public.shop_promos;
CREATE POLICY "Owner can insert shop promos" ON public.shop_promos
  FOR INSERT WITH CHECK (public.is_shop_owner(shop_id::text));

-- Owner: bisa update promo tokonya sendiri
DROP POLICY IF EXISTS "Owner can update shop promos" ON public.shop_promos;
CREATE POLICY "Owner can update shop promos" ON public.shop_promos
  FOR UPDATE USING (public.is_shop_owner(shop_id::text))
  WITH CHECK (public.is_shop_owner(shop_id::text));

-- Owner: bisa hapus promo tokonya sendiri
DROP POLICY IF EXISTS "Owner can delete shop promos" ON public.shop_promos;
CREATE POLICY "Owner can delete shop promos" ON public.shop_promos
  FOR DELETE USING (public.is_shop_owner(shop_id::text));

-- ──────────────────────────────────────────
-- 3. REALTIME PUBLICATION
-- ──────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'shop_promos'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.shop_promos;
  END IF;
END;
$$;

-- ──────────────────────────────────────────
-- 4. GRANT PERMISSIONS
-- ──────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.shop_promos TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shop_promos TO authenticated;
