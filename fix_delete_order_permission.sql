-- ============================================================
-- PERBAIKAN CEPAT: Izin Hapus Pesanan untuk Mitra/Owner
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query
-- Aman dijalankan ulang (idempotent).
-- ============================================================

-- 1. Policy RLS: owner boleh menghapus pesanan di tokonya sendiri
--    (misalnya pesanan yang sudah dibatalkan)
DROP POLICY IF EXISTS "Owner can delete shop orders" ON public.orders;
CREATE POLICY "Owner can delete shop orders" ON public.orders
  FOR DELETE USING (public.is_shop_owner(shop_id));

-- 2. GRANT DELETE agar request sampai ke RLS (mencegah error 42501)
GRANT DELETE ON public.orders TO authenticated;
