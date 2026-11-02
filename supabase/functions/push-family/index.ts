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


// Akrabalık hitabı: ünvanlar reise göre saklanır; her alıcı göndereni KENDİSİNE göre görür.
// (Uygulamadaki lib/models.dart kinLabel ile aynı kurallar.)
type M = { user_id: string; role_title: string; icon: string | null; gender: string | null };
const FEMALE = new Set(["Anne", "Kızı", "Annesi", "Ninesi", "Gelini"]);
const MALE = new Set(["Aile Reisi", "Baba", "Oğlu", "Babası", "Dedesi", "Damadı"]);
const genderOf = (m: M) => m.gender ?? (FEMALE.has(m.role_title) ? "f" : MALE.has(m.role_title) ? "m" : null);

function kinLabel(viewer: M, target: M, reis: M | undefined): string {
  const t = target.role_title || "Aile ferdin";
  if (reis && viewer.user_id === reis.user_id) return POSSESSIVE[t] ?? t;
  const reisG = reis ? genderOf(reis) : null;
  let tg = genderOf(target);
  if (!tg && t === "Eşi" && reisG) tg = reisG === "m" ? "f" : "m";
  const pick = (m: string, f: string, n: string) => (tg === "f" ? f : tg === "m" ? m : n);
  const v = viewer.role_title;
  if (reis && target.user_id === reis.user_id) {
    const r: Record<string, string> = {
      "Eşi": "Eşin", "Oğlu": pick("Baban", "Annen", "Ebeveynin"), "Kızı": pick("Baban", "Annen", "Ebeveynin"),
      "Annesi": pick("Oğlun", "Kızın", "Çocuğun"), "Babası": pick("Oğlun", "Kızın", "Çocuğun"),
      "Kardeşi": "Kardeşin", "Torunu": pick("Deden", "Ninen", "Büyüğün"),
      "Gelini": pick("Kayınpederin", "Kayınvaliden", "Kayınbüyüğün"), "Damadı": pick("Kayınpederin", "Kayınvaliden", "Kayınbüyüğün"),
      "Dedesi": "Torunun", "Ninesi": "Torunun",
    };
    return r[v] ? `${r[v]} (${t})` : t;
  }
  const reisMale = reisG === "m";
  const table: Record<string, Record<string, string>> = {
    "Eşi": { "Oğlu": "Oğlun", "Kızı": "Kızın", "Torunu": "Torunun", "Gelini": "Gelinin", "Damadı": "Damadın", "Annesi": "Kayınvaliden", "Babası": "Kayınpederin" },
    "Oğlu": { "Eşi": pick("Baban", "Annen", "Ebeveynin"), "Oğlu": "Kardeşin", "Kızı": "Kardeşin", "Annesi": "Ninen", "Babası": "Deden",
      "Kardeşi": reisMale ? pick("Amcan", "Halan", "Amcan / Halan") : pick("Dayın", "Teyzen", "Dayın / Teyzen"), "Gelini": "Yengen", "Damadı": "Enişten" },
    "Annesi": { "Annesi": "Eşin", "Babası": "Eşin", "Eşi": pick("Damadın", "Gelinin", "Gelinin"), "Oğlu": "Torunun", "Kızı": "Torunun", "Torunu": "Torunun", "Kardeşi": pick("Oğlun", "Kızın", "Çocuğun") },
    "Kardeşi": { "Annesi": "Annen", "Babası": "Baban", "Kardeşi": "Kardeşin", "Oğlu": "Yeğenin", "Kızı": "Yeğenin", "Eşi": pick("Enişten", "Yengen", "Yengen") },
    "Gelini": { "Eşi": pick("Kayınpederin", "Kayınvaliden", "Kayınbüyüğün"), "Torunu": pick("Oğlun", "Kızın", "Çocuğun") },
    "Torunu": { "Eşi": pick("Deden", "Ninen", "Büyüğün") },
  };
  table["Kızı"] = table["Oğlu"]; table["Babası"] = table["Annesi"]; table["Damadı"] = table["Gelini"];
  const rel = table[v]?.[t];
  if (rel) return rel;
  return POSSESSIVE[t] && t !== "Aile Ferdi" ? `Aile Reisinin ${t}` : t;
}

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

function text(type: string, who: string, prayer: string | null, message: string, toMe = false): [string, string] | null {
  const p = prayer ? PRAYERS[prayer.toUpperCase()] ?? "" : "";
  switch (type) {
    case "PRAYED": return [`${who} namazını kıldı 🤲`, `${p} namazını kıldı. Allah kabul etsin.`];
    case "KAZA": return [`${who} kaza namazı kıldı 📿`, "Bir kaza namazı eda etti. Allah kabul etsin."];
    case "DUA": return [toMe ? `${who} sana dua gönderdi 🤲` : `${who} aileye dua gönderdi 🤲`, message || "Allah ibadetlerimizi kabul etsin."];
    case "MEMBER_JOINED": return ["Aile havuzuna katılım 🤝", `${message || who} aile havuzuna katıldı.`];
    default: return null;
  }
}

