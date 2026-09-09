# Privio Website Protection (Chromium browsers)

The extension redirects only blocked top-level navigations to Privio. Browser
suggestions, preconnects, ads, background requests and subresources cannot
trigger authentication.

The same unpacked extension runs in **Chrome, Edge, Brave, Opera and Vivaldi**.
It reports its host browser (via `env.js`, from the User-Agent) so Privio's status
card shows the right one. Firefox needs a separate build (no MV3 `service_worker`)
and is not covered yet.

## Features

- **Popup** - connection status, whether protection is on, configured/blocked
  counts, current-tab state, and a one-click **Open settings in Privio** button.
- **Settings page** (`options.html`) - language selector, live connection and
  protection status, the list of protected/blocked domains, app + extension
  versions, last sync, and **Open Privio on your Mac**.
- **Languages** - Polish and English, shared via `i18n.js`. Default *Automatic*
  follows the Privio app language (from `/privio/config`), falling back to the
  browser language. The choice is stored per browser in `chrome.storage.local`.
- **Toolbar status dot** - a small dot drawn directly on the Privio icon: green
  while protection is working, red when it is disabled, paused, or unavailable.

## Local installation

1. Open your browser's extensions page (`chrome://extensions`,
   `edge://extensions`, `brave://extensions`, …).
2. Enable **Developer mode**.
3. Choose **Load unpacked**.
4. Select this `ChromeExtension` directory.

Privio must be running with Website Protection enabled. Communication stays on
`http://127.0.0.1:8987`.

The **Open Privio** buttons call `GET /privio/open-settings`; the Mac app then
brings its window to front (behind its own Touch ID gate) on the *Protected
Websites* screen. This never unlocks a site - it only opens the app.
