// push-family: Aile havuzunda bir olay (namaz, kaza, dua, katılım) olunca diğer üyelerin
// telefonlarına Firebase Cloud Messaging (HTTP v1) ile bildirim gönderir.
//
// Tetikleme: pool_events tablosuna eklenen her satır için veritabanı tetikleyicisi bu fonksiyonu
// {event_id} ile çağırır; ayrıca her dakika çalışan görev (aile-push-retry) bekleyen veya başarısız
// olayları yeniden çağırır. Kuyruk: pending → processing → sent / failed (en fazla 3 deneme, 10 dk).
// Olay claim_push_event ile atomik sahiplenilir: aynı olay aynı anda iki kez işlenmez. Google'a
// bağlanılamazsa (OAuth) ya da hiçbir cihaza geçici hata yüzünden gidemezse "failed" olur, tekrar denenir.
//
// Gizli ayar: FCM_SERVICE_ACCOUNT (Firebase hizmet hesabı JSON'u, Supabase Edge Function secret).
// SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Supabase tarafından otomatik sağlanır.

// Tam sürüm sabit: her dağıtım aynı bağımlılığı çözer (sürüm yükseltmesi bilerek ve test edilerek yapılır).
import { createClient } from "jsr:@supabase/supabase-js@2.119.0";

const POSSESSIVE: Record<string, string> = {
  "Eşi": "Eşin", "Oğlu": "Oğlun", "Kızı": "Kızın", "Annesi": "Annen", "Babası": "Baban",
  "Kardeşi": "Kardeşin", "Torunu": "Torunun", "Gelini": "Gelinin", "Damadı": "Damadın",
  "Dedesi": "Deden", "Ninesi": "Ninen",
};
const PRAYERS: Record<string, string> = {
  FAJR: "Sabah", DHUHR: "Öğle", ASR: "İkindi", MAGHRIB: "Akşam", ISHA: "Yatsı", WITR: "Vitir",
};
const PRAYERS_EN: Record<string, string> = {
  FAJR: "Fajr", DHUHR: "Dhuhr", ASR: "Asr", MAGHRIB: "Maghrib", ISHA: "Isha", WITR: "Witr",
};

// Ünvan ve hitapların İngilizcesi (uygulamadaki lib/models.dart _kinEn ile aynı). Alıcının cihaz dili
// 'en' ise bildirim İngilizce gider; veritabanında ünvanlar hep Türkçe saklanır.
const KIN_EN: Record<string, string> = {
  "Aile Reisi": "Head of Family", "Baba": "Father", "Anne": "Mother", "Aile Ferdi": "Family Member",
  "Eşi": "Spouse", "Oğlu": "Son", "Kızı": "Daughter", "Annesi": "Mother", "Babası": "Father",
  "Kardeşi": "Sibling", "Torunu": "Grandchild", "Gelini": "Daughter-in-law", "Damadı": "Son-in-law",
  "Dedesi": "Grandfather", "Ninesi": "Grandmother",
  "Eşin": "Your spouse", "Oğlun": "Your son", "Kızın": "Your daughter", "Annen": "Your mother",
  "Baban": "Your father", "Kardeşin": "Your sibling", "Torunun": "Your grandchild",
  "Gelinin": "Your daughter-in-law", "Damadın": "Your son-in-law", "Deden": "Your grandfather",
  "Ninen": "Your grandmother", "Ebeveynin": "Your parent", "Çocuğun": "Your child",
  "Büyüğün": "Your grandparent", "Kayınpederin": "Your father-in-law", "Kayınvaliden": "Your mother-in-law",
  "Kayınbüyüğün": "Your parent-in-law", "Amcan": "Your uncle", "Halan": "Your aunt", "Dayın": "Your uncle",
  "Teyzen": "Your aunt", "Amcan / Halan": "Your uncle / aunt", "Dayın / Teyzen": "Your uncle / aunt",
  "Yengen": "Your sister-in-law", "Enişten": "Your brother-in-law", "Yeğenin": "Your niece / nephew",
  "Aile ferdin": "A family member",
};
const kin = (tr: string, en: boolean) => (en ? KIN_EN[tr] ?? tr : tr);


