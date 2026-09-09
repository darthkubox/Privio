const API = "http://127.0.0.1:8987";
const manifest = chrome.runtime.getManifest();
const connection = document.querySelector("#connection");
const appState = document.querySelector("#appState");
const protectionState = document.querySelector("#protectionState");
const appVersion = document.querySelector("#appVersion");
const extVersion = document.querySelector("#extVersion");
const lastSync = document.querySelector("#lastSync");
const protectedDomains = document.querySelector("#protectedDomains");
const blockedDomains = document.querySelector("#blockedDomains");
const domainsEmpty = document.querySelector("#domainsEmpty");
const langGroup = document.querySelector("#langGroup");
const toast = document.querySelector("#toast");
extVersion.textContent = `v${manifest.version}`;

let lang = "en";
let pref = "auto";
const T = key => PrivioI18n.t(lang, key);

function applyLanguage(appLanguage) {
  const next = PrivioI18n.resolve(pref, appLanguage);
  lang = next;
  PrivioI18n.apply(document, lang);
  langGroup.querySelectorAll("button").forEach(btn => {
    btn.classList.toggle("selected", btn.dataset.lang === pref);
  });
}

function showToast(message, isError) {
  toast.textContent = message;
  toast.classList.toggle("error", !!isError);
  toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { toast.hidden = true; }, 2600);
}

function renderChips(container, domains, locked) {
  container.innerHTML = "";
  for (const domain of domains) {
    const chip = document.createElement("span");
    chip.className = locked ? "chip locked" : "chip";
    chip.textContent = domain;
    container.appendChild(chip);
  }
}

function relativeSync(lastSeenEpoch) {
  if (!lastSeenEpoch) return T("never");
  const seconds = Math.max(0, Math.round(Date.now() / 1000 - lastSeenEpoch));
  if (seconds < 5) return T("just_now");
  return `${seconds}${T("seconds_ago")}`;
}

async function refresh() {
  try {
    const [configRes, extRes] = await Promise.all([
      fetch(`${API}/privio/config?browser=${encodeURIComponent(PrivioEnv.browser())}&version=${encodeURIComponent(manifest.version)}`, { cache: "no-store" }),
      fetch(`${API}/privio/extensions`, { cache: "no-store" })
    ]);
    if (!configRes.ok) throw new Error(String(configRes.status));
    const config = await configRes.json();
    const ext = extRes.ok ? await extRes.json() : { extensions: [] };
    applyLanguage(config.language);

    connection.className = "pill connected";
    connection.querySelector("span").textContent = T("conn_connected");
    appState.textContent = T("conn_connected");
    appState.className = "on";
    protectionState.textContent = T(config.protectionEnabled ? "on" : "off");
    protectionState.className = config.protectionEnabled ? "on" : "off";
    appVersion.textContent = config.appVersion ? `v${config.appVersion}` : "-";

    const ownEntry = (ext.extensions || []).find(e => e.browser === PrivioEnv.browser());
    lastSync.textContent = relativeSync(ownEntry?.lastSeen);

    const configured = config.configured || config.routed || [];
    const blocked = config.blocked || [];
    renderChips(protectedDomains, configured, false);
    renderChips(blockedDomains, blocked, true);
    domainsEmpty.hidden = configured.length > 0 || blocked.length > 0;
  } catch (_) {
    applyLanguage(null);
    connection.className = "pill offline";
    connection.querySelector("span").textContent = T("conn_offline");
    appState.textContent = T("conn_offline");
    appState.className = "off";
    protectionState.textContent = "-";
    protectionState.className = "";
    appVersion.textContent = "-";
    lastSync.textContent = T("never");
    renderChips(protectedDomains, [], false);
    renderChips(blockedDomains, [], true);
    domainsEmpty.hidden = false;
  }
}

langGroup.addEventListener("click", async event => {
  const button = event.target.closest("button[data-lang]");
  if (!button) return;
  pref = button.dataset.lang;
  try { await chrome.storage.local.set({ privioLang: pref }); } catch (_) {}
  applyLanguage(null);
  showToast(T("saved"), false);
  refresh();
});

document.querySelector("#openPrivio").addEventListener("click", async () => {
  try {
    const response = await fetch(`${API}/privio/open-settings`, { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    showToast(T("toast_opening"), false);
  } catch (_) {
    showToast(T("toast_open_failed"), true);
  }
});

(async () => {
  pref = await PrivioI18n.storedPref();
  applyLanguage(null);
  refresh();
  setInterval(refresh, 2000);
})();
