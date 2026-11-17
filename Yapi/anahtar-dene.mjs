// App Store Connect API anahtarını dener; gizli değerleri YAZDIRMAZ.
// Ortam: ASC_KEY_ID, ASC_ISSUER_ID, APPLE_TEAM_ID, ASC_KEY_P8.
// Her denetim için "tamam" ya da sorunun ne olduğunu yazar; sorun varsa 1 ile çıkar.
import { createPrivateKey, sign } from 'node:crypto';

const BUNDLE = 'com.vizemia.app';
const env = (ad) => String(process.env[ad] || '');
let sorun = 0;
const tamam = (m) => console.log(`✓ ${m}`);
const hata = (m) => { console.log(`::error::${m}`); sorun += 1; };

const keyId = env('ASC_KEY_ID').trim();
const issuer = env('ASC_ISSUER_ID').trim();
const team = env('APPLE_TEAM_ID').trim();
const p8 = env('ASC_KEY_P8');

// Biçim denetimleri (yalnız uzunluk ve desen; değer gösterilmez)
if (/^[A-Z0-9]{10}$/.test(keyId)) tamam('ASC_KEY_ID biçimi doğru (10 karakter)');
else hata(`ASC_KEY_ID 10 büyük harf/rakam olmalı; şu an ${keyId.length} karakter${/\s/.test(env('ASC_KEY_ID')) ? ', boşluk içeriyor' : ''}`);
if (env('ASC_KEY_ID') !== keyId) hata('ASC_KEY_ID başında ya da sonunda boşluk/satır sonu var');

if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(issuer)) tamam('ASC_ISSUER_ID biçimi doğru (tireli kimlik)');
else hata(`ASC_ISSUER_ID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" biçiminde olmalı; şu an ${issuer.length} karakter. Bu değer Integrations sayfasının üstündeki "Issuer ID"; anahtarın Key ID'si değil.`);
if (env('ASC_ISSUER_ID') !== issuer) hata('ASC_ISSUER_ID başında ya da sonunda boşluk/satır sonu var');

if (/^[A-Z0-9]{10}$/.test(team)) tamam('APPLE_TEAM_ID biçimi doğru (10 karakter)');
else hata(`APPLE_TEAM_ID 10 büyük harf/rakam olmalı; şu an ${team.length} karakter`);
if (team && team === keyId) hata('APPLE_TEAM_ID ile ASC_KEY_ID aynı: ikisinden biri yanlış yere girilmiş');

const satirlar = p8.trim().split(/\r?\n/);
if (!p8.includes('-----BEGIN PRIVATE KEY-----')) hata('ASC_KEY_P8 "-----BEGIN PRIVATE KEY-----" satırıyla başlamıyor (dosyanın tamamı yapıştırılmalı)');
else if (!p8.includes('-----END PRIVATE KEY-----')) hata('ASC_KEY_P8 "-----END PRIVATE KEY-----" satırı eksik');
else tamam(`ASC_KEY_P8 başlık ve bitiş satırları var (${satirlar.length} satır)`);

let anahtar = null;
try {
  anahtar = createPrivateKey({ key: p8.trim() + '\n', format: 'pem' });
  if (anahtar.asymmetricKeyType === 'ec') tamam('ASC_KEY_P8 geçerli bir Apple anahtarı (EC)');
  else hata(`ASC_KEY_P8 Apple anahtarı değil (tür: ${anahtar.asymmetricKeyType})`);
} catch (e) {
  hata(`ASC_KEY_P8 okunamadı: dosya eksik ya da bozuk kopyalanmış (${e.code || e.message})`);
}

if (!anahtar || sorun) {
  console.log('Biçim sorunları düzeltilmeden Apple\'a sorulmadı.');
  process.exit(1);
}

// Apple'a sor
const b64 = (x) => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');
const simdi = Math.floor(Date.now() / 1000);
const govde = `${b64({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${b64({ iss: issuer, iat: simdi, exp: simdi + 600, aud: 'appstoreconnect-v1' })}`;
const imza = sign('sha256', Buffer.from(govde), { key: anahtar, dsaEncoding: 'ieee-p1363' }).toString('base64url');
const jwt = `${govde}.${imza}`;

async function sor(yol) {
  const r = await fetch(`https://api.appstoreconnect.apple.com/v1/${yol}`, { headers: { Authorization: `Bearer ${jwt}` } });
  let j = {};
  try { j = await r.json(); } catch { /* boş */ }
  return { durum: r.status, j };
}

const apps = await sor(`apps?filter[bundleId]=${BUNDLE}&fields[apps]=name,bundleId`);
if (apps.durum === 401) {
  hata('Apple anahtarı reddetti (401). Olası nedenler: Key ID ile .p8 dosyası farklı anahtarlara ait; Issuer ID yanlış; anahtar iptal edilmiş; ya da "Individual Keys" sekmesinden oluşturulmuş (Team Keys olmalı).');
} else if (apps.durum === 403) {
  hata('Anahtar geçerli ama yetkisi yetmiyor (403). Anahtarın Access değeri "Admin" olmalı.');
} else if (apps.durum !== 200) {
  hata(`Apple beklenmeyen cevap verdi: ${apps.durum} ${JSON.stringify(apps.j.errors?.[0]?.title || '')}`);
} else {
  tamam('Apple anahtarı kabul etti');
  const bulunan = (apps.j.data || []).map((a) => a.attributes?.name);
  if (bulunan.length) tamam(`App Store Connect'te ${BUNDLE} kayıtlı uygulama var: ${bulunan.join(', ')}`);
  else hata(`App Store Connect'te ${BUNDLE} kimlikli uygulama yok: Apps → + → New App ile açılmalı (Bundle ID listeden ${BUNDLE}).`);
  const bid = await sor(`bundleIds?filter[identifier]=${BUNDLE}&fields[bundleIds]=identifier,platform`);
  if (bid.durum === 200 && (bid.j.data || []).length) tamam(`${BUNDLE} uygulama kimliği kayıtlı`);
  else if (bid.durum === 200) hata(`${BUNDLE} uygulama kimliği (Identifier) kayıtlı değil`);
}

if (sorun) process.exit(1);
console.log('Anahtar ve uygulama kaydı hazır.');