// Akrabalık hitabı: ünvanlar reise göre saklanır; her alıcı göndereni KENDİSİNE göre görür.
// (Uygulamadaki lib/models.dart kinLabel ile aynı kurallar.)
type M = { user_id: string; role_title: string; icon: string | null; gender: string | null };
const FEMALE = new Set(["Anne", "Kızı", "Annesi", "Ninesi", "Gelini"]);
const MALE = new Set(["Aile Reisi", "Baba", "Oğlu", "Babası", "Dedesi", "Damadı"]);
const genderOf = (m: M) => m.gender ?? (FEMALE.has(m.role_title) ? "f" : MALE.has(m.role_title) ? "m" : null);

function kinLabel(viewer: M, target: M, reis: M | undefined, en = false): string {
  const t = target.role_title || "Aile ferdin";
  if (reis && viewer.user_id === reis.user_id) return kin(POSSESSIVE[t] ?? t, en);
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
    return r[v] ? `${kin(r[v], en)} (${kin(t, en)})` : kin(t, en);
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
  if (rel) return kin(rel, en);
  if (POSSESSIVE[t] && t !== "Aile Ferdi") {
    return en ? `Head of family's ${kin(t, true).toLowerCase()}` : `Aile Reisinin ${t}`;
  }
  return kin(t, en);
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

// Hazır aile mesajlarının İngilizcesi (uygulamadaki familyMessagesEn ile aynı; test denetler).
// Uygulama bunları her zaman Türkçe gönderir; İngilizce cihaza bu karşılık gider.
const GREET_EN: Record<string, string> = {
  "Allah kabul etsin, kıldığın namazlar kalbine nur, ömrüne huzur ve bereket olsun kardeşim.": "May Allah accept it; may your prayers be light for your heart and peace and blessing for your life, my dear.",
  "Rabbim kıldığın namazları, ettiğin duaları dergâh-ı izzetinde en güzel şekilde makbul eylesin.": "May my Lord accept your prayers and supplications in His exalted presence in the most beautiful way.",
  "Namaz dinin direğidir. Birlikte hayırda yarışarak istikrarımızı koruduğumuz için Elhamdülillah!": "Prayer is the pillar of the religion. Alhamdulillah that we keep our consistency by competing together in good deeds!",
  "Rabbim sana ve ailene afiyet, kalbine inşirah, hanene bereket ihsan eylesin.": "May my Lord grant you and your family well-being, ease to your heart and blessing to your home.",
  "Kaza namazlarını eritmeye devam; Rabbim azmini, gayretini ve sevabını kat kat artırsın.": "Keep making up your missed prayers; may my Lord multiply your resolve, your effort and your reward.",
  "Günün farzlarını tamamlayarak huzurla geceye kavuşturan Yüce Allah'a hamdolsun.": "Praise be to Allah the Exalted, who let us complete the day's obligatory prayers and reach the night in peace.",
  "🎉 Ramazan Bayramınız mübarek olsun! Allah nice bayramlara sağlık, huzur ve birlik içinde ulaştırsın. 🤲": "🎉 Eid al-Fitr Mubarak! May Allah let us reach many more Eids in health, peace and togetherness. 🤲",
  "🐑 Kurban Bayramınız mübarek olsun! Allah nice bayramlara sağlık, huzur ve birlik içinde ulaştırsın. 🤲": "🐑 Eid al-Adha Mubarak! May Allah let us reach many more Eids in health, peace and togetherness. 🤲",
};
// İngilizce → Türkçe (1.78 sürümü hazır mesajı gönderenin dilinde yolluyordu)
const GREET_TR: Record<string, string> = Object.fromEntries(Object.entries(GREET_EN).map(([tr, en]) => [en, tr]));

// Hazır mesajı alıcının dilinde verir; kendi yazılmış mesaj olduğu gibi kalır. Object.hasOwn:
// "constructor", "__proto__" gibi bir mesaj nesnenin kendi alanlarına denk gelmesin.
function greeting(message: string, en: boolean): string {
  if (!message) return "";
  const map = en ? GREET_EN : GREET_TR;
  return Object.hasOwn(map, message) ? map[message] : message;
}

function text(type: string, who: string, prayer: string | null, message: string, toMe = false, en = false): [string, string] | null {
  if (en) {
    const p = prayer ? PRAYERS_EN[prayer.toUpperCase()] ?? "" : "";
    switch (type) {
      case "PRAYED": return [`${who} prayed 🤲`, `Prayed ${p}. May Allah accept it.`];
      case "KAZA": return [`${who} made up a missed prayer 📿`, "Completed one kaza prayer. May Allah accept it."];
      case "ALL_PRAYED": return [`${who} prayed all 5 prayers 🌟`, "Masha'Allah! Completed all of the day's prayers. May Allah accept them."];
      case "DUA": return [toMe ? `${who} sent you a dua 🤲` : `${who} sent the family a dua 🤲`, greeting(message, true) || "May Allah accept our worship."];
      case "MEMBER_JOINED": return ["New family member 🤝", `${message ? kin(message, true) : who} joined the family circle.`];
      case "PRO_REQUEST": return [`${who} wants Pro 🌟`, "If you get Family Pro, everyone in the circle becomes Pro."];
      default: return null;
    }
  }
  const p = prayer ? PRAYERS[prayer.toUpperCase()] ?? "" : "";
  switch (type) {
    case "PRAYED": return [`${who} namazını kıldı 🤲`, `${p} namazını kıldı. Allah kabul etsin.`];
    case "KAZA": return [`${who} kaza namazı kıldı 📿`, "Bir kaza namazı eda etti. Allah kabul etsin."];
    case "ALL_PRAYED": return [`${who} 5 vaktin hepsini kıldı 🌟`, "Maşallah! Günün bütün namazlarını eda etti. Allah kabul etsin."];
    case "DUA": return [toMe ? `${who} sana dua gönderdi 🤲` : `${who} aileye dua gönderdi 🤲`, greeting(message, false) || "Allah ibadetlerimizi kabul etsin."];
    case "MEMBER_JOINED": return ["Aile havuzuna katılım 🤝", `${message || who} aile havuzuna katıldı.`];
    case "PRO_REQUEST": return [`${who} Pro istiyor 🌟`, "Aile Pro'sunu alırsan havuzdaki herkes Pro olur."];
    default: return null;
  }
}

// Çağrı anahtarı: yalnızca veritabanı tetikleyicisi ve tekrar deneme görevi bilir (Vault'ta üretilir).
// Anahtar okunamazsa ya da tutmazsa çağrı reddedilir (fail-closed). Önbellek: anahtar her istekte okunmaz.
let hookSecret: { value: string; at: number } | null = null;
async function expectedSecret(db: ReturnType<typeof createClient>): Promise<string | null> {
  if (hookSecret && Date.now() - hookSecret.at < 10 * 60_000) return hookSecret.value;
  const { data, error } = await db.rpc("push_hook_secret");
  if (error || typeof data !== "string" || data.length < 32) return null;
  hookSecret = { value: data, at: Date.now() };
  return data;
}

function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const given = req.headers.get("x-push-secret") ?? "";
    const expected = await expectedSecret(db);
    if (!expected || !given || !sameSecret(given, expected)) {
      return new Response("yetkisiz", { status: 401 });
    }

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
        return Response.json({ configured: true, oauth: "hata" });
      }
    }

    if (!event_id) return new Response("event_id gerekli", { status: 400 });

    // Olayı atomik sahiplen (pending/failed, 3 denemeden az, son 10 dk)
    const { data: claimed } = await db.rpc("claim_push_event", { p_id: event_id });
    const ev = (claimed ?? [])[0];
    if (!ev) return Response.json({ skipped: true });
    const finish = (ok: boolean) => db.rpc("finish_push_event", { p_id: ev.id, p_ok: ok });

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) { await finish(false); return Response.json({ skipped: "FCM_SERVICE_ACCOUNT yok" }); }
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
    // Ad yalnızca çocuklarda (Oğlu, Kızı, Torunu) ya da aynı ünvanlı birden fazla kişi varsa eklenir;
    // anne, baba, eş ve Aile Reisi tek olduğu için adsız kalır.
    const CHILD = new Set(["Oğlu", "Kızı", "Torunu"]);
    const sameTitle = (members ?? []).filter((m) => m.role_title && m.role_title === sender?.role_title).length;
    const needName = !!sender && (CHILD.has(sender.role_title) || sameTitle > 1);
    const withName = (label: string) => {
      if (!needName || !first || label.includes(first)) return label;
      const i = label.indexOf(" (");
      return i < 0 ? `${label} ${first}` : `${label.slice(0, i)} ${first}${label.slice(i)}`;
    };
    // Kişiye özel dua yalnızca o kişiye; diğer olaylar göndereni hariç herkese
    const recipients = ev.target_id
      ? [ev.target_id].filter((id) => id !== ev.sender_id && (members ?? []).some((m) => m.user_id === id))
      : (members ?? []).map((m) => m.user_id).filter((id) => id !== ev.sender_id);
    if (!recipients.length || !text(ev.event_type, "", ev.prayer, "", false)) {
      await finish(true); // gönderilecek kimse / bildirimi olmayan olay türü
      return Response.json({ sent: 0 });
    }

    // Kişinin bildirim tercihi: namaz / kaza / dua (katılım bildirimi herkese)
    const prefCol = ev.event_type === "PRAYED" || ev.event_type === "ALL_PRAYED" ? "notify_prayer"
      : ev.event_type === "KAZA" ? "notify_kaza"
      : ev.event_type === "DUA" ? "notify_dua" : null;
    let q = db.from("devices").select("user_id, fcm_token, lock_screen, lang").in("user_id", recipients);
    if (prefCol) q = q.eq(prefCol, true);
    const { data: rawDevices, error: devErr } = await q;
    // Cihaz listesi okunamazsa olay "gönderildi" sayılmasın: tekrar denensin (fail-closed)
    if (devErr) { await finish(false); return Response.json({ error: devErr.message, retry: true }, { status: 500 }); }
    const seen = new Set<string>();
    const devices = (rawDevices ?? []).filter((d) => !seen.has(d.fcm_token) && !!seen.add(d.fcm_token));
    if (!devices.length) { await finish(true); return Response.json({ sent: 0, reason: "cihaz yok" }); }

    let token: string;
    try {
      token = await accessToken(sa);
    } catch (e) {
      await finish(false); // Google bağlantısı yok: bir dakika içinde tekrar denenecek
      return Response.json({ error: String(e), retry: true }, { status: 502 });
    }
    const icon = sender?.icon ? `${sender.icon} ` : "";
    const reis = (members ?? []).find((m) => m.user_id === pool?.owner_id) as M | undefined;
    let sent = 0, transient = 0;
    await Promise.all(devices.map(async (d) => {
      // Alıcıya göre akrabalık hitabı: reis "Kızın", kızı "Baban (Aile Reisi)" / "Annen" …
      const viewer = (members ?? []).find((m) => m.user_id === d.user_id) as M | undefined;
      const en = d.lang === "en"; // alıcının uygulama dili (bilinmiyorsa Türkçe)
      const who = icon + withName(sender && viewer ? kinLabel(viewer, sender as M, reis, en) : kin(sender?.role_title || "Aile ferdin", en));
      const t = text(ev.event_type, who, ev.prayer, ev.message ?? "", !!ev.target_id, en);
      if (!t) return;
      const send = () => fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: d.fcm_token,
            notification: { title: t[0], body: t[1] },
            android: {
              priority: "HIGH",
              // Ulaşamazsa 1 saat sonra düşsün: telefon uzun süre kapalı/kayıtsız kalınca eski bildirimler topluca gelmez
              ttl: "3600s",
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
      let res = await send().catch(() => null);
      // Geçici hata (ağ, 429, 5xx): o cihaza bir kez daha dene
      if (!res || res.status === 429 || res.status >= 500) {
        await new Promise((r) => setTimeout(r, 800));
        res = await send().catch(() => null);
      }
      if (!res || res.status === 429 || res.status >= 500) {
        transient++;
        return;
      }
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 400) {
        // Yalnızca cihaz adresi gerçekten geçersizse listeden çıkar. Mesaj içeriğinden kaynaklanan
        // bir 400 (INVALID_ARGUMENT ama adres geçerli) geçerli cihazı silmesin.
        const body = await res.text();
        const badToken = res.status === 404 || body.includes("UNREGISTERED") ||
          (body.includes("INVALID_ARGUMENT") && /registration token|message\.token|"token"/i.test(body));
        if (badToken) {
          await db.from("devices").delete().eq("user_id", d.user_id).eq("fcm_token", d.fcm_token);
        }
      }
    }));
    // Hiçbir cihaza gidemediyse ve sebep geçiciyse olay tekrar denenecek
    await finish(!(sent === 0 && transient > 0));
    return Response.json({ sent, transient });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