Deno.serve(async (req) => {
  try {
    const { event_id, check } = await req.json().catch(() => ({}));

    // Sağlık kontrolü: anahtar var mı ve Google'dan erişim izni alınabiliyor mu? (gizli bilgi döndürmez)
    if (check) {
      const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
      if (!raw) return Response.json({ configured: false });
      try {
        const sa = JSON.parse(raw);
        await accessToken(sa);
        return Response.json({ configured: true, oauth: "ok", project: sa.project_id });
      } catch (e) {
        return Response.json({ configured: true, oauth: "hata", detail: String(e).slice(0, 120) });
      }
    }

    if (!event_id) return new Response("event_id gerekli", { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Olayı tek seferlik sahiplen (yalnızca son 2 dk, henüz gönderilmemiş)
    const since = new Date(Date.now() - 120_000).toISOString();
    const { data: ev } = await db.from("pool_events")
      .update({ pushed_at: new Date().toISOString() })
      .eq("id", event_id).is("pushed_at", null).gte("created_at", since)
      .select("id, pool_id, sender_id, event_type, prayer, message, target_id").maybeSingle();
    if (!ev) return Response.json({ skipped: true });

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) return Response.json({ skipped: "FCM_SERVICE_ACCOUNT yok" });
    const sa = JSON.parse(saRaw);

    const [{ data: pool }, { data: members }] = await Promise.all([
      db.from("pools").select("owner_id").eq("id", ev.pool_id).single(),
      db.from("pool_members").select("user_id, role_title, icon, gender").eq("pool_id", ev.pool_id),
    ]);
    const sender = (members ?? []).find((m) => m.user_id === ev.sender_id);
    // Gönderenin ilk adı: aynı ünvanlı iki kişi ("Kızın") ayırt edilsin → "Kızın Ayşe"
    const { data: prof } = await db.from("profiles").select("display_name").eq("id", ev.sender_id).maybeSingle();
    const firstRaw = String(prof?.display_name ?? "").trim().split(/\s+/)[0] ?? "";
    const mixed = firstRaw !== firstRaw.toLocaleUpperCase("tr") && firstRaw !== firstRaw.toLocaleLowerCase("tr");
    const first = !firstRaw ? "" : mixed ? firstRaw
      : firstRaw[0].toLocaleUpperCase("tr") + firstRaw.slice(1).toLocaleLowerCase("tr");
    const withName = (label: string) => {
      if (!first || label.includes(first)) return label;
      const i = label.indexOf(" (");
      return i < 0 ? `${label} ${first}` : `${label.slice(0, i)} ${first}${label.slice(i)}`;
    };
    // Kişiye özel dua yalnızca o kişiye; diğer olaylar göndereni hariç herkese
    const recipients = ev.target_id
      ? [ev.target_id].filter((id) => id !== ev.sender_id && (members ?? []).some((m) => m.user_id === id))
      : (members ?? []).map((m) => m.user_id).filter((id) => id !== ev.sender_id);
    if (!recipients.length) return Response.json({ sent: 0 });

    // Kişinin bildirim tercihi: namaz / kaza / dua (katılım bildirimi herkese)
    const prefCol = ev.event_type === "PRAYED" ? "notify_prayer"
      : ev.event_type === "KAZA" ? "notify_kaza"
      : ev.event_type === "DUA" ? "notify_dua" : null;
    let q = db.from("devices").select("user_id, fcm_token, lock_screen").in("user_id", recipients);
    if (prefCol) q = q.eq(prefCol, true);
    const { data: devices } = await q;
    if (!devices?.length) return Response.json({ sent: 0, reason: "cihaz yok" });

    const token = await accessToken(sa);
    const icon = sender?.icon ? `${sender.icon} ` : "";
    const reis = (members ?? []).find((m) => m.user_id === pool?.owner_id) as M | undefined;
    let sent = 0;
    await Promise.all(devices.map(async (d) => {
      // Alıcıya göre akrabalık hitabı: reis "Kızın", kızı "Baban (Aile Reisi)" / "Annen" …
      const viewer = (members ?? []).find((m) => m.user_id === d.user_id) as M | undefined;
      const who = icon + withName(sender && viewer ? kinLabel(viewer, sender as M, reis) : (sender?.role_title || "Aile ferdin"));
      const t = text(ev.event_type, who, ev.prayer, ev.message ?? "", !!ev.target_id);
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
              notification: {
                channel_id: "aile_olaylari",
                sound: "default",
                tag: `ev-${ev.id}`,
                // Kilit ekranında içerik görünsün mü (kişinin tercihi)
                visibility: d.lock_screen === false ? "PRIVATE" : "PUBLIC",
              },
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
