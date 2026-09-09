import SwiftUI
import AppKit
import PrivioCore

/// Ten sam wzorzec co „Protected Apps”: lista po lewej, ustawienia po prawej.
struct ProtectedWebsitesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var showingAddSheet = false
    @State private var showingExtensionSetup = false
    @State private var extensionStatuses: [BrowserExtensionStatus] = []

    private var filteredTargets: [WebTargetSnapshot] {
        searchText.isEmpty ? model.webTargets : model.webTargets.filter {
            $0.target.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.target.domain.localizedCaseInsensitiveContains(searchText)
        }
    }
    private var selectedSnapshot: WebTargetSnapshot? { model.webTargets.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.privioSeparator)
            HStack(spacing: 0) {
                listColumn.frame(minWidth: 320, maxWidth: 420)
                Divider().overlay(Color.privioSeparator)
                detailColumn.frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWebsiteSheet().environment(model)
        }
        .sheet(isPresented: $showingExtensionSetup) {
            BrowserExtensionSetupSheet(statuses: extensionStatuses)
                .environment(model)
        }
        .onAppear { selectFirstIfNeeded(); loadKnownExtensions() }
        .onChange(of: model.webTargets.map(\.id)) { _, _ in selectFirstIfNeeded() }
        .task { await monitorExtensions() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Protected Websites").font(.privioSystem(size: 24, weight: .bold)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            HStack(spacing: 7) {
                Text("Website protection").font(.privioSystem(size: 12.5, weight: .medium)).foregroundStyle(Color.privioTextSecondary)
                Toggle("", isOn: Binding(get: { model.websiteBlockingEnabled }, set: { model.setWebsiteBlockingEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.privioPrimary).disabled(!model.isPro)
            }
            Button { showingAddSheet = true } label: {
                HStack(spacing: 6) { FAIcon("plus"); Text("Add Website") }
                    .font(.privioSystem(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PrivioGradient.brand))
            }
            .buttonStyle(.plain).disabled(!model.isPro).opacity(model.isPro ? 1 : 0.45)
        }
        .padding(.horizontal, PrivioLayout.pagePadding)
        .padding(.top, PrivioLayout.headerTop)
        .padding(.bottom, PrivioLayout.headerBottom)
    }

    private var listColumn: some View {
        VStack(spacing: 12) {
            extensionCard
            SearchField(text: $searchText, placeholder: "Search websites…")
                .padding(.horizontal, PrivioLayout.pagePadding)
            if !model.isPro { proUpsell }
            else if filteredTargets.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: PrivioLayout.rowSpacing) {
                        ForEach(filteredTargets) { snapshot in
                            ProtectedWebsiteRow(snapshot: snapshot, status: effectiveStatus(snapshot),
                                isSelected: selectedID == snapshot.id,
                                onSelect: { selectedID = snapshot.id },
                                onToggleProtection: { model.setWebProtectionEnabled($0, for: snapshot.target) })
                        }
                    }
                    .padding(.horizontal, PrivioLayout.pagePadding)
                    .padding(.bottom, PrivioLayout.pagePadding)
                }
            }
        }
    }

    private var extensionCard: some View {
        // Ta sama wtyczka MV3 działa w Chrome/Edge/Brave/Opera/Vivaldi - bierzemy
        // pierwszą AKTYWNĄ przeglądarkę (a jak żadna, to ostatnio widzianą).
        let detected = extensionStatuses.first { $0.active }
            ?? extensionStatuses.max(by: { $0.lastSeen < $1.lastSeen })
        let connected = detected?.active == true
        let protectionWorks = connected && model.websiteBlockingEnabled && model.state.protectionActive
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                FAIcon("puzzlepiece.extension.fill", size: 15).foregroundStyle(Color.privioPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Browser extension").font(.privioSystem(size: 12.5, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                    if let detected {
                        Text(verbatim: detected.version.map { "\(detected.browser) · v\($0)" } ?? detected.browser)
                            .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
                    } else {
                        Text("Optional - adds in-page unlock in Chromium")
                            .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
                    }
                }
                Spacer()
                Button("Set up") { showingExtensionSetup = true }
                    .buttonStyle(.plain).font(.privioSystem(size: 11.5, weight: .semibold)).foregroundStyle(Color.privioPrimary)
            }
            HStack(spacing: 6) {
                Circle().fill(protectionWorks ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(detected == nil ? "Not detected" : (!connected ? "Inactive" :
                     (protectionWorks ? "Connected · protection active" : "Connected · protection off")))
                    .font(.privioSystem(size: 10.5, weight: .medium)).foregroundStyle(Color.privioTextSecondary)
                Spacer()
            }
            .padding(.leading, 24)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.privioSurface)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.privioSeparator)))
        .padding(.horizontal, PrivioLayout.pagePadding)
        .padding(.top, PrivioLayout.pagePadding)
    }

    private func monitorExtensions() async {
        while !Task.isCancelled {
            if let url = URL(string: "http://127.0.0.1:8987/privio/extensions"),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let response = try? JSONDecoder().decode(BrowserExtensionResponse.self, from: data) {
                mergeExtensions(response.extensions)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func loadKnownExtensions() {
        guard let data = UserDefaults.standard.data(forKey: "knownBrowserExtensions"),
              let known = try? JSONDecoder().decode([BrowserExtensionStatus].self, from: data) else { return }
        extensionStatuses = known.map {
            BrowserExtensionStatus(browser: $0.browser, version: $0.version,
                                   active: false, lastSeen: $0.lastSeen)
        }
    }

    /// Prawdziwe rozszerzenie raportuje wersję semantyczną (np. „0.1.14"). Kanały
    /// diagnostyczne proxy zgłaszają się z wersją typu „vdiagnostic"/„vlocal" i nie są
    /// osobnymi rozszerzeniami - odfiltrowujemy je, by lista pokazywała tylko realne.
    private static func isRealExtension(_ s: BrowserExtensionStatus) -> Bool {
        s.version?.first?.isNumber == true
    }

    private func mergeExtensions(_ live: [BrowserExtensionStatus]) {
        var merged = Dictionary(uniqueKeysWithValues: extensionStatuses.map { ($0.browser, $0) })
        for status in live where Self.isRealExtension(status) { merged[status.browser] = status }
        extensionStatuses = merged.values.filter(Self.isRealExtension).sorted { $0.browser < $1.browser }
        let remembered = extensionStatuses.map {
            BrowserExtensionStatus(browser: $0.browser, version: $0.version,
                                   active: false, lastSeen: $0.lastSeen)
        }
        if let data = try? JSONEncoder().encode(remembered) {
            UserDefaults.standard.set(data, forKey: "knownBrowserExtensions")
        }
    }

    @ViewBuilder private var detailColumn: some View {
        if let snapshot = selectedSnapshot, model.isPro { WebsiteDetailPanel(snapshot: snapshot) }
        else {
            VStack(spacing: 8) {
                FAIcon(model.isPro ? "hand.point.up.left" : "star.circle", size: 32).foregroundStyle(Color.privioTextTertiary)
                Text(model.isPro ? "Select a website to configure it" : "Website protection requires Privio Pro")
                    .font(.privioSystem(size: 14)).foregroundStyle(Color.privioTextSecondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func effectiveStatus(_ s: WebTargetSnapshot) -> LockStatus {
        WebTargetSnapshot.effectiveStatus(target: s.target, rawStatus: s.status,
                                          protectionActive: model.state.protectionActive)
    }
    private func selectFirstIfNeeded() {
        if let selectedID, model.webTargets.contains(where: { $0.id == selectedID }) { return }
        selectedID = model.webTargets.first?.id
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(); FAIcon("lock.rectangle.dashed", size: 40).foregroundStyle(Color.privioTextTertiary)
            Text(searchText.isEmpty ? "No protected websites yet" : "No matches").font(.privioSystem(size: 14, weight: .medium)).foregroundStyle(Color.privioTextSecondary)
            if searchText.isEmpty { Text("Add a website to protect it with Touch ID or password.").font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary).multilineTextAlignment(.center) }
            Spacer()
        }.frame(maxWidth: .infinity).padding(24)
    }
    private var proUpsell: some View {
        VStack(spacing: 10) {
            Spacer(); FAIcon("star.circle.fill", size: 36).foregroundStyle(Color.privioPrimary)
            Text("Website blocking is a Pro feature").font(.privioSystem(size: 14, weight: .medium)).foregroundStyle(Color.privioTextSecondary)
            Text("Activate Privio Pro in About to protect websites.").font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary).multilineTextAlignment(.center); Spacer()
        }.frame(maxWidth: .infinity).padding(24)
    }
}

private struct ProtectedWebsiteRow: View {
    let snapshot: WebTargetSnapshot; let status: LockStatus; let isSelected: Bool
    let onSelect: () -> Void; let onToggleProtection: (Bool) -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                WebsiteFaviconView(domain: snapshot.target.domain, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.target.displayName).font(.privioSystem(size: 14, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                    Text(snapshot.target.domain).font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8); StatusBadge(status: status, compact: true)
                Toggle("", isOn: Binding(get: { snapshot.target.protectionEnabled }, set: onToggleProtection))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.privioPrimary)
                    .accessibilityLabel("Protect \(snapshot.target.displayName)")
                FAIcon("chevron.right", size: 11).foregroundStyle(Color.privioTextTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.privioSurfaceSelected : (hovering ? Color.privioSurfaceSelected.opacity(0.5) : Color.privioSurface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.privioPrimary.opacity(0.5) : Color.privioSeparator, lineWidth: isSelected ? 1.5 : 1)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct WebsiteFaviconView: View {
    let domain: String
    let size: CGFloat
    @State private var favicon: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(favicon == nil ? AnyShapeStyle(PrivioGradient.brand) : AnyShapeStyle(Color.white))
            .frame(width: size, height: size)
            .overlay {
                if let favicon {
                    Image(nsImage: favicon)
                        .resizable().scaledToFit()
                        .padding(size * 0.13)
                } else {
                    FAIcon("globe", size: size * 0.48).foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Color.privioSeparator.opacity(favicon == nil ? 0 : 0.7), lineWidth: 1))
            .task(id: domain) { favicon = await WebsiteFaviconLoader.shared.image(for: domain) }
    }
}

@MainActor
private final class WebsiteFaviconLoader {
    static let shared = WebsiteFaviconLoader()
    private var cache: [String: NSImage] = [:]
    private var missing = Set<String>()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        // Pobieranie ikon nie może zostać zatrzymane przez proxy blokujące tę samą
        // domenę; reszta ruchu nadal przechodzi przez normalne reguły Privio.
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        session = URLSession(configuration: configuration)
    }

    func image(for domain: String) async -> NSImage? {
        if let cached = cache[domain] { return cached }
        if missing.contains(domain) { return nil }

        let paths = ["/favicon.ico", "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"]
        for path in paths {
            guard let url = URL(string: "https://\(domain)\(path)") else { continue }
            var request = URLRequest(url: url)
            request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 2_000_000,
                  let image = NSImage(data: data), image.isValid else { continue }
            cache[domain] = image
            return image
        }
        missing.insert(domain)
        return nil
    }
}

private struct WebsiteDetailPanel: View {
    @Environment(AppModel.self) private var model
    let snapshot: WebTargetSnapshot
    private var target: WebTarget { snapshot.target }
    private var status: LockStatus {
        WebTargetSnapshot.effectiveStatus(target: target, rawStatus: snapshot.status,
                                          protectionActive: model.state.protectionActive)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrivioLayout.sectionSpacing) {
                header
                section("Lock Settings") {
                    pickerRow("Lock after inactivity", selection: lockBinding, options: LockTimeoutPreset.allCases, title: \.title)
                    Text("The timer starts after you leave this tab or the browser loses focus. Closing the last tab locks the website immediately.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                section("Authentication") {
                    pickerRow("Unlock with", selection: authBinding, options: WebsiteAuthMethod.allCases, title: \.title)
                    Text(LocalizedStringKey(authBinding.wrappedValue.footnote)).font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 12)
                Button(role: .destructive) { model.removeWebTarget(target) } label: {
                    HStack(spacing: 6) { FAIcon("trash"); Text("Remove Website") }
                        .font(.privioSystem(size: 13, weight: .medium)).foregroundStyle(Color.privioDanger)
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(PrivioLayout.pagePadding)
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            WebsiteFaviconView(domain: target.domain, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.displayName).font(.privioSystem(size: 20, weight: .bold)).foregroundStyle(Color.privioTextPrimary)
                Text(target.domain).font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(status: status)
                if status == .locked { actionButton("Unlock", icon: "touchid") { model.unlockWebTarget(target) } }
                else if status == .unlocked { actionButton("Lock", icon: "lock.fill") { model.lockWebTarget(target) } }
            }
        }
    }
    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 5) { FAIcon(icon); Text(title) }
            .font(.privioSystem(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(PrivioGradient.brand)) }.buttonStyle(.plain)
    }
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.privioSystem(size: 12, weight: .semibold)).foregroundStyle(Color.privioTextSecondary).textCase(.uppercase).padding(.bottom, 8)
            VStack(spacing: PrivioLayout.cardSpacing) { content() }
                .padding(PrivioLayout.cardPadding)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.privioSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.privioSeparator, lineWidth: 1)))
        }
    }
    private func pickerRow<Option: Hashable & Identifiable>(_ label: LocalizedStringKey, selection: Binding<Option>, options: [Option], title: KeyPath<Option, String>) -> some View {
        HStack { Text(label).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary); Spacer()
            Picker("", selection: selection) { ForEach(options) { Text(LocalizedStringKey($0[keyPath: title])).tag($0) } }
                .labelsHidden().pickerStyle(.menu).tint(.privioPrimary).fixedSize() }
    }
    private var lockBinding: Binding<LockTimeoutPreset> {
        Binding(get: { .from(seconds: target.lockAfterInactivity) }, set: { p in var updated = target; updated.lockAfterInactivity = p.seconds; model.updateWebTarget(updated) })
    }
    private var authBinding: Binding<WebsiteAuthMethod> {
        Binding(get: { WebsiteAuthMethod(target: target) }, set: { method in var updated = target; method.apply(to: &updated); model.updateWebTarget(updated) })
    }
}

