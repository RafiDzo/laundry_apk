-- ============================================================
-- WASHORA — CHAT INTERNAL MITRA ↔ PELANGGAN (REALTIME)
-- Jalankan SETELAH supabase_install_all.sql dan supabase_notifications.sql.
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
--
-- Konsep:
--   • 1 percakapan = 1 pesanan (order). Hanya pelanggan pemilik pesanan dan
--     pemilik outlet pesanan itu yang bisa membuka & membaca percakapannya.
--   • Percakapan hanya dibuat lewat RPC chat_open_conversation (validasi hak akses).
--   • Status pesan: terkirim (baris ada) → diterima (delivered_at) → dibaca (read_at).
--   • "Sedang mengetik" memakai Realtime Broadcast, tidak disimpan di database.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. TABEL
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  shop_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,  -- pelanggan
  owner_id UUID NOT NULL,                                               -- pemilik outlet (mitra)
  customer_name TEXT NOT NULL DEFAULT '',
  shop_name TEXT NOT NULL DEFAULT '',
  last_message_at TIMESTAMPTZ,
  last_message_preview TEXT NOT NULL DEFAULT '',
  last_sender_id UUID,
  customer_unread INT NOT NULL DEFAULT 0,
  owner_unread INT NOT NULL DEFAULT 0,
  blocked_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS chat_conv_user_idx  ON public.chat_conversations (user_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS chat_conv_owner_idx ON public.chat_conversations (owner_id, last_message_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL,
  type TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text', 'image')),
  body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 2000),
  image_path TEXT,
  client_id TEXT,  -- id dari aplikasi, mencegah pesan ganda saat "Kirim ulang"
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  CONSTRAINT chat_message_content CHECK (
    (type = 'text' AND char_length(btrim(body)) > 0)
    OR (type = 'image' AND image_path IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS chat_msg_conv_idx ON public.chat_messages (conversation_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS chat_msg_client_idx
  ON public.chat_messages (conversation_id, client_id) WHERE client_id IS NOT NULL;

-- Template balasan cepat milik mitra
CREATE TABLE IF NOT EXISTS public.chat_quick_replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL DEFAULT auth.uid(),
  body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 300),
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS chat_qr_owner_idx ON public.chat_quick_replies (owner_id, sort_order);

-- Laporan pesan / pengguna (ditinjau admin lewat dashboard Supabase)
CREATE TABLE IF NOT EXISTS public.chat_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  message_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  reporter_id UUID NOT NULL DEFAULT auth.uid(),
  reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Daftar kata kasar untuk filter (bisa ditambah/hapus dari Table Editor)
CREATE TABLE IF NOT EXISTS public.chat_banned_words (
  word TEXT PRIMARY KEY CHECK (word = lower(btrim(word)) AND char_length(word) >= 3)
);
INSERT INTO public.chat_banned_words (word) VALUES
  ('anjing'), ('bangsat'), ('bajingan'), ('kontol'), ('memek'), ('ngentot'),
  ('goblok'), ('tolol'), ('babi'), ('kampret'), ('asu'), ('jancok'), ('keparat')
ON CONFLICT DO NOTHING;

-- Matikan filter: UPDATE public.chat_settings SET profanity_filter = false;
CREATE TABLE IF NOT EXISTS public.chat_settings (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  profanity_filter BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO public.chat_settings (id) VALUES (TRUE) ON CONFLICT DO NOTHING;


-- ════════════════════════════════════════════════════════════
-- 2. HELPER HAK AKSES
-- ════════════════════════════════════════════════════════════
-- Menerima TEXT agar aman dipakai policy storage (nama folder = id percakapan)
CREATE OR REPLACE FUNCTION public.chat_is_participant(p_conversation TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_conversations c
    WHERE c.id::text = p_conversation
      AND auth.uid() IN (c.user_id, c.owner_id)
  );
$$;


-- ════════════════════════════════════════════════════════════
-- 3. RLS
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_quick_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_reports       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_banned_words  ENABLE ROW LEVEL SECURITY;  -- tanpa policy: hanya dibaca trigger
ALTER TABLE public.chat_settings      ENABLE ROW LEVEL SECURITY;  -- tanpa policy: hanya dibaca trigger

-- Percakapan: hanya dua pihak yang terlibat. Dibuat/diubah lewat RPC & trigger.
DROP POLICY IF EXISTS "Chat participants view conversation" ON public.chat_conversations;
CREATE POLICY "Chat participants view conversation" ON public.chat_conversations
  FOR SELECT USING (auth.uid() IN (user_id, owner_id));

-- Pesan: baca jika peserta; kirim atas nama sendiri, percakapan tidak diblokir
DROP POLICY IF EXISTS "Chat participants view messages" ON public.chat_messages;
CREATE POLICY "Chat participants view messages" ON public.chat_messages
  FOR SELECT USING (public.chat_is_participant(conversation_id::text));

DROP POLICY IF EXISTS "Chat participants send messages" ON public.chat_messages;
CREATE POLICY "Chat participants send messages" ON public.chat_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND auth.uid() IN (c.user_id, c.owner_id)
        AND c.blocked_by IS NULL
    )
  );

-- Template balasan: hanya milik sendiri
DROP POLICY IF EXISTS "Owner manages own quick replies" ON public.chat_quick_replies;
CREATE POLICY "Owner manages own quick replies" ON public.chat_quick_replies
  FOR ALL USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

-- Laporan: peserta boleh melapor & melihat laporannya sendiri
DROP POLICY IF EXISTS "Participants create reports" ON public.chat_reports;
CREATE POLICY "Participants create reports" ON public.chat_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid() AND public.chat_is_participant(conversation_id::text));
DROP POLICY IF EXISTS "Reporter views own reports" ON public.chat_reports;
CREATE POLICY "Reporter views own reports" ON public.chat_reports
  FOR SELECT USING (reporter_id = auth.uid());

GRANT SELECT ON public.chat_conversations TO authenticated;
GRANT SELECT, INSERT ON public.chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_quick_replies TO authenticated;
GRANT SELECT, INSERT ON public.chat_reports TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 4. TRIGGER PESAN
-- ════════════════════════════════════════════════════════════
-- Sebelum simpan: waktu dari server, status awal kosong, filter kata kasar,
-- dan path gambar wajib berada di folder percakapan ini.
CREATE OR REPLACE FUNCTION public.chat_before_insert_message()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  w TEXT;
BEGIN
  NEW.created_at := NOW();
  NEW.delivered_at := NULL;
  NEW.read_at := NULL;
  NEW.body := btrim(COALESCE(NEW.body, ''));

  IF NEW.type = 'image' AND (NEW.image_path IS NULL OR NEW.image_path NOT LIKE NEW.conversation_id::text || '/%') THEN
    RAISE EXCEPTION 'Path gambar tidak valid' USING ERRCODE = '22023';
  END IF;

  IF (SELECT profanity_filter FROM public.chat_settings LIMIT 1) IS DISTINCT FROM FALSE THEN
    FOR w IN SELECT word FROM public.chat_banned_words LOOP
      NEW.body := regexp_replace(NEW.body, '\m' || w || '\M', repeat('*', char_length(w)), 'gi');
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_before_insert_message ON public.chat_messages;
CREATE TRIGGER chat_before_insert_message
  BEFORE INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.chat_before_insert_message();

-- Sesudah simpan: perbarui ringkasan percakapan, hitung belum dibaca,
-- dan kirim notifikasi in-app ke pelanggan jika mitra yang mengirim.
CREATE OR REPLACE FUNCTION public.chat_after_insert_message()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  c public.chat_conversations%ROWTYPE;
  v_preview TEXT;
BEGIN
  v_preview := CASE WHEN NEW.type = 'image'
                    THEN 'Foto' || CASE WHEN NEW.body <> '' THEN ': ' || NEW.body ELSE '' END
                    ELSE NEW.body END;
  v_preview := left(v_preview, 120);

  UPDATE public.chat_conversations
  SET last_message_at = NEW.created_at,
      last_message_preview = v_preview,
      last_sender_id = NEW.sender_id,
      customer_unread = customer_unread + CASE WHEN NEW.sender_id = owner_id THEN 1 ELSE 0 END,
      owner_unread    = owner_unread    + CASE WHEN NEW.sender_id = user_id  THEN 1 ELSE 0 END
  WHERE id = NEW.conversation_id
  RETURNING * INTO c;

  IF c.id IS NOT NULL AND NEW.sender_id = c.owner_id THEN
    INSERT INTO public.notifications (user_id, order_id, status, title, body)
    VALUES (c.user_id, c.order_id, 'chat',
            'Pesan baru dari ' || COALESCE(NULLIF(c.shop_name, ''), 'outlet'),
            v_preview);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS chat_after_insert_message ON public.chat_messages;
CREATE TRIGGER chat_after_insert_message
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.chat_after_insert_message();


-- ════════════════════════════════════════════════════════════
-- 5. RPC
-- ════════════════════════════════════════════════════════════
-- Buka (atau buat) percakapan untuk satu pesanan. Hanya pelanggan pemilik
-- pesanan atau pemilik outlet pesanan itu yang boleh.
CREATE OR REPLACE FUNCTION public.chat_open_conversation(p_order_id UUID)
RETURNS public.chat_conversations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o RECORD;
  c public.chat_conversations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi login berakhir' USING ERRCODE = '42501';
  END IF;

  SELECT ord.id, ord.user_id, ord.shop_id, ord.customer_name, s.owner_id, s.name AS shop_name
  INTO o
  FROM public.orders ord
  JOIN public.shops s ON s.id::text = ord.shop_id
  WHERE ord.id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pesanan tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;
  IF o.user_id IS NULL THEN
    RAISE EXCEPTION 'Pesanan walk-in tanpa akun pelanggan tidak bisa di-chat' USING ERRCODE = '22023';
  END IF;
  IF o.owner_id IS NULL THEN
    RAISE EXCEPTION 'Outlet belum terhubung ke akun mitra' USING ERRCODE = '22023';
  END IF;
  IF auth.uid() NOT IN (o.user_id, o.owner_id) THEN
    RAISE EXCEPTION 'Anda tidak terlibat dalam pesanan ini' USING ERRCODE = '42501';
  END IF;
  IF o.user_id = o.owner_id THEN
    RAISE EXCEPTION 'Akun pemilik outlet tidak bisa chat dengan dirinya sendiri' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.chat_conversations (order_id, shop_id, user_id, owner_id, customer_name, shop_name)
  VALUES (o.id, o.shop_id, o.user_id, o.owner_id, COALESCE(o.customer_name, ''), COALESCE(o.shop_name, ''))
  ON CONFLICT (order_id) DO UPDATE
    SET customer_name = CASE WHEN EXCLUDED.customer_name <> '' THEN EXCLUDED.customer_name ELSE chat_conversations.customer_name END,
        shop_name = CASE WHEN EXCLUDED.shop_name <> '' THEN EXCLUDED.shop_name ELSE chat_conversations.shop_name END
  RETURNING * INTO c;

  RETURN c;
END;
$$;

-- Tandai pesan dari lawan bicara sudah dibaca, nolkan hitungan belum dibaca milik sendiri
CREATE OR REPLACE FUNCTION public.chat_mark_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  c public.chat_conversations%ROWTYPE;
BEGIN
  SELECT * INTO c FROM public.chat_conversations WHERE id = p_conversation_id;
  IF NOT FOUND OR auth.uid() NOT IN (c.user_id, c.owner_id) THEN
    RAISE EXCEPTION 'Akses ditolak' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_messages
  SET read_at = NOW(), delivered_at = COALESCE(delivered_at, NOW())
  WHERE conversation_id = p_conversation_id
    AND sender_id <> auth.uid()
    AND read_at IS NULL;

  UPDATE public.chat_conversations
  SET customer_unread = CASE WHEN auth.uid() = user_id  THEN 0 ELSE customer_unread END,
      owner_unread    = CASE WHEN auth.uid() = owner_id THEN 0 ELSE owner_unread END
  WHERE id = p_conversation_id;

  -- Notifikasi chat untuk pesanan ini ikut terbaca
  UPDATE public.notifications
  SET is_read = TRUE
  WHERE user_id = auth.uid() AND order_id = c.order_id AND status = 'chat' AND is_read = FALSE;
END;
$$;

-- Tandai semua pesan masuk sudah DITERIMA perangkat (centang dua abu-abu)
CREATE OR REPLACE FUNCTION public.chat_mark_delivered()
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE public.chat_messages m
  SET delivered_at = NOW()
  FROM public.chat_conversations c
  WHERE m.conversation_id = c.id
    AND auth.uid() IN (c.user_id, c.owner_id)
    AND m.sender_id <> auth.uid()
    AND m.delivered_at IS NULL;
$$;

-- Blokir / buka blokir. Hanya yang memblokir yang bisa membuka blokir.
CREATE OR REPLACE FUNCTION public.chat_set_block(p_conversation_id UUID, p_block BOOLEAN)
RETURNS public.chat_conversations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  c public.chat_conversations%ROWTYPE;
BEGIN
  SELECT * INTO c FROM public.chat_conversations WHERE id = p_conversation_id;
  IF NOT FOUND OR auth.uid() NOT IN (c.user_id, c.owner_id) THEN
    RAISE EXCEPTION 'Akses ditolak' USING ERRCODE = '42501';
  END IF;
  IF p_block THEN
    IF c.blocked_by IS NULL THEN
      UPDATE public.chat_conversations SET blocked_by = auth.uid() WHERE id = p_conversation_id RETURNING * INTO c;
    END IF;
  ELSE
    IF c.blocked_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Hanya pihak yang memblokir yang bisa membuka blokir' USING ERRCODE = '42501';
    END IF;
    UPDATE public.chat_conversations SET blocked_by = NULL WHERE id = p_conversation_id RETURNING * INTO c;
  END IF;
  RETURN c;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_open_conversation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_mark_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_mark_delivered() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_set_block(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_is_participant(TEXT) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 6. STORAGE GAMBAR CHAT (privat, maks 3 MB, hanya gambar)
--    Path: {conversation_id}/{sender_id}_{timestamp}.jpg
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('chat-images', 'chat-images', FALSE, 3145728, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = FALSE,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Chat participants read images" ON storage.objects;
CREATE POLICY "Chat participants read images" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'chat-images' AND public.chat_is_participant((storage.foldername(name))[1]));

DROP POLICY IF EXISTS "Chat participants upload images" ON storage.objects;
CREATE POLICY "Chat participants upload images" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat-images' AND public.chat_is_participant((storage.foldername(name))[1]));


-- ════════════════════════════════════════════════════════════
-- 7. REALTIME
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_conversations') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
