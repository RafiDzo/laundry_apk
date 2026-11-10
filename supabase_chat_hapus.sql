-- ============================================================
-- WASHORA — HAPUS PESAN & PERCAKAPAN CHAT
-- Jalankan SETELAH supabase_chat.sql. Aman dijalankan berulang.
--
--   • Hapus untuk saya   : pesan disembunyikan hanya dari akun sendiri (kapan saja).
--   • Hapus untuk semua  : pengirim menarik pesan dalam 24 jam; isi & foto dihapus,
--                          lawan bicara melihat "Pesan ini telah dihapus".
--   • Hapus percakapan   : dari kotak masuk, tanpa membuka ruang chat. Riwayat lama
--                          hilang hanya untuk akun sendiri; pesan baru tetap masuk.
--   • Bersihkan lama     : hapus sekaligus percakapan yang tidak aktif N hari.
-- Laporan pesan menyimpan salinan isi pesan, jadi moderasi tetap punya bukti.
-- ============================================================

ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.chat_conversations ADD COLUMN IF NOT EXISTS customer_cleared_at TIMESTAMPTZ;
ALTER TABLE public.chat_conversations ADD COLUMN IF NOT EXISTS owner_cleared_at TIMESTAMPTZ;
ALTER TABLE public.chat_reports ADD COLUMN IF NOT EXISTS message_snapshot TEXT;

