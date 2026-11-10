-- ============================================================
-- WASHORA — KLAIM KERUSAKAN LANJUTAN
-- Jalankan SETELAH supabase_bukti_klaim.sql dan supabase_langganan_benefit.sql.
-- Aman dijalankan berulang (idempotent).
--
--   • Jenis kerusakan, item yang terdampak, dan penyelesaian yang diminta pelanggan
--   • Batas ganti rugi transparan: maks. 10× harga layanan item terdampak
--   • Penyelesaian "Poin" (kredit poin otomatis) di samping cuci ulang & ganti rugi
--   • Batas respons outlet 2×24 jam; lewat itu pelanggan bisa menaikkan ke Washora
--   • Status "Selesai": mitra menandai cuci ulang/ganti rugi sudah dituntaskan
--   • Statistik klaim untuk dashboard mitra
-- ============================================================

ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS affected_items JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS requested_resolution TEXT;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS requested_amount INT;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS resolved_note TEXT;
ALTER TABLE public.damage_claims ADD COLUMN IF NOT EXISTS escalated BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.damage_claims DROP CONSTRAINT IF EXISTS damage_claims_status_check;
ALTER TABLE public.damage_claims ADD CONSTRAINT damage_claims_status_check CHECK (status IN
  ('pending', 'approved', 'rejected', 'appealed', 'appeal_approved', 'appeal_rejected', 'resolved'));

