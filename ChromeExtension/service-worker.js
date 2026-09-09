importScripts("i18n.js", "env.js");
const API = "http://127.0.0.1:8987";
let routed = [];
let swLang = "en";

async function resolveSwLang(appLanguage) {
  const pref = await PrivioI18n.storedPref();
  swLang = PrivioI18n.resolve(pref, appLanguage);
  return swLang;
}
const pendingTargets = new Map();
const tabDomains = new Map();
let activeDomain = null;
let focusedWindowId = chrome.windows.WINDOW_ID_NONE;

const matchesDomain = (host, domain) => host === domain || host.endsWith(`.${domain}`);
const escapeRegex = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function routedDomainForUrl(value) {
  try {
    const host = new URL(value).hostname;
    return routed.find(domain => matchesDomain(host, domain)) || null;
  } catch (_) {
    return null;
  }
}

async function lockIfNoOpenTab(domain) {
  await new Promise(resolve => setTimeout(resolve, 200));
  const tabs = await chrome.tabs.query({});
  if (tabs.some(tab => {
    try { return matchesDomain(new URL(tab.url || "").hostname, domain); }
    catch (_) { return false; }
  })) return;
  try {
    await fetch(`${API}/privio/lock?domain=${encodeURIComponent(domain)}`, { cache: "no-store" });
    await syncRules();
  } catch (error) {
    console.debug("Privio lock unavailable", error);
  }
}

async function rememberTabDomain(tabId, domain) {
  if (!domain) return;
  tabDomains.set(tabId, domain);
  const stored = await chrome.storage.session.get("privioTabDomains");
  const domains = stored.privioTabDomains || {};
  domains[String(tabId)] = domain;
  await chrome.storage.session.set({ privioTabDomains: domains });
}

async function forgetTabDomain(tabId) {
  const stored = await chrome.storage.session.get("privioTabDomains");
  const domains = stored.privioTabDomains || {};
  const previous = tabDomains.get(tabId) || domains[String(tabId)] || null;
  tabDomains.delete(tabId);
  delete domains[String(tabId)];
  await chrome.storage.session.set({ privioTabDomains: domains });
  return previous;
}

async function rememberPendingTarget(tabId, target) {
  pendingTargets.set(tabId, target);
  const stored = await chrome.storage.session.get("privioPendingTargets");
  const targets = stored.privioPendingTargets || {};
  targets[String(tabId)] = target;
  await chrome.storage.session.set({ privioPendingTargets: targets });
}

async function pendingTargetForTab(tabId) {
  if (pendingTargets.has(tabId)) return pendingTargets.get(tabId);
  const stored = await chrome.storage.session.get("privioPendingTargets");
  return stored.privioPendingTargets?.[String(tabId)] || null;
}

async function forgetPendingTarget(tabId) {
  pendingTargets.delete(tabId);
  const stored = await chrome.storage.session.get("privioPendingTargets");
  const targets = stored.privioPendingTargets || {};
  delete targets[String(tabId)];
  await chrome.storage.session.set({ privioPendingTargets: targets });
}

async function sendActivity(domain, isActive) {
  if (!domain) return;
  try {
    await fetch(`${API}/privio/activity?domain=${encodeURIComponent(domain)}&active=${isActive ? "1" : "0"}`, {
      cache: "no-store"
    });
  } catch (error) {
    console.debug("Privio activity unavailable", error);
  }
}

async function refreshActiveDomain() {
  if (activeDomain === null) {
    const stored = await chrome.storage.session.get("privioActiveDomain");
    activeDomain = stored.privioActiveDomain || null;
  }
  let next = null;
  if (focusedWindowId !== chrome.windows.WINDOW_ID_NONE) {
    const tabs = await chrome.tabs.query({ active: true, windowId: focusedWindowId });
    next = routedDomainForUrl(tabs[0]?.url || "");
  }
  if (next !== activeDomain) {
    const previous = activeDomain;
    activeDomain = next;
    if (previous) await sendActivity(previous, false);
    if (next) await chrome.storage.session.set({ privioActiveDomain: next });
    else await chrome.storage.session.remove("privioActiveDomain");
  }
  if (activeDomain) await sendActivity(activeDomain, true);
}

async function hydrateFocusedWindow() {
  const windows = await chrome.windows.getAll();
  focusedWindowId = windows.find(window => window.focused)?.id ?? chrome.windows.WINDOW_ID_NONE;
  await refreshActiveDomain();
}

async function hydrateTabDomains() {
  const tabs = await chrome.tabs.query({});
  const stored = await chrome.storage.session.get(["privioTabDomains", "privioPendingTargets"]);
  const previousDomains = stored.privioTabDomains || {};
  const previousTargets = stored.privioPendingTargets || {};
  const domains = {};
  const targets = {};
  for (const tab of tabs) {
    const domain = routedDomainForUrl(tab.url || "");
    if (domain) {
      tabDomains.set(tab.id, domain);
      domains[String(tab.id)] = domain;
    } else if (tab.url?.startsWith(chrome.runtime.getURL("unlock.html")) &&
               previousDomains[String(tab.id)]) {
      tabDomains.set(tab.id, previousDomains[String(tab.id)]);
      domains[String(tab.id)] = previousDomains[String(tab.id)];
    }
    if (previousTargets[String(tab.id)]) {
      pendingTargets.set(tab.id, previousTargets[String(tab.id)]);
      targets[String(tab.id)] = previousTargets[String(tab.id)];
    }
  }
  await chrome.storage.session.set({
    privioTabDomains: domains,
    privioPendingTargets: targets
  });
}

