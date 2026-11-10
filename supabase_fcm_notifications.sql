-- ============================================================
-- WASHORA — FCM TOKEN & PUSH NOTIFICATION DISPATCH
-- Menyimpan FCM token per user/device & fungsi kirim notifikasi
-- Aman dijalankan berulang (idempotent).
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run.
-- ============================================================

-- ──────────────────────────────────────────
-- 1. TABEL FCM_TOKENS
-- Satu user bisa punya beberapa device (HP, tablet)
-- ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',  -- android / ios / web
  role TEXT NOT NULL DEFAULT 'customer',      -- customer / owner
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_user_token UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS fcm_tokens_user_idx ON public.fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS fcm_tokens_role_idx ON public.fcm_tokens(role);

-- ──────────────────────────────────────────
-- 2. RLS POLICIES
-- ──────────────────────────────────────────
ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User can manage their own FCM tokens" ON public.fcm_tokens;
CREATE POLICY "User can manage their own FCM tokens" ON public.fcm_tokens
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fcm_tokens TO authenticated;
GRANT ALL ON public.fcm_tokens TO service_role;   -- dibaca Edge Function send-push
REVOKE ALL ON public.fcm_tokens FROM anon;

-- ──────────────────────────────────────────
-- 3. FUNCTION UPSERT FCM TOKEN
-- Dipanggil dari Flutter saat user login / token refreshed
-- ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.upsert_fcm_token(
  p_token TEXT,
  p_platform TEXT DEFAULT 'android',
  p_role TEXT DEFAULT 'customer'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.fcm_tokens (user_id, token, platform, role, updated_at)
  VALUES (auth.uid(), p_token, p_platform, p_role, NOW())
  ON CONFLICT (user_id, token)
  DO UPDATE SET
    platform = EXCLUDED.platform,
    role = EXCLUDED.role,
    updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_fcm_token TO authenticated;

-- ──────────────────────────────────────────
-- 4. FUNCTION REMOVE FCM TOKEN (Saat Logout)
-- ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_fcm_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.fcm_tokens
  WHERE user_id = auth.uid() AND token = p_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_fcm_token TO authenticated;
