-- ============================================================
-- WASHORA — RATING & ULASAN LANJUTAN
-- Jalankan SETELAH supabase_ulasan_lokasi.sql (tabel reviews & trigger rating).
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
--
-- Menambahkan ke tabel reviews yang sudah ada:
--   • penilaian per aspek, foto (maks 3), opsi anonim, batas edit 7 hari
--   • balasan mitra (sekali, lewat RPC review_reply) + notifikasi ke pelanggan
--   • laporan ulasan oleh mitra (antrean tinjauan admin: tabel review_reports)
--   • ringkasan rating (RPC review_summary) untuk profil outlet & dashboard mitra
-- Rata-rata & jumlah ulasan di tabel shops tetap dihitung trigger
-- refresh_shop_rating (hanya untuk outlet yang ulasannya berubah).
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 0. IZIN AKSES TABEL REVIEWS
--    supabase_ulasan_lokasi.sql membuat tabel reviews tanpa GRANT, sehingga
--    aplikasi mendapat "permission denied for table reviews". RLS tetap
--    membatasi siapa boleh menulis/mengubah (lihat policy di file tersebut).
-- ════════════════════════════════════════════════════════════
GRANT SELECT ON public.reviews TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reviews TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 1. KOLOM BARU DI REVIEWS
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS aspect_cleanliness SMALLINT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS aspect_timeliness SMALLINT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS aspect_friendliness SMALLINT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS aspect_price SMALLINT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS photo_urls TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS reply TEXT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS reply_at TIMESTAMPTZ;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_aspects_range') THEN
    ALTER TABLE public.reviews ADD CONSTRAINT reviews_aspects_range CHECK (
      (aspect_cleanliness  IS NULL OR aspect_cleanliness  BETWEEN 1 AND 5) AND
      (aspect_timeliness   IS NULL OR aspect_timeliness   BETWEEN 1 AND 5) AND
      (aspect_friendliness IS NULL OR aspect_friendliness BETWEEN 1 AND 5) AND
      (aspect_price        IS NULL OR aspect_price        BETWEEN 1 AND 5));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reviews_limits') THEN
    ALTER TABLE public.reviews ADD CONSTRAINT reviews_limits CHECK (
      char_length(COALESCE(comment, '')) <= 500
      AND cardinality(photo_urls) <= 3
      AND char_length(COALESCE(reply, '')) <= 500);
  END IF;
END $$;

