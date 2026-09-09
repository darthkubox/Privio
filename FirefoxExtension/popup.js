const API = "http://127.0.0.1:8987";
const manifest = chrome.runtime.getManifest();
const connection = document.querySelector("#connection");
const hero = document.querySelector("#hero");
const title = document.querySelector("#title");
const description = document.querySelector("#description");
const protectedCount = document.querySelector("#protectedCount");
const blockedCount = document.querySelector("#blockedCount");
const currentSite = document.querySelector("#currentSite");
const currentState = document.querySelector("#currentState");
const siteAction = document.querySelector("#siteAction");
const unprotectSite = document.querySelector("#unprotectSite");
const pauseControls = document.querySelector("#pauseControls");
const pausedBanner = document.querySelector("#pausedBanner");
const pausedText = document.querySelector("#pausedText");
const toast = document.querySelector("#toast");
document.querySelector("#version").textContent = `v${manifest.version}`;

let lang = "en";
const matches = (host, domain) => host === domain || host.endsWith(`.${domain}`);
const T = key => PrivioI18n.t(lang, key);

async function resolveLanguage(appLanguage) {
  const pref = await PrivioI18n.storedPref();
  const next = PrivioI18n.resolve(pref, appLanguage);
  if (next !== lang) {
    lang = next;
    PrivioI18n.apply(document, lang);
  }
}

function showToast(message, isError) {
  toast.textContent = message;
  toast.classList.toggle("error", !!isError);
  toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { toast.hidden = true; }, 3200);
}

