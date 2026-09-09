// Zgodność Chrome↔Firefox. Skopiowane z wersji Chromium pliki (popup/unlock/options/
// blocker/i18n) używają `chrome.*`. W Firefoksie API oparte na promisach to `browser.*`
// (firefoksowe `chrome.*` bywa callbackowe), więc kierujemy `chrome` na `browser`, żeby
// `await chrome.tabs.query(...)` itp. działało bez modyfikowania współdzielonych plików.
// W Chrome `browser` nie istnieje, więc nic nie zmieniamy.
if (typeof browser !== "undefined") {
  try { self.chrome = browser; } catch (_) {}
}
