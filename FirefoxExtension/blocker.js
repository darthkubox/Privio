// Niezależna warstwa egzekwowania blokady. DNR pozostaje pierwszą linią obrony,
// ale nie wszystkie wydania Chromium niezawodnie stosują dynamiczne przekierowanie
// rozszerzenia unpacked. Kontrola na document_start zatrzymuje także aplikacje SPA.
(async () => {
  if (window.top !== window) return;
  try {
    const response = await chrome.runtime.sendMessage({
      type: "shouldBlock",
      url: location.href
    });
    if (response?.blocked && response.unlockURL) location.replace(response.unlockURL);
  } catch (_) {
    // Przy niedostępnym service workerze trwałe reguły DNR nadal pozostają aktywne.
  }
})();
