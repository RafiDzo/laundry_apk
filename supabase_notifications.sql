-- ============================================================
-- WASHORA — NOTIFIKASI PELANGGAN (menu lonceng)
-- Jalankan SETELAH supabase_install_all.sql.
-- Aman dijalankan berulang (idempotent).
--
-- Notifikasi dibuat otomatis oleh trigger database setiap kali status
-- pesanan berubah (termasuk dibatalkan). Karena dibuat di database,
-- notifikasi tidak bergantung pada aplikasi mitra dan tetap tercatat
-- walaupun pelanggan sedang offline.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  -- SET NULL (bukan CASCADE): jika mitra menghapus pesanan yang dibatalkan,
  -- notifikasi "Pesanan dibatalkan" tetap ada untuk pelanggan
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  status TEXT,
  title TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx
  ON public.notifications(user_id, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Pelanggan hanya bisa melihat & menandai-baca notifikasinya sendiri.
-- Tidak ada policy INSERT: notifikasi hanya dibuat oleh trigger di bawah.
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can mark own notifications" ON public.notifications;
CREATE POLICY "Users can mark own notifications" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Hanya kolom is_read yang boleh diubah dari aplikasi
GRANT SELECT ON public.notifications TO authenticated;
GRANT UPDATE (is_read) ON public.notifications TO authenticated;

-- ──────────────────────────────────────────
-- TRIGGER: buat notifikasi saat status pesanan berubah
-- ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_order_status_change()
RETURNS trigger AS $$
DECLARE
  v_shop  TEXT := COALESCE(NULLIF(NEW.shop_name, ''), 'Outlet');
  v_title TEXT;
  v_body  TEXT;
BEGIN
  -- Pesanan walk-in (tanpa akun) atau status tidak berubah: tidak ada notifikasi
  IF NEW.user_id IS NULL OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'pending' THEN
      v_title := 'Pesanan kembali ke antrean';
      v_body  := v_shop || ' memindahkan pesananmu ke antrean.';
    WHEN 'washing' THEN
      v_title := 'Cucianmu sedang dicuci';
      v_body  := v_shop || ' mulai mencuci pesananmu.';
    WHEN 'drying' THEN
      v_title := 'Pengeringan & setrika';
      v_body  := 'Cucianmu sedang dikeringkan dan dirapikan oleh ' || v_shop || '.';
    WHEN 'done' THEN
      v_title := 'Cucian selesai diproses';
      v_body  := CASE WHEN NEW.delivery_type = 'dropoff'
                   THEN 'Cucianmu sudah siap diambil di ' || v_shop || '.'
                   ELSE 'Cucianmu sudah siap dan akan segera diantar kurir.'
                 END;
    WHEN 'delivered' THEN
      v_title := 'Pesanan selesai';
      v_body  := CASE WHEN NEW.delivery_type = 'dropoff'
                   THEN 'Cucian sudah diambil. Terima kasih telah menggunakan Washora!'
                   ELSE 'Cucianmu sudah diantar. Terima kasih telah menggunakan Washora!'
                 END;
    WHEN 'cancelled' THEN
      v_title := 'Pesanan dibatalkan';
      v_body  := 'Pesananmu dibatalkan oleh ' || v_shop || '. Hubungi outlet jika ada pertanyaan.';
    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (user_id, order_id, status, title, body)
  VALUES (NEW.user_id, NEW.id, NEW.status, v_title, v_body);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_order_status_notify ON public.orders;
CREATE TRIGGER on_order_status_notify
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.notify_order_status_change();

-- ──────────────────────────────────────────
-- REALTIME: badge lonceng langsung bertambah tanpa refresh
-- ──────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END;
$$;
