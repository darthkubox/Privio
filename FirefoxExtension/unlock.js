const API = "http://127.0.0.1:8987";
const domainLabel = document.querySelector("#domain");
const statusLabel = document.querySelector("#status");
const retryButton = document.querySelector("#retry");
document.querySelector("#back").addEventListener("click", () => history.back());
let target = null;
let domain = null;
let lang = "en";
const T = key => PrivioI18n.t(lang, key);

const isBlocked = config => (config.blocked || []).some(item => domain === item || domain.endsWith(`.${item}`));
async function config() {
  const response = await fetch(`${API}/privio/config`, { cache: "no-store" });
  return response.json();
}

async function resolveLanguage(appLanguage) {
  const pref = await PrivioI18n.storedPref();
  lang = PrivioI18n.resolve(pref, appLanguage);
  PrivioI18n.apply(document, lang);
}

async function authenticate() {
  retryButton.hidden = true;
  statusLabel.textContent = T("unlock_confirm");
  try {
    await fetch(`${API}/privio/request-unlock?domain=${encodeURIComponent(domain)}`, { cache: "no-store" });
    const started = Date.now();
    while (Date.now() - started < 8000) {
      await new Promise(resolve => setTimeout(resolve, 250));
      const current = await config();
      if (!isBlocked(current)) {
        statusLabel.textContent = T("unlock_success");
        await chrome.runtime.sendMessage({ type: "syncNow" });
        location.replace(target);
        return;
      }
    }
    statusLabel.textContent = T("unlock_cancelled");
    retryButton.hidden = false;
  } catch (_) {
    statusLabel.textContent = T("unlock_offline");
    retryButton.hidden = false;
  }
}

retryButton.addEventListener("click", authenticate);
(async () => {
  // Ustal język najpierw (z konfiguracji aplikacji, jeśli dostępna).
  try { await resolveLanguage((await config()).language); } catch (_) { await resolveLanguage(null); }
  chrome.runtime.sendMessage({ type: "getPendingTarget" }, response => {
    target = response?.target;
    if (!target) {
      statusLabel.textContent = T("unlock_no_target");
      return;
    }
    domain = new URL(target).hostname;
    domainLabel.textContent = domain;
    authenticate();
  });
})();