async function refresh() {
  connection.className = "pill waiting";
  connection.querySelector("span").textContent = T("conn_connecting");
  try {
    const response = await fetch(`${API}/privio/config?browser=${encodeURIComponent(PrivioEnv.browser())}&version=${encodeURIComponent(manifest.version)}`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    const config = await response.json();
    await resolveLanguage(config.language);

    const paused = !!config.pausedUntil && config.pausedUntil * 1000 > Date.now();
    connection.className = "pill connected";
    connection.querySelector("span").textContent = T("conn_connected");
    if (paused) {
      hero.className = "hero disabled";
      hero.querySelector(".shield").textContent = "⏸";
      title.textContent = T("hero_paused_title");
      description.textContent = T("hero_paused_desc");
    } else {
      hero.className = config.protectionEnabled ? "hero active" : "hero disabled";
      hero.querySelector(".shield").textContent = config.protectionEnabled ? "✓" : "-";
      title.textContent = T(config.protectionEnabled ? "hero_active_title" : "hero_disabled_title");
      description.textContent = T(config.protectionEnabled ? "hero_active_desc" : "hero_disabled_desc");
    }
    protectedCount.textContent = (config.configured || config.routed || []).length;
    blockedCount.textContent = (config.blocked || []).length;

    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    let host = "";
    try { host = new URL(tab?.url || "").hostname; } catch (_) {}
    currentSite.textContent = host || T("current_none");
    const routed = (config.routed || []).find(domain => matches(host, domain));
    const blocked = (config.blocked || []).find(domain => matches(host, domain));
    currentState.className = blocked ? "mini locked" : (routed ? "mini good" : "mini neutral");
    currentState.textContent = T(blocked ? "state_blocked" : (routed ? "state_protected" : "state_unprotected"));
    const configured = (config.configured || []).find(domain => matches(host, domain));
    updateSiteAction(host, !!routed, !!blocked, !!configured, config.protectionEnabled && !paused);
    applyPauseUI(config.protectionEnabled, paused, config.pausedUntil);
  } catch (_) {
    await resolveLanguage(null);
    connection.className = "pill offline";
    connection.querySelector("span").textContent = T("conn_offline");
    hero.className = "hero disabled";
    hero.querySelector(".shield").textContent = "!";
    title.textContent = T("hero_offline_title");
    description.textContent = T("hero_offline_desc");
    protectedCount.textContent = "-";
    blockedCount.textContent = "-";
    currentState.className = "mini neutral";
    currentState.textContent = T("state_unprotected");
    siteAction.hidden = true;
    unprotectSite.hidden = true;
    pauseControls.hidden = true;
    pausedBanner.hidden = true;
  }
}

// Sekcja pauzy: gdy wstrzymano → baner „Wstrzymano do HH:MM" + „Wznów".
// Gdy ochrona włączona i nie wstrzymana → przyciski wstrzymania. W innym wypadku ukryte.
function applyPauseUI(protectionEnabled, paused, pausedUntilEpoch) {
  if (paused) {
    const time = new Date(pausedUntilEpoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    const indefinite = pausedUntilEpoch * 1000 > Date.now() + 2 * 24 * 60 * 60 * 1000;
    pausedText.textContent = indefinite ? T("paused_manual") : `${T("paused_prefix")} ${time}`;
    pausedBanner.hidden = false;
    pauseControls.hidden = true;
  } else {
    pausedBanner.hidden = true;
    pauseControls.hidden = !protectionEnabled;
  }
}

// Jeden przycisk kontekstowy dla bieżącej strony:
//  - chroniona i odblokowana → „Zablokuj teraz",
//  - niechroniona strona WWW → „Chroń tę stronę",
//  - już zablokowana / brak strony → ukryty.
function updateSiteAction(host, routed, blocked, configured, protectionEnabled) {
  unprotectSite.hidden = !configured;
  unprotectSite.dataset.domain = configured ? host : "";
  const isWeb = /\./.test(host) && !host.startsWith("127.");
  if (!isWeb || blocked) { siteAction.hidden = true; return; }
  if (routed) {
    siteAction.hidden = false;
    siteAction.textContent = T("btn_lock_now");
    siteAction.dataset.action = "relock";
  } else if (protectionEnabled) {
    siteAction.hidden = false;
    siteAction.textContent = T("btn_protect_site");
    siteAction.dataset.action = "protect";
  } else {
    siteAction.hidden = true;
    return;
  }
  siteAction.dataset.domain = host;
}

async function runSiteAction() {
  const action = siteAction.dataset.action;
  const domain = siteAction.dataset.domain;
  if (!action || !domain) return;
  try {
    const response = await fetch(`${API}/privio/${action}?domain=${encodeURIComponent(domain)}`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    if (action === "protect" || action === "relock") {
      // Serwis Privio zapisuje stan asynchronicznie. Czekamy, aż service worker
      // rzeczywiście zainstaluje regułę DNR, a następnie przeładowujemy kartę.
      // To jest konieczne również dla „Zablokuj teraz”: już wyrenderowana
      // aplikacja SPA (np. Gmail) nie wykonuje nowej nawigacji main_frame sama.
      for (let attempt = 0; attempt < 12; attempt += 1) {
        await new Promise(resolve => setTimeout(resolve, 100));
        const result = await chrome.runtime.sendMessage({ type: "syncNow" });
        const expected = action === "relock"
          ? (result?.config?.blocked || [])
          : (result?.config?.configured || result?.config?.routed || []);
        if (expected.some(item => matches(domain, item) || matches(item, domain))) break;
      }
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tab?.id) await chrome.tabs.reload(tab.id);
    }
    showToast(T(action === "relock" ? "toast_locked" : "toast_protected"), false);
    setTimeout(refresh, 400);
  } catch (_) {
    showToast(T("toast_action_failed"), true);
  }
}

async function openPrivioSettings() {
  try {
    const response = await fetch(`${API}/privio/open-settings`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    showToast(T("toast_opening"), false);
  } catch (_) {
    showToast(T("toast_open_failed"), true);
  }
}

siteAction.addEventListener("click", runSiteAction);
unprotectSite.addEventListener("click", async () => {
  const domain = unprotectSite.dataset.domain;
  if (!domain) return;
  try {
    const response = await fetch(`${API}/privio/request-unprotect?domain=${encodeURIComponent(domain)}`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    showToast(T("toast_unprotect_requested"), false);
    // Uwierzytelnienie odbywa się w aplikacji Privio i kończy asynchronicznie.
    // Dopóki popup jest otwarty, czekamy na faktyczne usunięcie domeny, a nie
    // pozostawiamy nieaktualnego przycisku „Przestań chronić”.
    for (let attempt = 0; attempt < 120; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 250));
      const result = await chrome.runtime.sendMessage({ type: "syncNow" });
      const configured = result?.config?.configured || result?.config?.routed || [];
      if (!configured.some(item => matches(domain, item) || matches(item, domain))) {
        await refresh();
        return;
      }
    }
    await refresh();
  } catch (_) {
    showToast(T("toast_action_failed"), true);
  }
});
pauseControls.addEventListener("click", async event => {
  const button = event.target.closest("button[data-min]");
  if (!button) return;
  try {
    const response = await fetch(`${API}/privio/request-pause?minutes=${encodeURIComponent(button.dataset.min)}`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    showToast(T(button.dataset.min === "0" ? "toast_disable_requested" : "toast_pause_requested"), false);
  } catch (_) {
    showToast(T("toast_action_failed"), true);
  }
});
document.querySelector("#resume").addEventListener("click", async () => {
  try {
    const response = await fetch(`${API}/privio/resume`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    showToast(T("toast_resumed"), false);
    setTimeout(refresh, 300);
  } catch (_) {
    showToast(T("toast_action_failed"), true);
  }
});
document.querySelector("#openPrivio").addEventListener("click", openPrivioSettings);
document.querySelector("#settings").addEventListener("click", () => chrome.runtime.openOptionsPage());
document.querySelector("#refresh").addEventListener("click", refresh);

(async () => {
  await resolveLanguage(null);
  refresh();
})();

// Popup może pozostać otwarty podczas systemowego Touch ID/hasła. Krótkie
// odświeżanie utrzymuje przyciski i liczniki w zgodzie ze stanem aplikacji.
setInterval(refresh, 1500);
