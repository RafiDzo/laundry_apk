-- ============================================================
-- WASHORA — LANGGANAN TAHAP 2: BENEFIT OTOMATIS
-- Jalankan SETELAH supabase_langganan.sql, supabase_promo_checkout.sql,
-- dan supabase_bukti_klaim.sql. Aman dijalankan berulang (idempotent).
--
--   • Gratis ongkir member: kuota per bulan kalender (WIB), dicek & dihitung server.
--   • Poin: didapat saat pesanan diterima (persen sesuai tingkat), 1 poin = Rp 1,
--     bisa dipakai memotong tagihan berikutnya. Dibatalkan → poin & kuota kembali.
--   • Batas klaim kerusakan mengikuti tingkat member saat cucian diterima.
-- Diskon Mitra Member & gratis upgrade Express menyusul di tahap 3.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. KOLOM & TABEL
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.memberships ADD COLUMN IF NOT EXISTS quota_month DATE;

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS member_plan TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS member_free_delivery BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS points_used INT NOT NULL DEFAULT 0;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_points_nonnegative') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_points_nonnegative CHECK (points_used >= 0);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.member_points (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  balance INT NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.points_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  delta INT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('earn', 'redeem', 'refund')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS points_ledger_once ON public.points_ledger (order_id, reason) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS points_ledger_user_idx ON public.points_ledger (user_id, created_at DESC);

ALTER TABLE public.member_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.points_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Customer views own points" ON public.member_points;
CREATE POLICY "Customer views own points" ON public.member_points FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Customer views own points ledger" ON public.points_ledger;
CREATE POLICY "Customer views own points ledger" ON public.points_ledger FOR SELECT USING (user_id = auth.uid());
GRANT SELECT ON public.member_points, public.points_ledger TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 2. HELPER
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.member_month_start()
RETURNS DATE LANGUAGE sql STABLE AS $$
  SELECT date_trunc('month', NOW() AT TIME ZONE 'Asia/Jakarta')::date;
$$;

-- Batas klaim (jam) berdasarkan langganan yang aktif saat cucian diterima
CREATE OR REPLACE FUNCTION public.claim_window_hours(p_user UUID, p_at TIMESTAMPTZ)
RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT p.claim_window_hours
    FROM public.memberships m JOIN public.membership_plans p ON p.id = m.plan_id
    WHERE m.user_id = p_user AND m.status = 'active'
      AND COALESCE(p_at, NOW()) BETWEEN m.starts_at AND m.ends_at
    ORDER BY p.claim_window_hours DESC
    LIMIT 1), 48);
$$;

-- Benefit pelanggan yang login, untuk ditampilkan saat checkout
CREATE OR REPLACE FUNCTION public.my_member_benefits()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  m public.memberships%ROWTYPE;
  p public.membership_plans%ROWTYPE;
  v_used INT;
  v_points INT;
