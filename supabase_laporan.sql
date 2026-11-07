-- ============================================================
-- WASHORA — LAPORAN OMZET, TRANSAKSI HARI INI & RIWAYAT LAYANAN
-- Jalankan SETELAH supabase_install_all.sql.
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. INDEX: laporan & riwayat selalu memfilter outlet + rentang tanggal
-- ════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS orders_shop_created_idx
  ON public.orders (shop_id, created_at DESC);

-- Riwayat per pelanggan (pelanggan aplikasi & walk-in)
CREATE INDEX IF NOT EXISTS orders_shop_user_idx
  ON public.orders (shop_id, user_id);
CREATE INDEX IF NOT EXISTS orders_shop_phone_idx
  ON public.orders (shop_id, customer_phone);


-- ════════════════════════════════════════════════════════════
-- 2. RPC: washora_revenue_report
--    Semua agregasi dihitung di database, aplikasi hanya menerima ringkasan.
--    SECURITY INVOKER → RLS orders tetap berlaku: mitra hanya bisa
--    melihat outlet miliknya sendiri, akun lain mendapat angka nol.
--    Omzet = total_price pesanan yang TIDAK dibatalkan.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.washora_revenue_report(
  p_shop_id TEXT,
  p_from TIMESTAMPTZ,
  p_to TIMESTAMPTZ,
  p_tz TEXT DEFAULT 'Asia/Jakarta'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_prev_from TIMESTAMPTZ;
  v_result JSONB;
BEGIN
  IF p_shop_id IS NULL OR p_from IS NULL OR p_to IS NULL OR p_to <= p_from THEN
    RAISE EXCEPTION 'Rentang tanggal tidak valid' USING ERRCODE = '22023';
  END IF;
  IF p_to - p_from > INTERVAL '366 days' THEN
    RAISE EXCEPTION 'Rentang laporan maksimal 1 tahun' USING ERRCODE = '22023';
  END IF;

  -- Periode pembanding: panjang sama, tepat sebelum p_from
  v_prev_from := p_from - (p_to - p_from);

  WITH cur AS (
    SELECT o.*
    FROM public.orders o
    WHERE o.shop_id = p_shop_id
      AND o.created_at >= p_from AND o.created_at < p_to
      AND o.status <> 'cancelled'
  ),
  prev AS (
    SELECT COALESCE(SUM(o.total_price), 0) AS total, COUNT(*) AS cnt
    FROM public.orders o
    WHERE o.shop_id = p_shop_id
      AND o.created_at >= v_prev_from AND o.created_at < p_from
      AND o.status <> 'cancelled'
  ),
  daily AS (
    SELECT (c.created_at AT TIME ZONE p_tz)::date AS day,
           SUM(c.total_price) AS total,
           COUNT(*) AS cnt
    FROM cur c
    GROUP BY 1
  ),
  svc AS (
    SELECT COALESCE(NULLIF(TRIM(i->>'name'), ''), 'Tanpa nama') AS name,
           SUM(COALESCE((i->>'price')::numeric, 0) * COALESCE((i->>'qty')::numeric, 0))::bigint AS total,
           COUNT(DISTINCT c.id) AS cnt
    FROM cur c
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(c.items, '[]'::jsonb)) AS i
    GROUP BY 1
  ),
  pay AS (
    SELECT LOWER(COALESCE(NULLIF(TRIM(c.payment_method), ''), '')) AS method,
           SUM(c.total_price) AS total,
           COUNT(*) AS cnt
    FROM cur c
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'total',      COALESCE((SELECT SUM(total_price) FROM cur), 0),
    'count',      (SELECT COUNT(*) FROM cur),
    'prev_total', (SELECT total FROM prev),
    'prev_count', (SELECT cnt FROM prev),
    'daily',      COALESCE((SELECT jsonb_agg(jsonb_build_object('day', day, 'total', total, 'count', cnt) ORDER BY day) FROM daily), '[]'::jsonb),
    'services',   COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'total', total, 'count', cnt) ORDER BY total DESC) FROM svc), '[]'::jsonb),
    'payments',   COALESCE((SELECT jsonb_agg(jsonb_build_object('method', method, 'total', total, 'count', cnt) ORDER BY total DESC) FROM pay), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.washora_revenue_report(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