private struct AddWebsiteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    var body: some View {
        PrivioModal(title: "Add Website",
                    subtitle: "Enter the website address you want Privio to protect.",
                    width: 460) {
            PrivioModalField(icon: "globe") {
                TextField("example.com", text: $domain)
                    .textFieldStyle(.plain).font(.privioSystem(size: 14)).onSubmit(add)
            }
        } footer: {
            Button("Cancel") { dismiss() }.privioSecondaryButton()
            Spacer()
            Button("Add Website", action: add).privioPrimaryButton().disabled(!WebTarget.normalize(domain).contains("."))
        }
    }
    private func add() { guard WebTarget.normalize(domain).contains(".") else { return }; model.addWebTarget(domain); dismiss() }
}

private struct BrowserExtensionStatus: Codable, Identifiable {
    let browser: String
    let version: String?
    let active: Bool
    let lastSeen: TimeInterval
    var id: String { browser }
}

private struct BrowserExtensionResponse: Decodable {
    let extensions: [BrowserExtensionStatus]
}

private struct BrowserExtensionSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showChromiumSteps = false
    @State private var showFirefoxSteps = false
    let statuses: [BrowserExtensionStatus]

    private struct SupportedBrowser: Identifiable {
        let name: String
        var assetName: String = ""
        var brandScalar: UInt32? = nil   // glif Font Awesome Brands (Firefox), gdy brak assetu
        var tint: Color? = nil
        var id: String { name }
    }

    private let chromiumBrowsers = [
        SupportedBrowser(name: "Google Chrome", assetName: "BrowserChrome"),
        SupportedBrowser(name: "Microsoft Edge", assetName: "BrowserEdge"),
        SupportedBrowser(name: "Brave", assetName: "BrowserBrave"),
        SupportedBrowser(name: "Opera", assetName: "BrowserOpera"),
        SupportedBrowser(name: "Vivaldi", assetName: "BrowserVivaldi"),
        SupportedBrowser(name: "Arc", assetName: "BrowserArc")
    ]
    // Firefox nie ma logo w katalogu zasobów - rysujemy oficjalny glif marki z
    // dołączonego Font Awesome Brands (fa-firefox, U+F269; F907 nie ma w tym pliku),
    // w barwie Firefoksa.
    private let firefoxBrowsers = [
        SupportedBrowser(name: "Mozilla Firefox", brandScalar: 0xF269,
                         tint: Color(red: 1.0, green: 0.44, blue: 0.22))
    ]

    var body: some View {
        PrivioModal(title: "Browser Extension",
                    subtitle: "Install the Privio add-on for your browser.",
                    width: 640) {
          VStack(alignment: .leading, spacing: 16) {
            browserCoverageNote
            detectedCard
            familyCard(
                title: "Chromium",
                subtitle: "Chrome, Edge, Brave, Opera, Vivaldi, Arc",
                browsers: chromiumBrowsers,
                storeName: "Chrome Web Store",
                manualDetail: "Load unpacked",
                folderName: "ChromeExtension",
                expanded: $showChromiumSteps,
                manualAction: { model.openChromeExtensionSetup() },
                steps: [
                    "Click 'Install manually' - Privio reveals the extension folder and opens chrome://extensions.",
                    "Turn on Developer mode (top-right corner).",
                    "Click 'Load unpacked' and choose the ChromeExtension folder.",
                    "Back in Privio the status turns Active automatically."
                ])
            familyCard(
                title: "Firefox",
                subtitle: "Mozilla Firefox",
                browsers: firefoxBrowsers,
                storeName: "Firefox Add-ons",
                manualDetail: "Temporary add-on",
                folderName: "FirefoxExtension",
                expanded: $showFirefoxSteps,
                manualAction: { model.openFirefoxExtensionSetup() },
                steps: [
                    "Click 'Install manually' - Privio reveals the add-on folder and opens about:debugging.",
                    "Open 'This Firefox' and click 'Load Temporary Add-on'.",
                    "Choose manifest.json in the FirefoxExtension folder.",
                    "The temporary add-on is removed when Firefox restarts; a permanent store version is coming soon."
                ])
          }
        } footer: {
            Spacer()
            Button("Done") { dismiss() }.privioPrimaryButton()
        }
    }

    /// Karta „Wykryte rozszerzenia Privio" - status heartbeatu z przeglądarek.
    private var detectedCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Detected Privio extensions")
                    .font(.privioSystem(size: 12.5, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                Spacer()
                Text("\(statuses.count)").font(.privioSystem(size: 11, weight: .bold)).foregroundStyle(Color.privioPrimary)
            }
            if statuses.isEmpty {
                Text("No installation detected. Open a browser with Privio installed to make it appear here.")
                    .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
            } else {
                ForEach(statuses.sorted(by: { $0.browser < $1.browser })) { status in
                    HStack(spacing: 8) {
                        Circle().fill(status.active ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(verbatim: status.browser).font(.privioSystem(size: 12, weight: .medium))
                        Spacer()
                        if let version = status.version { Text(verbatim: "v\(version)") }
                        Text(status.active ? "Active" : "Inactive")
                    }
                    .foregroundStyle(Color.privioTextSecondary).font(.privioSystem(size: 10.5))
                }
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.privioSurface)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.privioSeparator)))
    }

    /// Sekcja rodziny przeglądarek (Chromium / Firefox): ikony, przyciski instalacji
    /// (sklep - wkrótce; ręcznie - działa) oraz rozwijana instrukcja pozasklepowa.
    @ViewBuilder
    private func familyCard(title: LocalizedStringKey, subtitle: LocalizedStringKey,
                            browsers: [SupportedBrowser], storeName: LocalizedStringKey,
                            manualDetail: LocalizedStringKey, folderName: String,
                            expanded: Binding<Bool>,
                            manualAction: @escaping () -> Void,
                            steps: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.privioSystem(size: 14, weight: .bold)).foregroundStyle(Color.privioTextPrimary)
                Text(subtitle).font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(chunk(browsers, 3).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(row) { browser in
                            HStack(spacing: 6) { browserIcon(browser); Text(verbatim: browser.name) }
                                .font(.privioSystem(size: 11, weight: .medium)).foregroundStyle(Color.privioTextSecondary)
                                .padding(.leading, 6).padding(.trailing, 9).padding(.vertical, 5)
                                .background(Capsule().fill(Color.privioBackground))
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) { FAIcon("storefront.fill", size: 12); Text(storeName) }
                        Text("Coming soon").font(.privioSystem(size: 10, weight: .regular))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).disabled(true)
                Button(action: manualAction) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) { FAIcon("shippingbox.fill", size: 12); Text("Install manually") }
                        Text(manualDetail).font(.privioSystem(size: 10, weight: .regular))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent).tint(.privioPrimary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
                } label: {
                    HStack {
                        Text("Manual installation instructions")
                            .font(.privioSystem(size: 11)).foregroundStyle(Color.privioTextSecondary)
                        Spacer()
                        FAIcon(expanded.wrappedValue ? "chevron.up" : "chevron.down", size: 10)
                            .foregroundStyle(Color.privioTextTertiary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded.wrappedValue {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            setupStep(index + 1, step)
                        }
                        // Lokalizacja rozpakowanych plików wtyczki + skrót do Findera.
                        HStack(spacing: 8) {
                            FAIcon("folder.fill", size: 11).foregroundStyle(Color.privioTextTertiary)
                            Text(verbatim: model.extensionFolderPath(named: folderName))
                                .font(.privioSystem(size: 10, design: .monospaced))
                                .foregroundStyle(Color.privioTextTertiary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button { model.revealExtensionFolder(named: folderName) } label: {
                                HStack(spacing: 5) { FAIcon("magnifyingglass", size: 10); Text("Reveal in Finder") }
                                    .font(.privioSystem(size: 10.5, weight: .semibold)).foregroundStyle(Color.privioPrimary)
                            }
                            .buttonStyle(.plain).fixedSize()
                        }
                        .padding(.top, 2)
                    }.padding(.top, 10)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.privioSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.privioSeparator)))
    }

    /// Uczciwa nota o zakresie ochrony (§5.4 FIX-web-protection). Dziś realnym
    /// strażnikiem stron jest wtyczka Chromium; Safari i Firefox NIE są jeszcze w
    /// pełni objęte (Safari nie honoruje systemowego proxy Privio). Pełna, niezależna
    /// od przeglądarki egzekucja przyjdzie z systemowym filtrem (NetworkExtension).
    /// NIE przedstawiaj ochrony stron jako pełnej/cross-browser, dopóki go nie ma.
    private var browserCoverageNote: some View {
        HStack(alignment: .top, spacing: 9) {
            FAIcon("exclamationmark.triangle.fill", size: 13).foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Which browsers are protected")
                    .font(.privioSystem(size: 11.5, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                Text("Website protection covers Chromium browsers (Chrome, Edge, Brave, Opera, Vivaldi, Arc) with the Privio extension, and Firefox with the separate Privio Firefox add-on. Safari is not covered yet - it ignores the system proxy and can bypass the block. Full, browser-independent protection is planned via a system network filter.")
                    .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.28))))
    }

    @ViewBuilder
    private func browserIcon(_ browser: SupportedBrowser) -> some View {
        if let raw = browser.brandScalar, let scalar = Unicode.Scalar(raw) {
            // Glif marki z Font Awesome Brands (np. Firefox), własny font jak w FAIcon.
            Text(String(scalar))
                .font(.custom("FontAwesome6Brands-Regular", fixedSize: 15))
                .foregroundStyle(browser.tint ?? Color.privioTextSecondary)
                .frame(width: 17, height: 17)
        } else {
            Image(browser.assetName)
                .resizable().scaledToFit().frame(width: 17, height: 17)
        }
    }

    private func chunk(_ items: [SupportedBrowser], _ size: Int) -> [[SupportedBrowser]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    private func setupStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.privioSystem(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.privioPrimary))
            Text(text).font(.privioSystem(size: 12.5)).foregroundStyle(Color.privioTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum WebsiteAuthMethod: String, CaseIterable, Identifiable, Hashable {
    case touchIDOrPassword, touchIDOnly, passwordOnly
    var id: Self { self }
    var title: String { switch self { case .touchIDOrPassword: "Touch ID or password"; case .touchIDOnly: "Touch ID only"; case .passwordOnly: "Password only" } }
    var footnote: String { switch self { case .touchIDOrPassword: "Falls back to your Mac password - e.g. with the lid closed."; case .touchIDOnly: "Requires Touch ID; can’t unlock when Touch ID is unavailable."; case .passwordOnly: "Always asks for your Mac account password; Touch ID is not used." } }
    init(target: WebTarget) { self = !target.requireTouchID ? .passwordOnly : (target.allowPasswordFallback ? .touchIDOrPassword : .touchIDOnly) }
    func apply(to target: inout WebTarget) { target.requireTouchID = self != .passwordOnly; target.allowPasswordFallback = self != .touchIDOnly }
}