BEGIN
  SELECT balance INTO v_points FROM public.member_points WHERE user_id = auth.uid();
  SELECT * INTO m FROM public.memberships
  WHERE user_id = auth.uid() AND status = 'active' AND NOW() BETWEEN starts_at AND ends_at
  ORDER BY ends_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('active', FALSE, 'points_balance', COALESCE(v_points, 0), 'claim_hours', 48);
  END IF;
  SELECT * INTO p FROM public.membership_plans WHERE id = m.plan_id;
  v_used := CASE WHEN m.quota_month IS DISTINCT FROM public.member_month_start() THEN 0 ELSE m.free_delivery_used END;
  RETURN jsonb_build_object(
    'active', TRUE,
    'plan_id', p.id,
    'plan_name', p.name,
    'free_delivery_quota', p.free_delivery_quota,
    'free_delivery_used', v_used,
    'points_pct', p.points_pct,
    'points_balance', COALESCE(v_points, 0),
    'claim_hours', p.claim_window_hours,
    'ends_at', m.ends_at
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.my_member_benefits() TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_window_hours(UUID, TIMESTAMPTZ) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 3. SAAT PESANAN DIBUAT: gratis ongkir & tukar poin
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.orders_apply_member()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  m public.memberships%ROWTYPE;
  p public.membership_plans%ROWTYPE;
  v_month DATE := public.member_month_start();
  v_subtotal NUMERIC;
  v_balance INT;
BEGIN
  NEW.member_plan := NULL;
  IF NEW.user_id IS NULL OR NEW.user_id IS DISTINCT FROM auth.uid() THEN
    -- Pesanan walk-in dari kasir: tidak memakai benefit member pelanggan
    NEW.member_free_delivery := FALSE;
    NEW.points_used := 0;
    RETURN NEW;
  END IF;

  SELECT * INTO m FROM public.memberships
  WHERE user_id = NEW.user_id AND status = 'active' AND NOW() BETWEEN starts_at AND ends_at
  ORDER BY ends_at DESC LIMIT 1
  FOR UPDATE;
  IF FOUND THEN
    SELECT * INTO p FROM public.membership_plans WHERE id = m.plan_id;
    NEW.member_plan := m.plan_id;
  END IF;

  IF NEW.member_free_delivery THEN
    IF m.id IS NULL THEN
      RAISE EXCEPTION 'Gratis ongkir member: langganan tidak aktif' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(NEW.delivery_type, 'pickup') = 'dropoff' THEN
      NEW.member_free_delivery := FALSE;
    ELSE
      IF m.quota_month IS DISTINCT FROM v_month THEN
        m.free_delivery_used := 0;
      END IF;
      IF p.free_delivery_quota IS NOT NULL AND m.free_delivery_used >= p.free_delivery_quota THEN
        RAISE EXCEPTION 'Kuota gratis ongkir member bulan ini sudah habis' USING ERRCODE = '22023';
      END IF;
      UPDATE public.memberships
      SET free_delivery_used = m.free_delivery_used + 1, quota_month = v_month, updated_at = NOW()
      WHERE id = m.id;
    END IF;
  END IF;

  IF COALESCE(NEW.points_used, 0) > 0 THEN
    SELECT COALESCE(SUM(COALESCE((i->>'price')::numeric, 0) * COALESCE((i->>'qty')::numeric, 0)), 0)
    INTO v_subtotal FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) AS i;
    IF NEW.points_used > v_subtotal THEN
      RAISE EXCEPTION 'Poin yang dipakai melebihi harga layanan' USING ERRCODE = '22023';
    END IF;
    SELECT balance INTO v_balance FROM public.member_points WHERE user_id = NEW.user_id FOR UPDATE;
    IF COALESCE(v_balance, 0) < NEW.points_used THEN
      RAISE EXCEPTION 'Poin tidak cukup (saldo %)', COALESCE(v_balance, 0) USING ERRCODE = '22023';
    END IF;
    UPDATE public.member_points SET balance = balance - NEW.points_used, updated_at = NOW() WHERE user_id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_apply_member ON public.orders;
CREATE TRIGGER orders_apply_member
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_apply_member();

-- Catat penukaran poin setelah pesanan punya id
CREATE OR REPLACE FUNCTION public.orders_log_redeem()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.points_used > 0 THEN
    INSERT INTO public.points_ledger (user_id, order_id, delta, reason)
    VALUES (NEW.user_id, NEW.id, -NEW.points_used, 'redeem')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS orders_log_redeem ON public.orders;
CREATE TRIGGER orders_log_redeem
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_log_redeem();


-- Validasi promo memperhitungkan poin & gratis ongkir member
-- (sama dengan supabase_promo_checkout.sql + poin dalam perhitungan ongkir)
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
     AND jsonb_array_length(p.active_days) > 0 AND NOT (p.active_days @> to_jsonb(v_dow)) THEN
    RAISE EXCEPTION 'Promo "%" tidak berlaku hari ini', p.title USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(SUM(COALESCE((i->>'price')::numeric, 0) * COALESCE((i->>'qty')::numeric, 0)), 0)
  INTO v_subtotal FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) AS i;
  IF v_subtotal < p.min_order THEN
    RAISE EXCEPTION 'Belum memenuhi minimal belanja promo "%"', p.title USING ERRCODE = '22023';
  END IF;

  IF p.type = 'discount_pct' THEN
    v_allowed := floor(v_subtotal * p.value / 100.0);
    IF p.max_saving > 0 THEN v_allowed := LEAST(v_allowed, p.max_saving); END IF;
  ELSIF p.type = 'discount_flat' THEN
    v_allowed := LEAST(p.value, v_subtotal);
  ELSE
    v_delivery := (NEW.total_price + NEW.discount_amount + COALESCE(NEW.points_used, 0))
                  - v_subtotal - COALESCE(NEW.service_fee, 0);
    v_allowed := CASE WHEN NEW.member_free_delivery THEN 0 ELSE GREATEST(v_delivery, 0) END;
  END IF;
  IF NEW.discount_amount > v_allowed + 1 THEN
    RAISE EXCEPTION 'Potongan promo tidak valid' USING ERRCODE = '22023';
  END IF;

  NEW.promo_title := p.title;
  UPDATE public.shop_promos SET used_count = used_count + 1, updated_at = NOW() WHERE id = p.id;
  RETURN NEW;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- 4. SAAT STATUS BERUBAH: dapat poin / kembalikan poin & kuota
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.orders_member_status()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pct NUMERIC;
  v_earn INT;
  n INT;
