<div align="center">

# Privio

**Privacy. Locked by you.**
Touch ID for the apps that matter.

</div>

Privio is a native macOS app‑locker (Swift + SwiftUI/AppKit). It protects selected applications
with **Touch ID**: when a protected app becomes active, Privio hides it immediately, asks for
authentication, and only restores it after you unlock. It also locks apps after inactivity, after
screen lock / sleep, and can auto‑quit apps after a period of inactivity.

- Lock any installed app with **Touch ID, Touch ID with password fallback, or Mac password only**
- **Hide on activation** - the protected app is hidden the moment it comes forward
- **Inactivity** locking and optional **auto‑quit**
- Lock after **screen lock / sleep / user switch**
- Lives in the **menu bar** (accessory app); Dock icon only while Settings are open
- Disabling protection or quitting Privio requires authentication
- Optional failed-authentication photos: off by default, local-only, newest 20 retained
- **Privacy Curtain** with spotlight, privacy-filter and blur modes
- **Private Vault**: local APFS/AES‑256 storage for files and encrypted notes, unlocked with macOS
  authentication; a movable Finder/Dock shortcut and recovery key are included
- **No cloud, no telemetry, no accounts** - everything stays local

> Requires macOS 14+. Apple Silicon. Built for a Mac with Touch ID.

## Build & run

The Xcode project is **generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)**
(the `.xcodeproj` is not committed). Signing is ad‑hoc by default.

```bash
brew install xcodegen          # once
xcodegen generate              # regenerate Privio.xcodeproj from project.yml
xcodebuild -project Privio.xcodeproj -scheme Privio -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/Privio-*/Build/Products/Debug/Privio.app
```

Run the unit tests:

```bash
xcodebuild -project Privio.xcodeproj -scheme PrivioCoreTests -destination 'platform=macOS' test
```

For a small, informed test group before Developer ID is available, see
[Docs/BETA_TESTING.md](Docs/BETA_TESTING.md). Stable releases use the signed and notarized process in
[Docs/RELEASE.md](Docs/RELEASE.md).

## Install & updates

**Install.** Privio ships as a macOS installer package. Open `Privio-<version>.pkg`, accept the EULA
(Polish/English), and authorize with your administrator password. It installs into `/Applications`
with system ownership, so removing it also requires an administrator. Requires macOS 14+. Prebuilt
packages are attached to [GitHub Releases](../../releases) (currently private, unsigned dev builds -
a public build needs Developer ID signing and notarization). To build one yourself:

```bash
Scripts/build_admin_installer.sh                                    # unsigned .pkg → .build/admin-installer/
PRIVIO_VERSION=0.2.0 PRIVIO_BUILD=2 Scripts/build_admin_installer.sh  # bump for each build
```

**In-app updates.** Privio uses [Sparkle 2](https://sparkle-project.org). Choose **Check for
Updates…** in Settings or the menu bar. Automatic checks and system profiling are off by default;
package updates always require your approval and administrator authorization. Every update is verified
with an EdDSA signature before it installs - the app embeds only the public key (`SUPublicEDKey`), and
the private signing key stays in the developer's login Keychain (never committed).

**Testing updates locally.** Debug builds read the appcast from `http://127.0.0.1:8080/appcast.xml`;
Release builds read the GitHub HTTPS feed. To publish a newer local build and exercise the update
button end-to-end:

```bash
Scripts/prepare_local_update.sh 0.1.1 2     # build + sign a newer .pkg, stage the local appcast
Scripts/serve_local_updates.sh              # serve it on 127.0.0.1:8080
```

You can also just double-click **`Start Privio Update Server.command`** (it stages an update if none
exists yet, then serves it). Keep the server running, launch an installed older build, and choose
**Check for Updates…**. The full signed-and-notarized release process is in
[Docs/RELEASE.md](Docs/RELEASE.md); for a small pre-Developer ID test group see
[Docs/BETA_TESTING.md](Docs/BETA_TESTING.md).

## Architecture

Two targets:

- **PrivioCore** - a framework with all domain logic, persistence, security and enforcement.
  UI‑agnostic and unit‑tested.
- **Privio** - the SwiftUI/AppKit app; UI plus dependency wiring in `PrivioApp.init`.

UI and enforcement are separated by a single seam - the `EnforcementControlling` protocol - with
`Codable`/`Sendable` messages, so the in‑process enforcement engine (`InProcessEnforcementService`,
an `actor`) can later be moved into a separate agent process over XPC without rewriting the core.
Collaborators are injected behind protocols (`AppActivationMonitoring`, `SystemEventMonitoring`,
`RunningAppController`, `BiometricAuthenticating`, `InactivityScheduling`), which keeps the logic
testable with fakes. Authentication uses Apple's `LocalAuthentication` plus a Secure Enclave key.
Password-only mode uses the native macOS password flow; Privio never stores a custom password.

## Security model & honest limitations

Privio protects private apps when someone briefly has access to your already‑unlocked Mac. It is
**not** meant to defend against root/admin/kernel‑level attackers.

- macOS has **no public API to intercept an app launch**, so Privio can only *react* (hide on
  activation). A brief content flash before hiding is possible and is minimized, not eliminated.
- A `kill` from Terminal on an unlocked Mac cannot be prevented.
- Privio is intentionally **not sandboxed** (distributed outside the Mac App Store) so it can hide
  and quit other apps. It uses only public Apple APIs - no private APIs, no Accessibility or Screen
  Recording permissions.
- Camera access is requested only if the user explicitly enables failed-attempt photos. Photos are
  stored locally, are never uploaded, and can be deleted from Settings.
- Private Vault data are encrypted at rest. While its APFS image is mounted, files behave like files
  on a normal disk and are readable by the current account; lock the vault after use. Losing both the
  Keychain entry and recovery key makes the vault unrecoverable.

## License & terms

Privio is **source‑available** (not OSI open source): the source is public for audit, but
redistribution is restricted and Pro features require a valid license. The legal documents below apply
jointly and are complete drafts prepared for professional legal review (Polish is the binding
language; English translations are supplied for convenience):

- [LICENSE.md](LICENSE.md) / [LICENSE.en.md](LICENSE.en.md) - the **source‑code** license.
- [EULA.md](EULA.md) / [EULA.en.md](EULA.en.md) - the **End‑User License Agreement** governing use of the
  official build (editions, Pro, purchase & EU withdrawal, privacy, protection limits, warranty, liability).
- [PRIVACY.md](PRIVACY.md) / [PRIVACY.en.md](PRIVACY.en.md) - the **Privacy Policy** (local‑first;
  camera, vault, updates and purchase).
- [SALES.md](SALES.md) / [SALES.en.md](SALES.en.md) - **sales terms** for Privio Pro (a Merchant of
  Record may act as seller).
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) - licenses of bundled third‑party code (Sparkle).

The honest protection scope and its limits are described in [Docs/Security-Model.md](Docs/Security-Model.md).

## Status

Public beta preparation. The core is functional: UI, app selection and persistence, activation
monitoring, Touch ID / Secure Enclave, inactivity and auto‑quit, screen‑lock/sleep locking,
login‑item autostart, menu‑bar controls, local activity persistence and offline Pro license
verification, plus the encrypted Private Vault and private notes. Legal documents are rendered as structured, selectable Markdown with document tabs and
a language dropdown. Automated builds and unit tests run in CI.

The current release still uses single‑process enforcement. A separate background agent/XPC service,
Developer ID signing, notarization and final legal review remain required before a stable public
release. See [Docs/SECURITY_TEST_MATRIX.md](Docs/SECURITY_TEST_MATRIX.md) for the verified scope and
known limitations.