-- Pesan yang ditarik boleh kosong
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_message_content;
ALTER TABLE public.chat_messages ADD CONSTRAINT chat_message_content CHECK (
  deleted_at IS NOT NULL
  OR (type = 'text' AND char_length(btrim(body)) > 0)
  OR (type = 'image' AND image_path IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.chat_hidden_messages (
  user_id UUID NOT NULL DEFAULT auth.uid(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, message_id)
);
ALTER TABLE public.chat_hidden_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User manages own hidden messages" ON public.chat_hidden_messages;
CREATE POLICY "User manages own hidden messages" ON public.chat_hidden_messages
  FOR SELECT USING (user_id = auth.uid());
GRANT SELECT ON public.chat_hidden_messages TO authenticated;


-- Batas riwayat yang terlihat oleh akun yang login
CREATE OR REPLACE FUNCTION public.chat_cleared_at(p_conversation UUID)
RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE WHEN auth.uid() = c.owner_id THEN c.owner_cleared_at ELSE c.customer_cleared_at END
  FROM public.chat_conversations c WHERE c.id = p_conversation;
$$;

-- Pesan terlihat jika: peserta, sesudah batas "hapus percakapan", dan tidak disembunyikan sendiri
DROP POLICY IF EXISTS "Chat participants view messages" ON public.chat_messages;
CREATE POLICY "Chat participants view messages" ON public.chat_messages
  FOR SELECT USING (
    public.chat_is_participant(conversation_id::text)
    AND created_at > COALESCE(public.chat_cleared_at(conversation_id), '-infinity'::timestamptz)
    AND NOT EXISTS (
      SELECT 1 FROM public.chat_hidden_messages h
      WHERE h.message_id = chat_messages.id AND h.user_id = auth.uid()
    )
  );


-- ════════════════════════════════════════════════════════════
-- RPC
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.chat_delete_message(p_message_id UUID, p_for_everyone BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  m public.chat_messages%ROWTYPE;
  c public.chat_conversations%ROWTYPE;
  v_last UUID;
BEGIN
  SELECT * INTO m FROM public.chat_messages WHERE id = p_message_id FOR UPDATE;
  IF NOT FOUND OR NOT public.chat_is_participant(m.conversation_id::text) THEN
    RAISE EXCEPTION 'Pesan tidak ditemukan' USING ERRCODE = '42501';
  END IF;

  IF NOT p_for_everyone THEN
    INSERT INTO public.chat_hidden_messages (user_id, message_id) VALUES (auth.uid(), m.id)
    ON CONFLICT DO NOTHING;
    RETURN 'hidden';
  END IF;

  IF m.sender_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Hanya pengirim yang bisa menghapus pesan untuk semua orang' USING ERRCODE = '42501';
  END IF;
  IF m.deleted_at IS NOT NULL THEN RETURN 'deleted'; END IF;
  IF NOW() > m.created_at + INTERVAL '24 hours' THEN
    RAISE EXCEPTION 'Pesan lebih dari 24 jam hanya bisa dihapus untuk diri sendiri' USING ERRCODE = '22023';
  END IF;

  UPDATE public.chat_messages SET deleted_at = NOW(), body = '', image_path = NULL WHERE id = m.id;

  -- Perbarui ringkasan di kotak masuk jika ini pesan terakhir
  SELECT id INTO v_last FROM public.chat_messages
  WHERE conversation_id = m.conversation_id ORDER BY created_at DESC LIMIT 1;
  IF v_last = m.id THEN
    UPDATE public.chat_conversations SET last_message_preview = 'Pesan dihapus' WHERE id = m.conversation_id;
  END IF;
  RETURN 'deleted';
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_clear_conversation(p_conversation_id UUID)
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
  UPDATE public.chat_conversations
  SET owner_cleared_at    = CASE WHEN auth.uid() = owner_id THEN NOW() ELSE owner_cleared_at END,
      customer_cleared_at = CASE WHEN auth.uid() = user_id  THEN NOW() ELSE customer_cleared_at END,
      owner_unread        = CASE WHEN auth.uid() = owner_id THEN 0 ELSE owner_unread END,
      customer_unread     = CASE WHEN auth.uid() = user_id  THEN 0 ELSE customer_unread END
  WHERE id = p_conversation_id;
END;
$$;

-- Hapus semua percakapan yang tidak aktif lebih dari p_days hari. Mengembalikan jumlahnya.
CREATE OR REPLACE FUNCTION public.chat_clear_old(p_days INT DEFAULT 30)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  n INT;
BEGIN
  IF p_days < 1 THEN RAISE EXCEPTION 'Minimal 1 hari' USING ERRCODE = '22023'; END IF;
  UPDATE public.chat_conversations
  SET owner_cleared_at    = CASE WHEN auth.uid() = owner_id THEN NOW() ELSE owner_cleared_at END,
      customer_cleared_at = CASE WHEN auth.uid() = user_id  THEN NOW() ELSE customer_cleared_at END,
      owner_unread        = CASE WHEN auth.uid() = owner_id THEN 0 ELSE owner_unread END,
      customer_unread     = CASE WHEN auth.uid() = user_id  THEN 0 ELSE customer_unread END
  WHERE auth.uid() IN (user_id, owner_id)
    AND COALESCE(last_message_at, created_at) < NOW() - make_interval(days => p_days)
    AND COALESCE(last_message_at, created_at) > COALESCE(
          CASE WHEN auth.uid() = owner_id THEN owner_cleared_at ELSE customer_cleared_at END,
          '-infinity'::timestamptz);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_delete_message(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_clear_conversation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_clear_old(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_cleared_at(UUID) TO authenticated;


-- Laporan pesan menyimpan salinan isi pesan (bukti tetap ada walau pesan ditarik)
CREATE OR REPLACE FUNCTION public.chat_reports_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.message_id IS NOT NULL THEN
    SELECT CASE WHEN type = 'image' THEN '[Foto] ' || COALESCE(image_path, '') || ' ' || body ELSE body END
    INTO NEW.message_snapshot
    FROM public.chat_messages WHERE id = NEW.message_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS chat_reports_snapshot ON public.chat_reports;
CREATE TRIGGER chat_reports_snapshot
  BEFORE INSERT ON public.chat_reports
  FOR EACH ROW EXECUTE FUNCTION public.chat_reports_snapshot();


-- Foto yang ditarik: pengirim boleh menghapus file miliknya di storage
DROP POLICY IF EXISTS "Chat sender deletes own images" ON storage.objects;
CREATE POLICY "Chat sender deletes own images" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND public.chat_is_participant((storage.foldername(name))[1])
    AND storage.filename(name) LIKE auth.uid()::text || '\_%'
  );

NOTIFY pgrst, 'reload schema';
