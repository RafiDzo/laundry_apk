-- ============================================================
-- WASHORA — PENGIRIM PUSH NOTIFICATION (FCM)
-- Jalankan SETELAH supabase_fcm_notifications.sql dan Edge Function "send-push"
-- sudah di-deploy. Aman dijalankan berulang.
--
-- Cara kerja:
--   • Setiap baris baru di tabel notifications (status pesanan, chat dari outlet,
--     klaim, poin, langganan, isi saldo, balasan ulasan) → push ke HP pelanggan.
--   • Push khusus mitra: pesanan baru, chat dari pelanggan, klaim baru, ulasan baru.
--   • Pengiriman lewat pg_net (asinkron): kalau push gagal, transaksi asli tetap jalan.
--
-- SETELAH MENJALANKAN, isi 1 baris di Table Editor → push_settings:
--   function_url = https://<project-ref>.supabase.co/functions/v1/send-push
--   secret       = teks acak panjang, SAMA dengan secret PUSH_WEBHOOK_SECRET di Edge Function
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Konfigurasi pengirim (tidak bisa dibaca aplikasi: RLS aktif tanpa policy)
CREATE TABLE IF NOT EXISTS public.push_settings (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  function_url TEXT NOT NULL DEFAULT '',
  secret TEXT NOT NULL DEFAULT '',
  enabled BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO public.push_settings (id) VALUES (TRUE) ON CONFLICT DO NOTHING;
ALTER TABLE public.push_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_settings FROM anon, authenticated;


-- Kirim satu push (tidak pernah menggagalkan transaksi pemanggil)
CREATE OR REPLACE FUNCTION public.send_push(p_user UUID, p_title TEXT, p_body TEXT, p_data JSONB DEFAULT '{}'::jsonb)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  s public.push_settings%ROWTYPE;
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  SELECT * INTO s FROM public.push_settings LIMIT 1;
  IF NOT FOUND OR NOT s.enabled OR s.function_url = '' OR s.secret = '' THEN RETURN; END IF;
  -- Hanya kirim jika user punya perangkat terdaftar
  IF NOT EXISTS (SELECT 1 FROM public.fcm_tokens WHERE user_id = p_user) THEN RETURN; END IF;

  PERFORM net.http_post(
    url := s.function_url,
    body := jsonb_build_object('user_id', p_user, 'title', left(COALESCE(p_title, 'Washora'), 120),
                               'body', left(COALESCE(p_body, ''), 240), 'data', COALESCE(p_data, '{}'::jsonb)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', s.secret),
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_push gagal: %', SQLERRM;
END;
$$;
-- PUBLIC juga dicabut: fungsi baru di PostgreSQL bisa dijalankan semua role secara bawaan
REVOKE ALL ON FUNCTION public.send_push(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;


-- ════════════════════════════════════════════════════════════
-- 1. Semua notifikasi in-app → push ke pemiliknya
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notifications_push()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.send_push(NEW.user_id, NEW.title, NEW.body,
    jsonb_build_object('type', COALESCE(NEW.status, ''), 'order_id', NEW.order_id, 'notification_id', NEW.id));
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS notifications_push ON public.notifications;
CREATE TRIGGER notifications_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_push();


-- ════════════════════════════════════════════════════════════
-- 2. Push untuk MITRA (pemilik outlet)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.shop_owner_of(p_shop_id TEXT)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT owner_id FROM public.shops WHERE id::text = p_shop_id;
$$;
REVOKE ALL ON FUNCTION public.shop_owner_of(TEXT) FROM PUBLIC, anon, authenticated;

-- Pesanan baru dari aplikasi
CREATE OR REPLACE FUNCTION public.push_owner_new_order()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NULL; END IF;   -- walk-in dicatat mitra sendiri
  PERFORM public.send_push(public.shop_owner_of(NEW.shop_id),
    'Pesanan baru masuk',
    COALESCE(NULLIF(NEW.customer_name, ''), 'Pelanggan') || ' · Rp ' ||
      REPLACE(TO_CHAR(COALESCE(NEW.total_price, 0), 'FM999,999,999'), ',', '.') ||
      CASE WHEN NEW.delivery_type = 'dropoff' THEN ' · antar sendiri' ELSE ' · perlu dijemput' END,
    jsonb_build_object('type', 'owner_new_order', 'order_id', NEW.id));
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS push_owner_new_order ON public.orders;
CREATE TRIGGER push_owner_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.push_owner_new_order();

-- Chat dari pelanggan, klaim baru, ulasan baru (dibuat hanya jika tabelnya ada)
CREATE OR REPLACE FUNCTION public.push_owner_chat()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  c RECORD;
BEGIN
  SELECT owner_id, user_id, order_id, customer_name INTO c FROM public.chat_conversations WHERE id = NEW.conversation_id;
  IF c.owner_id IS NULL OR NEW.sender_id IS DISTINCT FROM c.user_id THEN RETURN NULL; END IF;
  PERFORM public.send_push(c.owner_id,
    'Chat dari ' || COALESCE(NULLIF(c.customer_name, ''), 'pelanggan'),
    CASE WHEN NEW.type = 'image' THEN 'Mengirim foto' ELSE NEW.body END,
    jsonb_build_object('type', 'owner_chat', 'order_id', c.order_id));
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.push_owner_claim()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.send_push(public.shop_owner_of(NEW.shop_id),
    'Klaim kerusakan baru', 'Mohon tanggapi dalam 2x24 jam: ' || left(NEW.description, 120),
    jsonb_build_object('type', 'owner_claim', 'order_id', NEW.order_id));
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.push_owner_review()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.send_push(public.shop_owner_of(NEW.shop_id),
    'Ulasan baru ' || repeat('★', GREATEST(LEAST(NEW.rating, 5), 1)),
    CASE WHEN COALESCE(NEW.comment, '') = '' THEN 'Pelanggan memberi ' || NEW.rating || ' bintang.' ELSE left(NEW.comment, 140) END,
    jsonb_build_object('type', 'owner_review', 'order_id', NEW.order_id));
  RETURN NULL;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.chat_messages') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS push_owner_chat ON public.chat_messages';
    EXECUTE 'CREATE TRIGGER push_owner_chat AFTER INSERT ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION public.push_owner_chat()';
  END IF;
  IF to_regclass('public.damage_claims') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS push_owner_claim ON public.damage_claims';
    EXECUTE 'CREATE TRIGGER push_owner_claim AFTER INSERT ON public.damage_claims FOR EACH ROW EXECUTE FUNCTION public.push_owner_claim()';
  END IF;
  IF to_regclass('public.reviews') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS push_owner_review ON public.reviews';
    EXECUTE 'CREATE TRIGGER push_owner_review AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.push_owner_review()';
  END IF;
END $$;
