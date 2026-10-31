// push-family: Aile havuzunda bir olay (namaz, kaza, dua, katılım) olunca diğer üyelerin
// telefonlarına Firebase Cloud Messaging (HTTP v1) ile bildirim gönderir.
//
// Tetikleme: pool_events tablosuna eklenen her satır için veritabanı tetikleyicisi bu fonksiyonu
// {event_id} ile çağırır. Fonksiyon olayı veritabanından kendisi okur ve "pushed_at" alanını
// atomik olarak işaretler: yalnızca son 2 dakikadaki, henüz gönderilmemiş gerçek olaylar işlenir.
// Bu yüzden dışarıdan çağrılması zararsızdır (aynı olay ikinci kez gönderilmez).
//
// Gizli ayar: FCM_SERVICE_ACCOUNT (Firebase hizmet hesabı JSON'u, Supabase Edge Function secret).
// SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Supabase tarafından otomatik sağlanır.

import { createClient } from "jsr:@supabase/supabase-js@2";

const POSSESSIVE: Record<string, string> = {
  "Eşi": "Eşin", "Oğlu": "Oğlun", "Kızı": "Kızın", "Annesi": "Annen", "Babası": "Baban",
  "Kardeşi": "Kardeşin", "Torunu": "Torunun", "Gelini": "Gelinin", "Damadı": "Damadın",
  "Dedesi": "Deden", "Ninesi": "Ninen",
};
const PRAYERS: Record<string, string> = {
  FAJR: "Sabah", DHUHR: "Öğle", ASR: "İkindi", MAGHRIB: "Akşam", ISHA: "Yatsı", WITR: "Vitir",
};

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedToken: { value: string; exp: number } | null = null;

async function accessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status}`);
  const j = await res.json();
  cachedToken = { value: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cachedToken.value;
}

function text(type: string, who: string, prayer: string | null, message: string): [string, string] | null {
  const p = prayer ? PRAYERS[prayer.toUpperCase()] ?? "" : "";
  switch (type) {
    case "PRAYED": return [`${who} namazını kıldı 🤲`, `${p} namazını kıldı. Allah kabul etsin.`];
    case "KAZA": return [`${who} kaza namazı kıldı 📿`, "Bir kaza namazı eda etti. Allah kabul etsin."];
    case "DUA": return [`${who} dua gönderdi 🤲`, message || "Allah ibadetlerimizi kabul etsin."];
    case "MEMBER_JOINED": return ["Aile havuzuna katılım 🤝", `${message || who} aile havuzuna katıldı.`];
    default: return null;
  }
}

Deno.serve(async (req) => {
  try {
    const { event_id } = await req.json().catch(() => ({}));
    if (!event_id) return new Response("event_id gerekli", { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Olayı tek seferlik sahiplen (yalnızca son 2 dk, henüz gönderilmemiş)
    const since = new Date(Date.now() - 120_000).toISOString();
    const { data: ev } = await db.from("pool_events")
      .update({ pushed_at: new Date().toISOString() })
      .eq("id", event_id).is("pushed_at", null).gte("created_at", since)
      .select("id, pool_id, sender_id, event_type, prayer, message").maybeSingle();
    if (!ev) return Response.json({ skipped: true });

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) return Response.json({ skipped: "FCM_SERVICE_ACCOUNT yok" });
    const sa = JSON.parse(saRaw);

    const [{ data: pool }, { data: members }] = await Promise.all([
      db.from("pools").select("owner_id").eq("id", ev.pool_id).single(),
      db.from("pool_members").select("user_id, role_title").eq("pool_id", ev.pool_id),
    ]);
    const sender = (members ?? []).find((m) => m.user_id === ev.sender_id);
    const recipients = (members ?? []).map((m) => m.user_id).filter((id) => id !== ev.sender_id);
    if (!recipients.length) return Response.json({ sent: 0 });

    const { data: devices } = await db.from("devices").select("user_id, fcm_token").in("user_id", recipients);
    if (!devices?.length) return Response.json({ sent: 0, reason: "cihaz yok" });

    const token = await accessToken(sa);
    const role = sender?.role_title || "Aile ferdin";
    let sent = 0;
    await Promise.all(devices.map(async (d) => {
      // Reis "Kızın / Oğlun" görür, diğerleri "Kızı / Oğlu"
      const who = d.user_id === pool?.owner_id ? (POSSESSIVE[role] ?? role) : role;
      const t = text(ev.event_type, who, ev.prayer, ev.message ?? "");
      if (!t) return;
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: d.fcm_token,
            notification: { title: t[0], body: t[1] },
            android: {
              priority: "HIGH",
              notification: { channel_id: "aile_olaylari", sound: "default", tag: `ev-${ev.id}` },
            },
            data: { type: ev.event_type, pool_id: ev.pool_id },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 400) {
        // Geçersiz / silinmiş cihaz adresi: listeden çıkar
        const body = await res.text();
        if (body.includes("UNREGISTERED") || body.includes("INVALID_ARGUMENT")) {
          await db.from("devices").delete().eq("user_id", d.user_id).eq("fcm_token", d.fcm_token);
        }
      }
    }));
    return Response.json({ sent });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