async function loadConfig() {
  const version = chrome.runtime.getManifest().version;
  const response = await fetch(`${API}/privio/config?browser=${encodeURIComponent(PrivioEnv.browser())}&version=${encodeURIComponent(version)}`, { cache: "no-store" });
  if (!response.ok) throw new Error(`Privio API: ${response.status}`);
  return response.json();
}

async function setToolbarStatus(active) {
  const suffix = active ? "active" : "inactive";
  await chrome.action.setBadgeText({ text: "" });
  await chrome.action.setIcon({
    path: {
      16: `icons/icon16-${suffix}.png`,
      32: `icons/icon32-${suffix}.png`
    }
  });
}

async function syncRules() {
  try {
    const config = await loadConfig();
    routed = config.routed || [];
    const existing = await chrome.declarativeNetRequest.getDynamicRules();
    const addRules = (config.blocked || []).map((domain, index) => ({
      id: 1000 + index,
      priority: 1,
      action: { type: "redirect", redirect: { extensionPath: "/unlock.html" } },
      condition: {
        // Chrome DNR używa RE2, który nie obsługuje grup non-capturing `(?:…)`.
        // Zwykłe grupy zapewniają ten sam matching domeny, portu i ścieżki.
        regexFilter: `^https?://([^/]+\\.)?${escapeRegex(domain)}(:[0-9]+)?(/|$)`,
        resourceTypes: ["main_frame"]
      }
    }));
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: existing.map(rule => rule.id),
      addRules
    });
    await chrome.storage.local.set({ privioConfig: config });
    await resolveSwLang(config.language);
    const paused = !!config.pausedUntil && config.pausedUntil * 1000 > Date.now();
    const protectionWorks = config.protectionEnabled && !paused;
    await setToolbarStatus(protectionWorks);
    await chrome.action.setTitle({ title: PrivioI18n.t(swLang, protectionWorks ? "badge_on" : "badge_off") });
    return config;
  } catch (error) {
    await resolveSwLang(null);
    await setToolbarStatus(false);
    await chrome.action.setTitle({ title: PrivioI18n.t(swLang, "badge_offline") });
    console.debug("Privio sync unavailable", error);
    return null;
  }
}

chrome.webNavigation.onBeforeNavigate.addListener(details => {
  if (details.frameId !== 0) return;
  try {
    const url = new URL(details.url);
    if (routed.some(domain => matchesDomain(url.hostname, domain))) {
      rememberPendingTarget(details.tabId, details.url);
      rememberTabDomain(details.tabId, routedDomainForUrl(details.url));
    }
  } catch (_) {}
});

chrome.webNavigation.onCommitted.addListener(details => {
  if (details.frameId !== 0) return;
  const previous = tabDomains.get(details.tabId) || null;
  const current = routedDomainForUrl(details.url);
  if (current) {
    rememberTabDomain(details.tabId, current);
    forgetPendingTarget(details.tabId);
  } else if (!details.url.startsWith(chrome.runtime.getURL("unlock.html"))) {
    forgetPendingTarget(details.tabId);
    forgetTabDomain(details.tabId).then(storedPrevious => {
      const domain = previous || storedPrevious;
      if (domain) lockIfNoOpenTab(domain);
    });
  }
  refreshActiveDomain();
});

chrome.tabs.onRemoved.addListener(tabId => {
  forgetPendingTarget(tabId);
  forgetTabDomain(tabId).then(previous => {
    if (previous) lockIfNoOpenTab(previous);
  });
});

chrome.tabs.onActivated.addListener(() => refreshActiveDomain());
chrome.windows.onFocusChanged.addListener(windowId => {
  focusedWindowId = windowId;
  refreshActiveDomain();
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "getPendingTarget") {
    pendingTargetForTab(sender.tab?.id).then(target => sendResponse({ target }));
    return true;
  }
  if (message.type === "syncNow") {
    syncRules().then(config => sendResponse({ config }));
    return true;
  }
  if (message.type === "shouldBlock") {
    (async () => {
      let target;
      try { target = new URL(message.url); }
      catch (_) { sendResponse({ blocked: false }); return; }
      const config = await syncRules();
      const domain = (config?.blocked || []).find(item => matchesDomain(target.hostname, item));
      if (!domain) { sendResponse({ blocked: false }); return; }
      if (sender.tab?.id != null) {
        await rememberPendingTarget(sender.tab.id, target.href);
        await rememberTabDomain(sender.tab.id, domain);
      }
      sendResponse({ blocked: true, unlockURL: chrome.runtime.getURL("unlock.html") });
    })();
    return true;
  }
});

chrome.alarms.create("privioSync", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "privioSync") {
    syncRules().then(async config => {
      if (!config) return;
      await refreshActiveDomain();
    });
  }
});
chrome.runtime.onInstalled.addListener(syncRules);
chrome.runtime.onStartup.addListener(syncRules);
syncRules().then(async () => {
  await hydrateTabDomains();
  await hydrateFocusedWindow();
});
setInterval(async () => {
  await syncRules();
  await refreshActiveDomain();
}, 2000);
