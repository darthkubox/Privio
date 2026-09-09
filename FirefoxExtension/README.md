# Privio – wtyczka Firefox (ochrona stron)

Pełna para z wtyczką Chromium, ale zbudowana firefoksowymi API (Firefox nie honoruje
systemowego proxy/PAC, którym Privio obejmuje Chrome, i ma tylko ograniczone DNR).

## Co robi (tak jak w Chrome)

- **Blokuje** chronioną stronę: nawigacja główna do zablokowanej domeny jest
  przekierowywana na ekran **`unlock.html`** („Strona chroniona przez Privio"), który
  uruchamia Touch ID i po odblokowaniu wraca na stronę (`webRequest.onBeforeRequest`,
  odpowiednik DNR-redirect z Chrome). Działa też natychmiastowa **ponowna blokada** po
  zablokowaniu w Privio.
- **Popup** po kliknięciu ikony: status połączenia i ochrony, liczniki chronione/
  zablokowane, bieżąca strona, „Zablokuj teraz / Chroń tę stronę / Przestań chronić",
  wstrzymanie ochrony, „Otwórz ustawienia w Privio" (identyczny UI jak w Chrome).
- **Strona opcji** (język PL/EN/Auto, status, lista domen).
- **Druga warstwa**: `proxy.onRequest` kieruje chronione domeny do lokalnego proxy
  Privio (127.0.0.1:8987) – łapie podzasoby i ruch inny niż główna nawigacja.
- **Auto-lock**: zamknięcie ostatniej karty domeny blokuje ją z powrotem.
- **Heartbeat**: co ~2 s odpytuje `/privio/config`, więc Firefox pojawia się w panelu
  „Browser extension" w Privio. Wtyczka nie zna sekretów i nic nie decyduje sama.

## Instalacja (wersja tymczasowa, do testów)

Wtyczka nie jest jeszcze podpisana → w zwykłym Firefoksie ładuje się jako **tymczasowy
dodatek** (znika po restarcie przeglądarki):

1. `about:debugging#/runtime/this-firefox` (wpisz ręcznie w pasku adresu).
2. **Load Temporary Add-on…** → wskaż `FirefoxExtension/manifest.json`.
3. Wejdź na chronioną stronę – zobaczysz ekran blokady Privio i Touch ID.

Trwała instalacja wymaga podpisania na [addons.mozilla.org](https://addons.mozilla.org)
albo Firefox Developer Edition/ESR z `xpinstall.signatures.required=false`.

## Pliki

- `background.js` – trasowanie, blokada `webRequest`, auto-lock, synchronizacja.
- `compat.js` – kieruje `chrome.*` na promisowe `browser.*` (współdzielone pliki z Chrome
  używają `chrome.*`).
- `popup.*`, `options.*`, `unlock.*`, `blocker.js`, `i18n.js` – skopiowane z wersji
  Chromium (działają w Firefoksie dzięki `compat.js`).
- `env.js` – raportuje „Firefox" do panelu Privio.
