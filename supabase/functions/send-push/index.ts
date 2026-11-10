// ============================================================
// WASHORA — Edge Function "send-push"
// Mengirim push notification ke semua perangkat (fcm_tokens) milik satu user
// lewat Firebase Cloud Messaging HTTP v1.
//
// Dipanggil oleh trigger database (supabase_push_sender.sql) dengan body:
//   { "user_id": "...", "title": "...", "body": "...", "data": { "order_id": "...", "type": "..." } }
// dan header "x-push-secret" yang harus sama dengan secret PUSH_WEBHOOK_SECRET.
//
// Secret yang wajib diisi (Dashboard → Edge Functions → Secrets):
//   FCM_SERVICE_ACCOUNT  = isi lengkap file JSON service account Firebase
//   PUSH_WEBHOOK_SECRET  = teks acak panjang (sama dengan push_settings.secret)
// SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY tersedia otomatis di Edge Functions.
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// ── Token OAuth Google (di-cache sampai mendekati kedaluwarsa) ──
let cached: { token: string; exp: number } | null = null;

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;

  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`OAuth Google gagal: ${res.status} ${await res.text()}`);
  const data = await res.json();
  cached = { token: data.access_token, exp: now + (data.expires_in ?? 3600) };
  return cached.token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Gunakan POST" });

  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
  if (!secret || req.headers.get("x-push-secret") !== secret) return json(401, { error: "Secret tidak cocok" });

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
  } catch {
    return json(500, { error: "Secret FCM_SERVICE_ACCOUNT belum diisi / bukan JSON" });
  }

  let payload: { user_id?: string; title?: string; body?: string; data?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "Body bukan JSON" });
  }
  if (!payload.user_id || !payload.title) return json(400, { error: "user_id & title wajib" });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: tokens, error } = await db.from("fcm_tokens").select("token").eq("user_id", payload.user_id);
  if (error) return json(500, { error: error.message });
  if (!tokens || tokens.length === 0) return json(200, { sent: 0, reason: "user belum punya token perangkat" });

  // FCM: semua nilai di "data" wajib string
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(payload.data ?? {})) if (v !== null && v !== undefined) data[k] = String(v);

  const access = await accessToken(sa);
  let sent = 0;
  const stale: string[] = [];

  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: payload.title, body: payload.body ?? "" },
          data,
          android: {
            priority: "HIGH",
            notification: { channel_id: "washora_channel", icon: "ic_stat_washora", color: "#0077B6" },
          },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      const text = await res.text();
      // Hanya token yang dinyatakan FCM tidak terdaftar lagi (aplikasi dihapus /
      // data dibersihkan) yang dihapus; error lain tidak boleh menghapus token
      if (res.status === 404 || text.includes("UNREGISTERED")) stale.push(token);
      console.error("FCM gagal", res.status, text);
    }
  }
  if (stale.length) await db.from("fcm_tokens").delete().in("token", stale);

  return json(200, { sent, removed: stale.length });
});
