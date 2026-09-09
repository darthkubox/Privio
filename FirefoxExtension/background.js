// Privio – tło wtyczki Firefox (ochrona stron), pełna para z wersją Chromium.
//
// Egzekwowanie jak w Chrome, ale firefoksowymi API (Chrome używa declarativeNetRequest
// + systemowego PAC; Firefox nie honoruje systemowego proxy i ma tylko ograniczone DNR):
//   1) `webRequest.onBeforeRequest` (blocking) – dla nawigacji głównej (main_frame) do
//      ZABLOKOWANEJ domeny przekierowuje na `unlock.html` (odpowiednik DNR-redirect z
//      Chrome). To daje natychmiastową ponowną blokadę po zablokowaniu w Privio oraz
//      ładny ekran zamiast surowego błędu.
//   2) `proxy.onRequest` – kieruje KIEROWANE (chronione) domeny do lokalnego proxy Privio
//      (127.0.0.1:8987) jako druga warstwa (podzasoby, ruch inny niż main_frame).
//   3) `blocker.js` (content script) – zapasowo, gdy przekierowanie webRequest nie zadziała.
//
// Wtyczka nic nie decyduje o blokadzie i nie zna sekretów – pobiera listy domen z
// lokalnego API Privio (`/privio/config`) i tylko trasuje/przekierowuje.

const API = "http://127.0.0.1:8987";
const PROXY = { type: "http", host: "127.0.0.1", port: 8987 };
const DIRECT = { type: "direct" };
const UNLOCK_URL = browser.runtime.getURL("unlock.html");

// Ostatnio znane listy z Privio. Przy nieudanym odpytaniu NIE czyścimy ich – jeśli
// Privio padło, zablokowane domeny mają pozostać zablokowane (bezpieczniej).
let routed = [];
let blocked = [];
let active = false; // protectionEnabled && !paused

// Śledzenie kart w pamięci (tło jest `persistent`, więc Mapy przeżywają).
const pendingTargets = new Map(); // tabId -> url, który chcemy otworzyć po odblokowaniu
const tabDomains = new Map();     // tabId -> chroniona domena aktualnie w karcie

const matchesDomain = (host, d) => host === d || host.endsWith(`.${d}`);
const hostOf = url => { try { return new URL(url).hostname.toLowerCase(); } catch (_) { return ""; } };
const routedDomainFor = url => { const h = hostOf(url); return routed.find(d => matchesDomain(h, d)) || null; };
const blockedDomainFor = url => { const h = hostOf(url); return blocked.find(d => matchesDomain(h, d)) || null; };

// --- 1) Blokada main_frame → unlock.html (odpowiednik DNR) --------------------
browser.webRequest.onBeforeRequest.addListener(
  details => {
    if (details.type !== "main_frame") return {};
    const domain = blockedDomainFor(details.url);
    if (!domain) return {};
    if (details.tabId >= 0) {
      pendingTargets.set(details.tabId, details.url);
      tabDomains.set(details.tabId, domain);
    }
    return { redirectUrl: UNLOCK_URL };
  },
  { urls: ["http://*/*", "https://*/*"], types: ["main_frame"] },
  ["blocking"]
);

// --- 2) Trasowanie chronionych domen do proxy Privio -------------------------
browser.proxy.onRequest.addListener(
  info => {
    if (!active || routed.length === 0) return DIRECT;
    return routedDomainFor(info.url) ? PROXY : DIRECT;
  },
  { urls: ["<all_urls>"] }
);

// --- 3) Wiadomości od popupu / unlock.html / blocker.js ----------------------
browser.runtime.onMessage.addListener((message, sender) => {
  if (message.type === "getPendingTarget") {
    return Promise.resolve({ target: pendingTargets.get(sender.tab?.id) || null });
  }
  if (message.type === "syncNow") {
    return sync().then(config => ({ config }));
  }
  if (message.type === "shouldBlock") {
    return sync().then(config => {
      const domain = (config?.blocked || []).find(d => matchesDomain(hostOf(message.url), d));
      if (!domain) return { blocked: false };
      if (sender.tab?.id != null) {
        pendingTargets.set(sender.tab.id, message.url);
        tabDomains.set(sender.tab.id, domain);
      }
      return { blocked: true, unlockURL: UNLOCK_URL };
    });
  }
  return undefined;
});

// --- Auto‑lock po zamknięciu ostatniej karty domeny (para z Chrome) ----------
async function lockIfNoOpenTab(domain) {
  if (!domain) return;
  await new Promise(resolve => setTimeout(resolve, 200));
  try {
    const tabs = await browser.tabs.query({});
    if (tabs.some(t => matchesDomain(hostOf(t.url || ""), domain))) return;
    await fetch(`${API}/privio/lock?domain=${encodeURIComponent(domain)}`, { cache: "no-store" });
    await sync();
  } catch (_) {}
}

browser.webNavigation.onCommitted.addListener(details => {
  if (details.frameId !== 0) return;
  const previous = tabDomains.get(details.tabId) || null;
  const current = routedDomainFor(details.url);
  if (current) {
    tabDomains.set(details.tabId, current);
    pendingTargets.delete(details.tabId);
  } else if (!details.url.startsWith(UNLOCK_URL)) {
    pendingTargets.delete(details.tabId);
    tabDomains.delete(details.tabId);
    if (previous) lockIfNoOpenTab(previous);
  }
});

browser.tabs.onRemoved.addListener(tabId => {
  const previous = tabDomains.get(tabId) || null;
  pendingTargets.delete(tabId);
  tabDomains.delete(tabId);
  if (previous) lockIfNoOpenTab(previous);
});

// --- Synchronizacja stanu z Privio ------------------------------------------
async function loadConfig() {
  const version = browser.runtime.getManifest().version;
  const res = await fetch(
    `${API}/privio/config?browser=Firefox&version=${encodeURIComponent(version)}`,
    { cache: "no-store" }
  );
  if (!res.ok) throw new Error(`Privio API ${res.status}`);
  return res.json();
}

async function sync() {
  try {
    const config = await loadConfig();
    routed = (config.routed || []).map(d => String(d).toLowerCase());
    blocked = (config.blocked || []).map(d => String(d).toLowerCase());
    const paused = !!config.pausedUntil && config.pausedUntil * 1000 > Date.now();
    active = !!config.protectionEnabled && !paused;
    await setIcon(active);
    return config;
  } catch (_) {
    // Privio nieosiągalne: zachowujemy ostatnio znane listy (zablokowane zostają
    // zablokowane). Ikona sygnalizuje offline.
    await setIcon(false);
    return null;
  }
}

async function setIcon(on) {
  const suffix = on ? "active" : "inactive";
  try {
    await browser.browserAction.setIcon({
      path: { 16: `icons/icon16-${suffix}.png`, 32: `icons/icon32-${suffix}.png` }
    });
    await browser.browserAction.setTitle({
      title: on ? "Privio: ochrona stron aktywna" : "Privio: ochrona wyłączona lub offline"
    });
  } catch (_) {}
}

browser.alarms.create("privio-sync", { periodInMinutes: 0.1 }); // ~6 s (minimum Firefoksa)
browser.alarms.onAlarm.addListener(a => { if (a.name === "privio-sync") sync(); });
browser.runtime.onStartup.addListener(sync);
browser.runtime.onInstalled.addListener(sync);

sync();
setInterval(sync, 2000); // szybszy puls; tło persistent to utrzymuje