BEGIN
  -- Benefit tidak bisa diubah setelah pesanan dibuat
  NEW.member_plan := OLD.member_plan;
  NEW.member_free_delivery := OLD.member_free_delivery;
  NEW.points_used := OLD.points_used;

  IF OLD.user_id IS NULL THEN RETURN NEW; END IF;

  -- Diterima pelanggan → poin sesuai tingkat saat memesan
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' AND OLD.member_plan IS NOT NULL THEN
    SELECT points_pct INTO v_pct FROM public.membership_plans WHERE id = OLD.member_plan;
    v_earn := floor(GREATEST(NEW.total_price, 0) * COALESCE(v_pct, 0) / 100.0);
    IF v_earn > 0 THEN
      INSERT INTO public.points_ledger (user_id, order_id, delta, reason)
      VALUES (OLD.user_id, OLD.id, v_earn, 'earn')
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN
        INSERT INTO public.member_points (user_id, balance) VALUES (OLD.user_id, v_earn)
        ON CONFLICT (user_id) DO UPDATE SET balance = member_points.balance + v_earn, updated_at = NOW();
        INSERT INTO public.notifications (user_id, order_id, status, title, body)
        VALUES (OLD.user_id, OLD.id, 'points_earned', 'Kamu dapat ' || v_earn || ' poin',
                'Dari pesanan di ' || COALESCE(NULLIF(OLD.shop_name, ''), 'outlet') || '. 1 poin = Rp 1 untuk pesanan berikutnya.');
      END IF;
    END IF;
  END IF;

  -- Dibatalkan → kembalikan poin yang dipakai & kuota gratis ongkir
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    IF OLD.points_used > 0 THEN
      INSERT INTO public.points_ledger (user_id, order_id, delta, reason)
      VALUES (OLD.user_id, OLD.id, OLD.points_used, 'refund')
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN
        INSERT INTO public.member_points (user_id, balance) VALUES (OLD.user_id, OLD.points_used)
        ON CONFLICT (user_id) DO UPDATE SET balance = member_points.balance + OLD.points_used, updated_at = NOW();
      END IF;
    END IF;
    IF OLD.member_free_delivery THEN
      UPDATE public.memberships
      SET free_delivery_used = GREATEST(free_delivery_used - 1, 0), updated_at = NOW()
      WHERE user_id = OLD.user_id AND status = 'active'
        AND OLD.created_at BETWEEN starts_at AND ends_at
        AND quota_month = date_trunc('month', OLD.created_at AT TIME ZONE 'Asia/Jakarta')::date;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_member_status ON public.orders;
CREATE TRIGGER orders_member_status
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_member_status();


-- ════════════════════════════════════════════════════════════
-- 5. BATAS KLAIM KERUSAKAN SESUAI TINGKAT MEMBER
--    (menggantikan "48 jam" tetap di supabase_bukti_klaim.sql)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.can_upload_order_photo(p_order_id TEXT, p_stage TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id::text = p_order_id
      AND (
        (p_stage IN ('intake', 'handover') AND public.is_shop_owner(o.shop_id))
        OR (p_stage = 'claim'
            AND o.user_id = auth.uid()
            AND o.status = 'delivered'
            AND o.received_at > NOW() - make_interval(hours => public.claim_window_hours(o.user_id, o.received_at)))
      )
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

DROP POLICY IF EXISTS "Claims: customer create" ON public.damage_claims;
CREATE POLICY "Claims: customer create" ON public.damage_claims
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id
        AND o.user_id = auth.uid()
        AND o.shop_id = damage_claims.shop_id
        AND o.status = 'delivered'
        AND o.received_at > NOW() - make_interval(hours => public.claim_window_hours(o.user_id, o.received_at))
    )
    AND EXISTS (SELECT 1 FROM public.order_photos p
                WHERE p.order_id = damage_claims.order_id AND p.stage = 'claim')
  );

NOTIFY pgrst, 'reload schema';