-- Index untuk daftar ulasan per outlet (urut terbaru / rating) & yang belum dibalas
CREATE INDEX IF NOT EXISTS reviews_shop_rating_idx ON public.reviews (shop_id, rating DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS reviews_shop_unreplied_idx ON public.reviews (shop_id, created_at DESC) WHERE reply IS NULL;


-- ════════════════════════════════════════════════════════════
-- 2. PENJAGA ISI ULASAN (insert & edit oleh pelanggan, balasan oleh mitra)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.reviews_clean_text(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v TEXT := btrim(regexp_replace(COALESCE(p, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g'));
  w TEXT;
BEGIN
  -- Filter kata kasar memakai daftar yang sama dengan chat (jika supabase_chat.sql sudah dijalankan)
  IF to_regclass('public.chat_banned_words') IS NOT NULL THEN
    IF to_regclass('public.chat_settings') IS NULL
       OR (SELECT profanity_filter FROM public.chat_settings LIMIT 1) IS DISTINCT FROM FALSE THEN
      FOR w IN EXECUTE 'SELECT word FROM public.chat_banned_words' LOOP
        v := regexp_replace(v, '\m' || w || '\M', repeat('*', char_length(w)), 'gi');
      END LOOP;
    END IF;
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.reviews_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_name TEXT;
  u TEXT;
  v_prefix TEXT;
BEGIN
  -- Jalur balasan mitra (RPC review_reply): hanya kolom balasan yang boleh berubah
  IF TG_OP = 'UPDATE' AND current_setting('washora.review_reply', true) = '1' THEN
    NEW.order_id := OLD.order_id;  NEW.shop_id := OLD.shop_id;   NEW.user_id := OLD.user_id;
    NEW.user_name := OLD.user_name; NEW.rating := OLD.rating;    NEW.comment := OLD.comment;
    NEW.tags := OLD.tags;          NEW.photo_urls := OLD.photo_urls;
    NEW.is_anonymous := OLD.is_anonymous; NEW.service_summary := OLD.service_summary;
    NEW.aspect_cleanliness := OLD.aspect_cleanliness; NEW.aspect_timeliness := OLD.aspect_timeliness;
    NEW.aspect_friendliness := OLD.aspect_friendliness; NEW.aspect_price := OLD.aspect_price;
    NEW.created_at := OLD.created_at; NEW.updated_at := OLD.updated_at;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_at := NOW();
    NEW.reply := NULL;
    NEW.reply_at := NULL;
  ELSE
    -- Edit oleh pelanggan: hanya 7 hari sejak dikirim, balasan & identitas tidak bisa diubah
    IF NOW() > OLD.created_at + INTERVAL '7 days' THEN
      RAISE EXCEPTION 'Ulasan hanya bisa diubah dalam 7 hari setelah dikirim' USING ERRCODE = '22023';
    END IF;
    NEW.order_id := OLD.order_id; NEW.shop_id := OLD.shop_id; NEW.user_id := OLD.user_id;
    NEW.created_at := OLD.created_at; NEW.reply := OLD.reply; NEW.reply_at := OLD.reply_at;
  END IF;
  NEW.updated_at := NOW();

  NEW.comment := public.reviews_clean_text(NEW.comment);
  NEW.tags := COALESCE(NEW.tags, '{}');

  -- Foto wajib dari bucket review-photos, di folder pesanan ini
  v_prefix := '/storage/v1/object/public/review-photos/' || NEW.order_id::text || '/';
  FOREACH u IN ARRAY COALESCE(NEW.photo_urls, '{}') LOOP
    IF position(v_prefix IN u) = 0 THEN
      RAISE EXCEPTION 'Foto ulasan tidak valid' USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- Nama ditentukan server: "Anonim" atau nama profil pelanggan
  IF NEW.is_anonymous THEN
    NEW.user_name := 'Anonim';
  ELSE
    SELECT name INTO v_name FROM public.users WHERE id = NEW.user_id;
    NEW.user_name := COALESCE(NULLIF(btrim(v_name), ''), NULLIF(btrim(NEW.user_name), ''), 'Pelanggan');
    IF NEW.user_name = 'Anonim' THEN NEW.user_name := 'Pelanggan'; END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reviews_guard ON public.reviews;
CREATE TRIGGER reviews_guard
  BEFORE INSERT OR UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.reviews_guard();


-- ════════════════════════════════════════════════════════════
-- 3. BALASAN MITRA (sekali per ulasan) + notifikasi ke pelanggan
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.review_reply(p_review_id UUID, p_reply TEXT)
RETURNS public.reviews
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r public.reviews%ROWTYPE;
  v TEXT;
  v_shop TEXT;
BEGIN
  SELECT * INTO r FROM public.reviews WHERE id = p_review_id;
  IF NOT FOUND OR NOT public.is_shop_owner(r.shop_id) THEN
    RAISE EXCEPTION 'Hanya pemilik outlet yang bisa membalas ulasan ini' USING ERRCODE = '42501';
  END IF;
  IF r.reply IS NOT NULL THEN
    RAISE EXCEPTION 'Ulasan ini sudah dibalas' USING ERRCODE = '22023';
  END IF;
  v := public.reviews_clean_text(p_reply);
  IF char_length(v) < 1 OR char_length(v) > 500 THEN
    RAISE EXCEPTION 'Balasan harus 1-500 karakter' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('washora.review_reply', '1', true);
  UPDATE public.reviews SET reply = v, reply_at = NOW() WHERE id = p_review_id RETURNING * INTO r;
  PERFORM set_config('washora.review_reply', '0', true);

  SELECT name INTO v_shop FROM public.shops WHERE id::text = r.shop_id;
  INSERT INTO public.notifications (user_id, order_id, status, title, body)
  VALUES (r.user_id, r.order_id, 'review_reply',
          COALESCE(NULLIF(v_shop, ''), 'Outlet') || ' membalas ulasanmu',
          left(v, 140));
  RETURN r;
END;
$$;
GRANT EXECUTE ON FUNCTION public.review_reply(UUID, TEXT) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 4. LAPORAN ULASAN (oleh mitra) — antrean tinjauan admin
--    Admin meninjau di Table Editor: ubah status jadi 'accepted' / 'rejected'.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.review_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL DEFAULT auth.uid(),
  reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (review_id, reporter_id)
);
CREATE INDEX IF NOT EXISTS review_reports_status_idx ON public.review_reports (status, created_at);

ALTER TABLE public.review_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner reports reviews of own shop" ON public.review_reports;
CREATE POLICY "Owner reports reviews of own shop" ON public.review_reports
  FOR INSERT WITH CHECK (
    reporter_id = auth.uid()
    AND status = 'pending'
    AND EXISTS (SELECT 1 FROM public.reviews r WHERE r.id = review_id AND public.is_shop_owner(r.shop_id))
  );
DROP POLICY IF EXISTS "Reporter views own review reports" ON public.review_reports;
CREATE POLICY "Reporter views own review reports" ON public.review_reports
  FOR SELECT USING (reporter_id = auth.uid());

GRANT SELECT, INSERT ON public.review_reports TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 5. RINGKASAN RATING (profil outlet & dashboard mitra)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.review_summary(p_shop_id TEXT)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH r AS (SELECT * FROM public.reviews WHERE shop_id = p_shop_id)
  SELECT jsonb_build_object(
    'average', COALESCE((SELECT ROUND(AVG(rating)::numeric, 1) FROM r), 0),
    'count', (SELECT COUNT(*) FROM r),
    'distribution', jsonb_build_object(
      '1', (SELECT COUNT(*) FROM r WHERE rating = 1),
      '2', (SELECT COUNT(*) FROM r WHERE rating = 2),
      '3', (SELECT COUNT(*) FROM r WHERE rating = 3),
      '4', (SELECT COUNT(*) FROM r WHERE rating = 4),
      '5', (SELECT COUNT(*) FROM r WHERE rating = 5)),
    'with_photos', (SELECT COUNT(*) FROM r WHERE cardinality(photo_urls) > 0),
    'unreplied', (SELECT COUNT(*) FROM r WHERE reply IS NULL),
    'aspects', jsonb_build_object(
      'cleanliness',  (SELECT ROUND(AVG(aspect_cleanliness)::numeric, 1)  FROM r),
      'timeliness',   (SELECT ROUND(AVG(aspect_timeliness)::numeric, 1)   FROM r),
      'friendliness', (SELECT ROUND(AVG(aspect_friendliness)::numeric, 1) FROM r),
      'price',        (SELECT ROUND(AVG(aspect_price)::numeric, 1)        FROM r)),
    'monthly', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'average', avg_r, 'count', cnt) ORDER BY m)
      FROM (
        SELECT date_trunc('month', created_at AT TIME ZONE 'Asia/Jakarta') AS m,
               ROUND(AVG(rating)::numeric, 1) AS avg_r, COUNT(*) AS cnt
        FROM r
        WHERE created_at >= date_trunc('month', NOW() AT TIME ZONE 'Asia/Jakarta') - INTERVAL '5 months'
        GROUP BY 1
      ) t), '[]'::jsonb)
  );
$$;
GRANT EXECUTE ON FUNCTION public.review_summary(TEXT) TO anon, authenticated;


-- ════════════════════════════════════════════════════════════
-- 6. FOTO ULASAN (bucket publik, maks 2 MB, hanya pelanggan pemilik pesanan selesai)
--    Path: {order_id}/{waktu}_{n}.jpg
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('review-photos', 'review-photos', TRUE, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = TRUE, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Anyone can view review photos" ON storage.objects;
CREATE POLICY "Anyone can view review photos" ON storage.objects
  FOR SELECT USING (bucket_id = 'review-photos');

DROP POLICY IF EXISTS "Customer uploads review photos" ON storage.objects;
CREATE POLICY "Customer uploads review photos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'review-photos'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[1]
        AND o.user_id = auth.uid()
        AND o.status = 'delivered'
    )
  );

NOTIFY pgrst, 'reload schema';