ALTER TABLE public.damage_claims DROP CONSTRAINT IF EXISTS damage_claims_resolution_check;
ALTER TABLE public.damage_claims ADD CONSTRAINT damage_claims_resolution_check CHECK (resolution IN
  ('rewash', 'compensation', 'points'));

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'damage_claims_category_check') THEN
    ALTER TABLE public.damage_claims ADD CONSTRAINT damage_claims_category_check CHECK (category IS NULL OR category IN
      ('torn', 'faded', 'stain', 'shrunk', 'missing', 'accessory', 'smell', 'other'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'damage_claims_requested_check') THEN
    ALTER TABLE public.damage_claims ADD CONSTRAINT damage_claims_requested_check CHECK (
      (requested_resolution IS NULL OR requested_resolution IN ('rewash', 'compensation', 'points'))
      AND (requested_amount IS NULL OR requested_amount >= 0));
  END IF;
END $$;

-- Kredit poin dari klaim dicatat di buku poin
ALTER TABLE public.points_ledger DROP CONSTRAINT IF EXISTS points_ledger_reason_check;
ALTER TABLE public.points_ledger ADD CONSTRAINT points_ledger_reason_check CHECK (reason IN ('earn', 'redeem', 'refund', 'claim'));


-- ════════════════════════════════════════════════════════════
-- Batas ganti rugi (kebijakan Washora): 10× harga layanan item terdampak
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.claim_compensation_cap(p_order_id UUID, p_items JSONB)
RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT (10 * COALESCE(SUM(COALESCE((i->>'price')::numeric, 0) * COALESCE((i->>'qty')::numeric, 0)), 0))::int
  FROM public.orders o, jsonb_array_elements(COALESCE(o.items, '[]'::jsonb)) AS i
  WHERE o.id = p_order_id
    AND (jsonb_array_length(COALESCE(p_items, '[]'::jsonb)) = 0
         OR COALESCE(p_items, '[]'::jsonb) ? (i->>'name'));
$$;
GRANT EXECUTE ON FUNCTION public.claim_compensation_cap(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.damage_claims_validate()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cap INT;
BEGIN
  NEW.escalated := FALSE;
  NEW.resolved_at := NULL;
  NEW.resolved_note := NULL;
  IF jsonb_typeof(COALESCE(NEW.affected_items, '[]'::jsonb)) <> 'array' THEN
    NEW.affected_items := '[]'::jsonb;
  END IF;
  IF NEW.requested_resolution = 'compensation' THEN
    v_cap := public.claim_compensation_cap(NEW.order_id, NEW.affected_items);
    IF COALESCE(NEW.requested_amount, 0) <= 0 THEN
      RAISE EXCEPTION 'Isi nominal ganti rugi yang diminta' USING ERRCODE = '22023';
    END IF;
    IF NEW.requested_amount > v_cap THEN
      RAISE EXCEPTION 'Ganti rugi maksimal Rp % (10x harga layanan item terdampak)', v_cap USING ERRCODE = '22023';
    END IF;
  ELSE
    NEW.requested_amount := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS damage_claims_validate ON public.damage_claims;
CREATE TRIGGER damage_claims_validate
  BEFORE INSERT ON public.damage_claims
  FOR EACH ROW EXECUTE FUNCTION public.damage_claims_validate();


-- ════════════════════════════════════════════════════════════
-- Keputusan mitra: cuci ulang / ganti rugi / poin, atau tolak
-- Hasil: OK | NOT_ALLOWED | NOT_PENDING | INVALID
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.decide_claim(
  p_claim_id UUID, p_approve BOOLEAN,
  p_resolution TEXT DEFAULT NULL, p_amount INT DEFAULT NULL, p_note TEXT DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
  v_claim public.damage_claims%ROWTYPE;
  v_cap INT;
BEGIN
  SELECT * INTO v_claim FROM public.damage_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_shop_owner(v_claim.shop_id) THEN RETURN 'NOT_ALLOWED'; END IF;
  IF v_claim.status <> 'pending' THEN RETURN 'NOT_PENDING'; END IF;

  IF p_approve THEN
    IF p_resolution NOT IN ('rewash', 'compensation', 'points')
       OR (p_resolution IN ('compensation', 'points') AND COALESCE(p_amount, 0) <= 0) THEN
      RETURN 'INVALID';
    END IF;
    IF p_resolution = 'compensation' THEN
      v_cap := public.claim_compensation_cap(v_claim.order_id, v_claim.affected_items);
      IF p_amount > v_cap THEN RETURN 'INVALID'; END IF;
    END IF;

    UPDATE public.damage_claims
    SET status = CASE WHEN p_resolution = 'points' THEN 'resolved' ELSE 'approved' END,
        resolution = p_resolution,
        compensation_amount = CASE WHEN p_resolution IN ('compensation', 'points') THEN p_amount END,
        owner_note = NULLIF(TRIM(COALESCE(p_note, '')), ''),
        decided_at = NOW(),
        resolved_at = CASE WHEN p_resolution = 'points' THEN NOW() END,
        resolved_note = CASE WHEN p_resolution = 'points' THEN 'Poin dikreditkan otomatis' END
    WHERE id = p_claim_id;

    -- Poin langsung masuk ke saldo pelanggan
    IF p_resolution = 'points' THEN
      INSERT INTO public.points_ledger (user_id, order_id, delta, reason)
      VALUES (v_claim.user_id, v_claim.order_id, p_amount, 'claim')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.member_points (user_id, balance) VALUES (v_claim.user_id, p_amount)
      ON CONFLICT (user_id) DO UPDATE SET balance = member_points.balance + p_amount, updated_at = NOW();
    END IF;
  ELSE
    IF LENGTH(TRIM(COALESCE(p_note, ''))) < 5 THEN RETURN 'INVALID'; END IF;
    UPDATE public.damage_claims
    SET status = 'rejected', owner_note = TRIM(p_note), decided_at = NOW()
    WHERE id = p_claim_id;
  END IF;
  RETURN 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Mitra menandai penyelesaian sudah dituntaskan (cuci ulang selesai / uang sudah ditransfer)
CREATE OR REPLACE FUNCTION public.resolve_claim(p_claim_id UUID, p_note TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_claim public.damage_claims%ROWTYPE;
BEGIN
  SELECT * INTO v_claim FROM public.damage_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_shop_owner(v_claim.shop_id) THEN RETURN 'NOT_ALLOWED'; END IF;
  IF v_claim.status NOT IN ('approved', 'appeal_approved') THEN RETURN 'NOT_APPROVED'; END IF;
  UPDATE public.damage_claims
  SET status = 'resolved', resolved_at = NOW(), resolved_note = NULLIF(TRIM(COALESCE(p_note, '')), '')
  WHERE id = p_claim_id;
  RETURN 'OK';
END;
$$;

-- Pelanggan menaikkan klaim ke Washora jika outlet tidak merespons 2×24 jam
CREATE OR REPLACE FUNCTION public.escalate_claim(p_claim_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_claim public.damage_claims%ROWTYPE;
BEGIN
  SELECT * INTO v_claim FROM public.damage_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR v_claim.user_id IS DISTINCT FROM auth.uid() THEN RETURN 'NOT_ALLOWED'; END IF;
  IF v_claim.status <> 'pending' THEN RETURN 'NOT_PENDING'; END IF;
  IF NOW() < v_claim.created_at + INTERVAL '48 hours' THEN RETURN 'TOO_EARLY'; END IF;
  UPDATE public.damage_claims
  SET status = 'appealed', escalated = TRUE, appealed_at = NOW(),
      appeal_reason = 'Outlet tidak merespons dalam 2x24 jam'
  WHERE id = p_claim_id;
  RETURN 'OK';
END;
$$;

-- Statistik klaim outlet (untuk mitra)
CREATE OR REPLACE FUNCTION public.claim_stats(p_shop_id TEXT)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE WHEN NOT public.is_shop_owner(p_shop_id) THEN NULL ELSE jsonb_build_object(
    'total', COUNT(*),
    'pending', COUNT(*) FILTER (WHERE status = 'pending'),
    'overdue', COUNT(*) FILTER (WHERE status = 'pending' AND created_at < NOW() - INTERVAL '48 hours'),
    'resolved', COUNT(*) FILTER (WHERE status = 'resolved'),
    'approved_rate', CASE WHEN COUNT(*) FILTER (WHERE decided_at IS NOT NULL) = 0 THEN NULL
      ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE resolution IS NOT NULL)
                 / COUNT(*) FILTER (WHERE decided_at IS NOT NULL)) END,
    'avg_response_hours', ROUND((AVG(EXTRACT(EPOCH FROM (decided_at - created_at)) / 3600)
                                 FILTER (WHERE decided_at IS NOT NULL))::numeric, 1),
    'claim_rate_pct', (SELECT CASE WHEN COUNT(*) = 0 THEN NULL
                         ELSE ROUND(100.0 * (SELECT COUNT(*) FROM public.damage_claims d WHERE d.shop_id = p_shop_id) / COUNT(*), 1) END
                       FROM public.orders o WHERE o.shop_id = p_shop_id AND o.status = 'delivered')
  ) END
  FROM public.damage_claims WHERE shop_id = p_shop_id;
$$;

GRANT EXECUTE ON FUNCTION public.decide_claim(UUID, BOOLEAN, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_claim(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_claim(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stats(TEXT) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- Notifikasi klaim (versi lengkap: poin, selesai, dinaikkan ke Washora)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_claim_change()
RETURNS trigger AS $$
DECLARE
  v_title TEXT;
  v_body  TEXT;
  v_resolution TEXT;
  v_amount TEXT := REPLACE(TO_CHAR(COALESCE(NEW.compensation_amount, 0), 'FM999,999,999'), ',', '.');
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_resolution := CASE NEW.resolution
    WHEN 'rewash' THEN 'Outlet akan mencuci ulang cucianmu tanpa biaya.'
    WHEN 'compensation' THEN 'Kamu akan menerima ganti rugi Rp ' || v_amount || '.'
    WHEN 'points' THEN v_amount || ' poin sudah masuk ke saldomu (1 poin = Rp 1).'
    ELSE ''
  END;

  CASE NEW.status
    WHEN 'pending' THEN
      v_title := 'Klaim kerusakan terkirim';
      v_body  := 'Outlet akan memeriksa foto bukti dan merespons maksimal 2x24 jam.';
    WHEN 'approved' THEN
      v_title := 'Klaim disetujui';
      v_body  := v_resolution;
    WHEN 'rejected' THEN
      v_title := 'Klaim ditolak';
      v_body  := 'Alasan: ' || COALESCE(NEW.owner_note, '-') || '. Kamu bisa mengajukan banding.';
    WHEN 'appealed' THEN
      v_title := CASE WHEN NEW.escalated THEN 'Klaim dinaikkan ke Washora' ELSE 'Banding diajukan' END;
      v_body  := 'Tim Washora akan meninjau bukti dari kedua pihak.';
    WHEN 'appeal_approved' THEN
      v_title := 'Banding disetujui';
      v_body  := v_resolution;
    WHEN 'appeal_rejected' THEN
      v_title := 'Banding ditolak';
      v_body  := 'Keputusan akhir: ' || COALESCE(NEW.admin_note, 'klaim tidak dapat diterima') || '.';
    WHEN 'resolved' THEN
      v_title := 'Klaim selesai';
      v_body  := CASE WHEN NEW.resolution = 'points' THEN v_resolution
                      ELSE COALESCE(NULLIF(NEW.resolved_note, ''), 'Outlet menandai penyelesaian klaim sudah dituntaskan.') END;
    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (user_id, order_id, status, title, body)
  VALUES (NEW.user_id, NEW.order_id, 'claim_' || NEW.status, v_title, v_body);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

NOTIFY pgrst, 'reload schema';
