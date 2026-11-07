-- ════════════════════════════════════════════════════════════
-- WASHORA — PENGATURAN OUTLET MITRA
-- Layanan & tarif, jam operasional, dan layanan antar jemput.
-- Aman dijalankan berulang kali (idempotent).
-- Jalankan di Supabase → SQL Editor → New query → Run.
-- ════════════════════════════════════════════════════════════

-- 1. Kolom pengaturan di tabel shops
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS is_open BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS operational_days TEXT NOT NULL DEFAULT 'Setiap Hari (Senin - Minggu)',
  ADD COLUMN IF NOT EXISTS is_delivery_available BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS delivery_fee INT NOT NULL DEFAULT 5000,
  ADD COLUMN IF NOT EXISTS delivery_fee_type TEXT NOT NULL DEFAULT 'flat',
  ADD COLUMN IF NOT EXISTS delivery_radius_km NUMERIC(5,1) NOT NULL DEFAULT 5.0,
  ADD COLUMN IF NOT EXISTS min_delivery_order INT NOT NULL DEFAULT 20000;

-- 2. Batasan nilai supaya data tidak rusak walau dikirim dari luar aplikasi
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_delivery_fee_type_check') THEN
    ALTER TABLE public.shops ADD CONSTRAINT shops_delivery_fee_type_check
      CHECK (delivery_fee_type IN ('flat', 'per_km', 'free'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_delivery_values_check') THEN
    ALTER TABLE public.shops ADD CONSTRAINT shops_delivery_values_check
      CHECK (delivery_fee >= 0 AND min_delivery_order >= 0
             AND delivery_radius_km > 0 AND delivery_radius_km <= 50);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shops_price_per_kg_check') THEN
    ALTER TABLE public.shops ADD CONSTRAINT shops_price_per_kg_check
      CHECK (price_per_kg >= 0);
  END IF;
END $$;

-- 3. Izin: mitra mengubah outlet miliknya sendiri
--    (policy "Owner can update own shop" sudah ada di supabase_install_all.sql;
--     dibuat ulang di sini agar file ini bisa berdiri sendiri)
DROP POLICY IF EXISTS "Owner can update own shop" ON public.shops;
CREATE POLICY "Owner can update own shop" ON public.shops
  FOR UPDATE USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

GRANT SELECT, UPDATE ON public.shops TO authenticated;

-- 4. Muat ulang cache skema API agar kolom baru langsung terbaca aplikasi
NOTIFY pgrst, 'reload schema';
