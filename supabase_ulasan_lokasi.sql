-- ============================================================
-- WASHORA — ULASAN PELANGGAN, LOKASI OUTLET & PENGATURAN OUTLET
-- Jalankan SETELAH supabase_install_all.sql.
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. KOLOM BARU DI SHOPS
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS review_count INT NOT NULL DEFAULT 0;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS phone TEXT DEFAULT '';
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS description TEXT DEFAULT '';
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS is_open BOOLEAN NOT NULL DEFAULT TRUE;


-- ════════════════════════════════════════════════════════════
-- 2. TABEL REVIEWS (1 ulasan per pesanan)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  shop_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_name TEXT NOT NULL DEFAULT '',
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT DEFAULT '',
  tags TEXT[] DEFAULT '{}',
  service_summary TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS reviews_shop_id_idx ON public.reviews (shop_id, created_at DESC);

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Semua orang boleh membaca ulasan
DROP POLICY IF EXISTS "Anyone can view reviews" ON public.reviews;
CREATE POLICY "Anyone can view reviews" ON public.reviews
  FOR SELECT USING (true);

-- Pelanggan hanya boleh mengulas pesanannya sendiri yang sudah selesai
DROP POLICY IF EXISTS "Customer can review own delivered order" ON public.reviews;
CREATE POLICY "Customer can review own delivered order" ON public.reviews
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.user_id = auth.uid()
        AND o.status = 'delivered'
        AND o.shop_id = reviews.shop_id
    )
  );

-- Pelanggan boleh mengubah / menghapus ulasannya sendiri
DROP POLICY IF EXISTS "Customer can update own review" ON public.reviews;
CREATE POLICY "Customer can update own review" ON public.reviews
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Customer can delete own review" ON public.reviews;
CREATE POLICY "Customer can delete own review" ON public.reviews
  FOR DELETE USING (user_id = auth.uid());


-- ════════════════════════════════════════════════════════════
-- 3. RATING OUTLET DIHITUNG OTOMATIS DARI ULASAN
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.refresh_shop_rating()
RETURNS TRIGGER AS $$
DECLARE
  v_shop TEXT := COALESCE(NEW.shop_id, OLD.shop_id);
BEGIN
  UPDATE public.shops s
  SET rating = COALESCE((SELECT ROUND(AVG(r.rating)::numeric, 1) FROM public.reviews r WHERE r.shop_id = v_shop), 0),
      review_count = (SELECT COUNT(*) FROM public.reviews r WHERE r.shop_id = v_shop)
  WHERE s.id::text = v_shop;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS reviews_refresh_shop_rating ON public.reviews;
CREATE TRIGGER reviews_refresh_shop_rating
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.refresh_shop_rating();

-- Sinkronkan rating outlet yang sudah ada (outlet tanpa ulasan tetap memakai rating lamanya)
UPDATE public.shops s
SET rating = agg.avg_rating, review_count = agg.cnt
FROM (
  SELECT shop_id, ROUND(AVG(rating)::numeric, 1) AS avg_rating, COUNT(*) AS cnt
  FROM public.reviews GROUP BY shop_id
) agg
WHERE s.id::text = agg.shop_id;


-- ════════════════════════════════════════════════════════════
-- 4. REALTIME UNTUK ULASAN (opsional, agar ulasan baru langsung muncul)
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
  END IF;
END $$;
