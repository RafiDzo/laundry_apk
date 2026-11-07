-- ============================================================
-- WASHORA — PAKAI PROMO OUTLET SAAT CHECKOUT
-- Jalankan SETELAH supabase_promo_migration.sql.
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
--
-- Pelanggan tidak boleh mengubah tabel shop_promos (RLS khusus mitra),
-- jadi validasi promo & penambahan used_count dilakukan trigger di server
-- saat pesanan dibuat. Aplikasi hanya mengirim promo_id + discount_amount;
-- server menolak jika promo tidak berlaku atau potongannya melebihi batas.
-- ============================================================

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS promo_id UUID REFERENCES public.shop_promos(id) ON DELETE SET NULL;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS promo_title TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_amount INT NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_discount_nonnegative') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_discount_nonnegative CHECK (discount_amount >= 0);
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════
-- Validasi saat pesanan dibuat
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.orders_apply_promo()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p public.shop_promos%ROWTYPE;
  v_subtotal NUMERIC;
  v_delivery NUMERIC;
  v_allowed NUMERIC;
  v_dow INT;
BEGIN
  IF NEW.promo_id IS NULL THEN
    NEW.discount_amount := 0;
    NEW.promo_title := NULL;
    RETURN NEW;
  END IF;

  -- Kunci baris promo agar kuota tidak terlewati saat banyak pesanan bersamaan
  SELECT * INTO p FROM public.shop_promos WHERE id = NEW.promo_id FOR UPDATE;

  IF NOT FOUND OR p.shop_id::text <> NEW.shop_id THEN
    RAISE EXCEPTION 'Promo tidak berlaku untuk outlet ini' USING ERRCODE = '22023';
  END IF;
  IF NOT p.is_active OR NOW() < p.start_at OR (p.end_at IS NOT NULL AND NOW() > p.end_at) THEN
    RAISE EXCEPTION 'Promo "%" sudah tidak berlaku', p.title USING ERRCODE = '22023';
  END IF;
  IF p.quota IS NOT NULL AND p.quota > 0 AND p.used_count >= p.quota THEN
    RAISE EXCEPTION 'Kuota promo "%" sudah habis', p.title USING ERRCODE = '22023';
  END IF;
  IF p.type = 'cashback' THEN
    RAISE EXCEPTION 'Promo cashback belum bisa dipakai saat checkout' USING ERRCODE = '22023';
  END IF;

  v_dow := EXTRACT(ISODOW FROM (NOW() AT TIME ZONE 'Asia/Jakarta'))::INT;
  IF p.active_days IS NOT NULL AND jsonb_typeof(p.active_days) = 'array'
     AND jsonb_array_length(p.active_days) > 0
     AND NOT (p.active_days @> to_jsonb(v_dow)) THEN
    RAISE EXCEPTION 'Promo "%" tidak berlaku hari ini', p.title USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(SUM(COALESCE((i->>'price')::numeric, 0) * COALESCE((i->>'qty')::numeric, 0)), 0)
  INTO v_subtotal
  FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) AS i;

  IF v_subtotal < p.min_order THEN
    RAISE EXCEPTION 'Belum memenuhi minimal belanja promo "%"', p.title USING ERRCODE = '22023';
  END IF;

  -- Batas atas potongan yang wajar (aplikasi bisa memberi lebih kecil,
  -- mis. jika promo hanya untuk layanan tertentu)
  IF p.type = 'discount_pct' THEN
    v_allowed := floor(v_subtotal * p.value / 100.0);
    IF p.max_saving > 0 THEN v_allowed := LEAST(v_allowed, p.max_saving); END IF;
  ELSIF p.type = 'discount_flat' THEN
    v_allowed := LEAST(p.value, v_subtotal);
  ELSE -- free_delivery: ongkir = total sebelum potongan - subtotal - biaya layanan
    v_delivery := (NEW.total_price + NEW.discount_amount) - v_subtotal - COALESCE(NEW.service_fee, 0);
    v_allowed := GREATEST(v_delivery, 0);
  END IF;

  IF NEW.discount_amount > v_allowed + 1 THEN
    RAISE EXCEPTION 'Potongan promo tidak valid' USING ERRCODE = '22023';
  END IF;

  NEW.promo_title := p.title;
  UPDATE public.shop_promos SET used_count = used_count + 1, updated_at = NOW() WHERE id = p.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_apply_promo ON public.orders;
CREATE TRIGGER orders_apply_promo
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_apply_promo();

-- Promo tidak boleh diganti setelah pesanan dibuat
CREATE OR REPLACE FUNCTION public.orders_lock_promo()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  NEW.promo_id := OLD.promo_id;
  NEW.promo_title := OLD.promo_title;
  NEW.discount_amount := OLD.discount_amount;

  -- Pesanan dibatalkan: kembalikan kuota promo
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' AND OLD.promo_id IS NOT NULL THEN
    UPDATE public.shop_promos SET used_count = GREATEST(used_count - 1, 0), updated_at = NOW()
    WHERE id = OLD.promo_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_lock_promo ON public.orders;
CREATE TRIGGER orders_lock_promo
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_lock_promo();

NOTIFY pgrst, 'reload schema';
