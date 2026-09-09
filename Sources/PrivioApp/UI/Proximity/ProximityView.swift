import AppKit
import CoreImage.CIFilterBuiltins
import PrivioCore
import SwiftUI

/// Sekcja „Blokada po odejściu" (Bluetooth proximity, Pro): podgląd sparowanych
/// urządzeń (zasięg/RSSI, bateria, połączenie), wybór 1-2 zaufanych, cel blokady,
/// progi i wyłącznik. Cała wrażliwa logika żyje w `ProximityLockPolicy` (testowanej).
struct ProximityView: View {
    @Environment(AppModel.self) private var model
    @Environment(ProximityController.self) private var proximity
    @State private var selectedDeviceID: String?
    @State private var showingAddDevice = false

    private var config: ProximityConfig { model.proximityConfig }
    private var trustedDevices: [ProximityDeviceInfo] {
        config.trustedDeviceIDs.map { proximity.deviceInfo(for: $0) }
    }
    private var selectedDevice: ProximityDeviceInfo? {
        guard let selectedDeviceID, config.trustedDeviceIDs.contains(selectedDeviceID) else { return nil }
        return proximity.deviceInfo(for: selectedDeviceID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.privioSeparator)
            HStack(spacing: 0) {
                deviceListColumn.frame(minWidth: 320, maxWidth: 420)
                Divider().overlay(Color.privioSeparator)
                detailColumn.frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            AddProximityDeviceSheet().environment(model).environment(proximity)
        }
        .onAppear { proximity.start(); proximity.setSectionVisible(true) }
        .onDisappear { proximity.setSectionVisible(false) }
        .onChange(of: config.trustedDeviceIDs) { _, _ in selectFirstIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Proximity Lock").font(.privioSystem(size: 24, weight: .bold)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Toggle("Lock when you walk away", isOn: Binding(
                get: { config.enabled },
                set: { on in model.setProximityConfig { $0.enabled = on } }
            ))
            .toggleStyle(.switch).controlSize(.small).tint(.privioPrimary)
            .disabled(!model.isPro || config.trustedDeviceIDs.isEmpty || proximity.hasClassicWatchWithoutBLE)
            Button { showingAddDevice = true } label: {
                HStack(spacing: 6) { FAIcon("plus"); Text("Add Device") }
                    .font(.privioSystem(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PrivioGradient.brand))
            }
            .buttonStyle(.plain)
            .disabled(!model.isPro || config.trustedDeviceIDs.count >= ProximityConfig.maxTrustedDevices)
            .opacity(model.isPro && config.trustedDeviceIDs.count < ProximityConfig.maxTrustedDevices ? 1 : 0.45)
        }
        .padding(.horizontal, PrivioLayout.pagePadding)
        .padding(.top, PrivioLayout.headerTop)
        .padding(.bottom, PrivioLayout.headerBottom)
    }

    private var deviceListColumn: some View {
        VStack(spacing: 12) {
            if proximity.bluetoothDenied { btPermissionCard.padding(.horizontal, PrivioLayout.pagePadding).padding(.top, PrivioLayout.pagePadding) }
            else if proximity.bluetoothState == .poweredOff { bluetoothOffCard.padding(.horizontal, PrivioLayout.pagePadding).padding(.top, PrivioLayout.pagePadding) }
            if !model.isPro { proCard.padding(PrivioLayout.pagePadding) }
            else if trustedDevices.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    FAIcon("dot.radiowaves.left.and.right", size: 40).foregroundStyle(Color.privioTextTertiary)
                    Text("No trusted devices yet").font(.privioSystem(size: 14, weight: .medium))
                    Text("Add a phone, watch or headphones to use it as an automatic lock trigger.")
                        .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary).multilineTextAlignment(.center)
                    Button("Add Device") { showingAddDevice = true }.buttonStyle(.borderedProminent).tint(.privioPrimary)
                    Spacer()
                }.frame(maxWidth: .infinity).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: PrivioLayout.rowSpacing) {
                        ForEach(trustedDevices) { device in
                            TrustedDeviceRow(
                                device: device, threshold: config.rssiThreshold,
                                isSelected: selectedDeviceID == device.id,
                                isActive: config.isDeviceActive(device.id),
                                select: { selectedDeviceID = device.id },
                                setActive: { setDeviceActive(device.id, $0) })
                        }
                    }.padding(PrivioLayout.pagePadding)
                }
            }
        }
        .onAppear { selectFirstIfNeeded() }
    }

    @ViewBuilder private var detailColumn: some View {
        if let device = selectedDevice, model.isPro {
            ScrollView {
                VStack(alignment: .leading, spacing: PrivioLayout.sectionSpacing) {
                    deviceDetailHeader(device)
                    if proximity.hasClassicWatchWithoutBLE { watchSignalWarning }
                    if proximity.autoPausedNotice { autoPausedCard }
                    actionCard
                    thresholdsCard
                    safetyCard
                    Spacer(minLength: 12)
                    Button(role: .destructive) { removeDevice(device.id) } label: {
                        HStack(spacing: 6) { FAIcon("trash"); Text("Remove Device") }
                            .font(.privioSystem(size: 13, weight: .medium)).foregroundStyle(Color.privioDanger)
                    }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(PrivioLayout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(spacing: 8) {
                FAIcon("hand.point.up.left", size: 32).foregroundStyle(Color.privioTextTertiary)
                Text("Select a device to configure it")
                    .font(.privioSystem(size: 14)).foregroundStyle(Color.privioTextSecondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func deviceDetailHeader(_ device: ProximityDeviceInfo) -> some View {
        HStack(spacing: 16) {
            FAIcon(deviceSymbol(device.kind), size: 27)
                .foregroundStyle(Color.privioPrimary).frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.privioPrimary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.privioSystem(size: 20, weight: .bold))
                if distanceUnavailable(device) {
                    DeviceActivityStatusView(isActive: device.isConnected, showsLabel: true)
                } else {
                    HStack(spacing: 8) {
                        SignalStrengthView(rssi: device.isConnected ? device.rssi : nil, threshold: config.rssiThreshold)
                            .frame(width: 26, height: 18)
                        Text(deviceRangeText(device)).font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextSecondary)
                    }
                }
            }
            Spacer()
        }
    }

    private var watchSignalWarning: some View {
        SettingsCard {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("This watch does not provide a reliable paired signal")
                        .font(.privioSystem(size: 13.5, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                    Text("Galaxy Watch briefly connects and disconnects even while it is on your wrist. Automatic locking stays disabled until its nearby BLE signal is identified.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }
            } icon: {
                FAIcon("exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    /// Urządzenie, dla którego nie zmierzymy odległości: nie jest beaconem Privio i nie
    /// udostępnia siły sygnału (klasyczne słuchawki itp. zwracają brak/0 dBm). Blokada
    /// zadziała tylko przy rozłączeniu, nie po odległości - o tym ostrzegamy.
    private func distanceUnavailable(_ device: ProximityDeviceInfo) -> Bool {
        !device.id.hasPrefix("ble:privio:") && device.rssi == nil
    }

    private func selectFirstIfNeeded() {
        if let selectedDeviceID, config.trustedDeviceIDs.contains(selectedDeviceID) { return }
        selectedDeviceID = config.trustedDeviceIDs.first
    }

    private func removeDevice(_ id: String) {
        if id.hasPrefix("ble:privio:") { PrivioBeaconPairingStore.shared.remove(deviceID: id) }
        model.setProximityConfig { cfg in
            cfg.trustedDeviceIDs.removeAll { $0 == id }
            cfg.disabledDeviceIDs.removeAll { $0 == id }
            if cfg.trustedDeviceIDs.isEmpty { cfg.enabled = false }
        }
    }

    /// Włącz/wyłącz urządzenie w blokowaniu bez usuwania go z listy (jak apka/strona).
    private func setDeviceActive(_ id: String, _ active: Bool) {
        model.setProximityConfig { cfg in
            if active { cfg.disabledDeviceIDs.removeAll { $0 == id } }
            else if !cfg.disabledDeviceIDs.contains(id) { cfg.disabledDeviceIDs.append(id) }
        }
    }

    private func deviceSymbol(_ kind: ProximityDeviceKind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    private func deviceRangeText(_ device: ProximityDeviceInfo) -> String {
        guard device.isConnected else { return String(localized: "No current signal - paired but not connected") }
        guard let rssi = device.rssi else { return String(localized: "Connected - signal unavailable") }
        let state = rssi >= config.rssiThreshold
            ? String(localized: "In range") : String(localized: "Out of range")
        return "\(state) · \(rssi) dBm"
    }

    // MARK: - Status

    private var statusCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill((config.enabled ? Color.privioUnlocked : Color.privioPrimary).opacity(0.13))
                        .frame(width: 52, height: 52)
                    FAIcon("dot.radiowaves.left.and.right", size: 22)
                        .foregroundStyle(config.enabled ? Color.privioUnlocked : Color.privioPrimary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lock when you walk away")
                        .font(.privioSystem(size: 16, weight: .semibold))
                        .foregroundStyle(Color.privioTextPrimary)
                    Text(statusSubtitle)
                        .font(.privioSystem(size: 11.5))
                        .foregroundStyle(Color.privioTextTertiary)
                }
                Spacer()
                if config.paused, model.isPro, config.enabled {
                    Button("Resume") { proximity.setPaused(false) }
                        .buttonStyle(.bordered)
                }
                Toggle("", isOn: Binding(
                    get: { config.enabled },
                    set: { on in model.setProximityConfig { $0.enabled = on } }
                ))
                .labelsHidden().toggleStyle(.switch).tint(.privioPrimary)
                .disabled(!model.isPro || config.trustedDeviceIDs.isEmpty)
            }
        }
    }

    private var statusSubtitle: LocalizedStringKey {
        if !model.isPro { return "A Pro feature. Uses a paired Bluetooth device only as a trigger." }
        if config.trustedDeviceIDs.isEmpty { return "Choose a trusted device below to enable this." }
        if config.paused { return "Paused - no automatic locking until you resume." }
        if !config.enabled { return "Off. Turn on to lock automatically when your device leaves." }
        let target = config.lockTarget == .screen
            ? String(localized: "the screen") : String(localized: "protected apps, sites and the vault")
        return "On - will lock \(target) after the device is out of range."
    }

    // MARK: - Pro / auto-pause

    private var btPermissionCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                FAIcon("exclamationmark.triangle.fill", size: 18).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bluetooth access is off")
                        .font(.privioSystem(size: 14, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                    Text("Privio needs Bluetooth to see your devices. Turn it on for Privio in System Settings.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open Settings") { openBluetoothPrivacySettings() }
                    .buttonStyle(.borderedProminent).tint(.privioPrimary)
            }
        }
    }

    private func openBluetoothPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    private var bluetoothOffCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                FAIcon("bluetooth.slash", size: 18).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bluetooth is off")
                        .font(.privioSystem(size: 14, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                    Text("Turn on Bluetooth to find and monitor your trusted devices.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }
                Spacer()
                Button("Open Bluetooth Settings") { openBluetoothSettings() }
                    .buttonStyle(.borderedProminent).tint(.privioPrimary)
            }
        }
    }

    private var proCard: some View {
        SettingsCard("Privio Pro") {
            Text("Proximity auto-lock is part of Privio Pro. Unlock it once, offline, to lock your Mac automatically when your phone, watch or headphones leave.")
                .font(.privioSystem(size: 13)).foregroundStyle(Color.privioTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("See Pro") { model.selectedSection = .settings }
                .buttonStyle(.borderedProminent).tint(.privioPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var autoPausedCard: some View {
        SettingsCard {
            HStack(spacing: 10) {
                FAIcon("exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-lock paused itself").font(.privioSystem(size: 13.5, weight: .medium))
                    Text("It locked several times in a row (flickering signal). Resume when you're ready.")
                        .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                }
                Spacer()
                Button("Resume") { proximity.setPaused(false) }.buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Devices

    private var devicesCard: some View {
        SettingsCard("Devices") {
            HStack {
                Button { openBluetoothSettings() } label: {
                    Label("Pair new device…", fa: "plus")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Text("\(config.trustedDeviceIDs.count)/\(ProximityConfig.maxTrustedDevices)")
                    .font(.privioSystem(size: 11.5, weight: .medium)).foregroundStyle(Color.privioTextTertiary)
            }
            Text("Paired devices and nearby Bluetooth devices (e.g. a watch or band) appear below. Pick up to \(ProximityConfig.maxTrustedDevices) that stay with you.")
                .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Color.privioSeparator)
            if proximity.devices.isEmpty {
                VStack(spacing: 8) {
                    if proximity.bluetoothState == .poweredOn {
                        ProgressView().controlSize(.small)
                        Text("Searching for Bluetooth devices…").font(.privioSystem(size: 13, weight: .medium))
                        Text("Keep your phone, watch or headphones nearby while Privio scans.")
                            .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                    } else {
                        FAIcon("dot.radiowaves.left.and.right", size: 28).foregroundStyle(Color.privioTextTertiary)
                        Text("Bluetooth devices are unavailable").font(.privioSystem(size: 13, weight: .medium))
                        Text("Check Bluetooth and Privio's access in System Settings.")
                            .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(proximity.devices) { device in
                        DeviceRow(device: device,
                                  threshold: config.rssiThreshold,
                                  isTrusted: config.trustedDeviceIDs.contains(device.id),
                                  canTrustMore: config.trustedDeviceIDs.count < ProximityConfig.maxTrustedDevices,
                                  setTrusted: { on in setTrusted(device.id, on) })
                        if device.id != proximity.devices.last?.id {
                            Divider().overlay(Color.privioSeparator)
                        }
                    }
                }
            }
        }
    }

    private func setTrusted(_ id: String, _ on: Bool) {
        model.setProximityConfig { cfg in
            if on {
                if !cfg.trustedDeviceIDs.contains(id),
                   cfg.trustedDeviceIDs.count < ProximityConfig.maxTrustedDevices {
                    cfg.trustedDeviceIDs.append(id)
                }
            } else {
                cfg.trustedDeviceIDs.removeAll { $0 == id }
            }
        }
    }

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Action + thresholds

    private var actionCard: some View {
        SettingsCard("When the device leaves") {
            Picker("", selection: Binding(
                get: { config.lockTarget },
                set: { target in model.setProximityConfig { $0.lockTarget = target } }
            )) {
                Text("Lock the screen").tag(ProximityLockTarget.screen)
                Text("Lock Privio apps, sites & vault").tag(ProximityLockTarget.protectedApps)
            }
            .labelsHidden().pickerStyle(.radioGroup)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(config.lockTarget == .screen
                 ? "Switches to the macOS login window (requires your login password to be set)."
                 : "Locks protected apps, blocked sites and the Private Vault - fully native.")
                .font(.privioSystem(size: 11.5)).foregroundStyle(Color.privioTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thresholdsCard: some View {
        SettingsCard("Sensitivity") {
            stepperRow(
                title: "Wait before locking",
                value: config.awayDebounceSeconds,
                unit: "s",
                range: ProximityConfig.awayDebounceRange,
                step: 5,
                set: { v in model.setProximityConfig { $0.awayDebounceSeconds = v } }
            )
            Divider().overlay(Color.privioSeparator)
            stepperRow(
                title: "Pause locking below battery",
                value: config.lowBatteryThreshold,
                unit: "%",
                range: ProximityConfig.lowBatteryRange,
                step: 5,
                set: { v in model.setProximityConfig { $0.lowBatteryThreshold = v } }
            )
            if let d = selectedDevice, !distanceUnavailable(d) {
                Divider().overlay(Color.privioSeparator)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trigger distance").font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
                            Text("Roughly how far you walk off before Privio locks. Real range depends on walls and where you keep the watch.")
                                .font(.privioSystem(size: 11)).foregroundStyle(Color.privioTextTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Self.rangeName(config.rssiThreshold))
                                .font(.privioSystem(size: 13, weight: .semibold)).foregroundStyle(Color.privioPrimary)
                            Text(Self.rangeMeters(config.rssiThreshold))
                                .font(.privioSystem(size: 11).monospacedDigit()).foregroundStyle(Color.privioTextTertiary)
                        }.fixedSize()
                    }
                    // Suwak odwrócony: w prawo = dłuższy zasięg (niższy próg dBm), w lewo =
                    // bliżej. Opisowa wartość wyżej i tak pokazuje realną odległość dla progu.
                    Slider(
                        value: Binding(
                            get: { Double(Self.rssiBoundsSum - config.rssiThreshold) },
                            set: { v in model.setProximityConfig { $0.rssiThreshold = Self.rssiBoundsSum - Int(v.rounded()) } }
                        ),
                        in: Double(ProximityConfig.rssiThresholdRange.lowerBound)...Double(ProximityConfig.rssiThresholdRange.upperBound),
                        step: 5
                    ).tint(.privioPrimary)
                    HStack(spacing: 8) {
                        Text("← Locks after a shorter distance").font(.privioSystem(size: 10)).foregroundStyle(Color.privioTextTertiary)
                        Spacer()
                        Text("Locks after a longer distance →").font(.privioSystem(size: 10)).foregroundStyle(Color.privioTextTertiary)
                    }
                }
            }
        }
    }

    /// Suma granic zakresu progu - do odwrócenia suwaka (prawo = dłuższy zasięg).
    static let rssiBoundsSum =
        ProximityConfig.rssiThresholdRange.lowerBound + ProximityConfig.rssiThresholdRange.upperBound

    /// Zamiana progu RSSI (dBm) na zrozumiały opis odległości. Wartości orientacyjne -
    /// realny zasięg BLE zależy od ścian, ciała i tego, gdzie użytkownik trzyma zegarek.
    static func rangeName(_ threshold: Int) -> String {
        if threshold >= -55 { return String(localized: "Right by the desk") }
        if threshold >= -70 { return String(localized: "Close") }
        if threshold >= -82 { return String(localized: "Same room") }
        if threshold >= -90 { return String(localized: "Next room") }
        return String(localized: "Far away")
    }

    static func rangeMeters(_ threshold: Int) -> String {
        if threshold >= -55 { return "~1-2 m" }
        if threshold >= -70 { return "~2-4 m" }
        if threshold >= -82 { return "~4-8 m" }
        if threshold >= -90 { return "~8-12 m" }
        return "~12 m+"
    }

    private func stepperRow(title: LocalizedStringKey, value: Int, unit: String,
                            range: ClosedRange<Int>, step: Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
            Spacer()
            Text("\(value) \(unit)").font(.privioSystem(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.privioTextSecondary).frame(minWidth: 48, alignment: .trailing)
            Stepper("", value: Binding(get: { value }, set: set), in: range, step: step)
                .labelsHidden()
        }
    }

    // MARK: - Safety note

    private var safetyCard: some View {
        SettingsCard("Safety") {
            Label {
                Text("Your device only ever triggers a lock - never an unlock. If it dies, breaks or is lost, you still sign in normally with Touch ID or your password, and Privio simply stops auto-locking. It can never lock you out.")
                    .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextSecondary)
            } icon: {
                FAIcon("checkmark.shield.fill").foregroundStyle(Color.privioUnlocked)
            }
        }
    }
}

private struct TrustedDeviceRow: View {
    let device: ProximityDeviceInfo
    let threshold: Int
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void
    let setActive: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        let dim = isActive ? 1.0 : 0.45
        return HStack(spacing: 12) {
            FAIcon(symbol, size: 17).foregroundStyle(Color.privioPrimary)
                .frame(width: 28).opacity(dim)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.privioSystem(size: 13.5, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
                Text(status).font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
            }.opacity(dim)
            Spacer()
            if distanceUnavailable {
                DeviceActivityStatusView(isActive: isActive && device.isConnected)
                    .frame(width: 26, height: 18).opacity(dim)
            } else {
                SignalStrengthView(rssi: isActive && device.isConnected ? device.rssi : nil, threshold: threshold)
                    .frame(width: 26, height: 18).opacity(dim)
            }
            Toggle("", isOn: Binding(get: { isActive }, set: { setActive($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.privioPrimary)
            FAIcon("chevron.right", size: 11)
                .foregroundStyle(Color.privioTextTertiary).opacity(dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.privioSurfaceSelected : (hovering ? Color.privioSurfaceSelected.opacity(0.5) : Color.privioSurface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.privioPrimary.opacity(0.5) : Color.privioSeparator,
                              lineWidth: isSelected ? 1.5 : 1)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { select() }
        .onHover { hovering = $0 }
    }

    private var status: String {
        if !isActive { return String(localized: "Disabled") }
        if distanceUnavailable {
            return String(localized: device.isConnected ? "Active" : "Inactive")
        }
        guard device.isConnected else { return String(localized: "No current signal") }
        guard let rssi = device.rssi else { return String(localized: "Connected") }
        let range = rssi >= threshold ? String(localized: "In range") : String(localized: "Out of range")
        return "\(range) · \(rssi) dBm"
    }

    private var distanceUnavailable: Bool {
        !device.id.hasPrefix("ble:privio:") && device.rssi == nil
    }

    private var symbol: String {
        switch device.kind {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

private enum PrivioCompanionApp: String, CaseIterable, Identifiable {
    case wearOS, watchOS, android, iOS

    var id: String { rawValue }
    var productName: LocalizedStringKey {
        switch self {
        case .wearOS, .watchOS: return "PrivioWear"
        case .android, .iOS: return "PrivioMobile"
        }
    }
    var platformName: LocalizedStringKey {
        switch self {
        case .wearOS: return "Wear OS watches"
        case .watchOS: return "Apple Watch"
        case .android: return "Android phones"
        case .iOS: return "iPhone"
        }
    }
    var symbol: String {
        switch self {
        case .wearOS: return "watch.analog"
        case .watchOS: return "applewatch"
        case .android: return "apps.iphone"
        case .iOS: return "iphone"
        }
    }
    var storeName: LocalizedStringKey {
        switch self {
        case .wearOS, .android: return "Google Play"
        case .watchOS, .iOS: return "App Store"
        }
    }
    var downloadURL: URL {
        switch self {
        case .wearOS:
            return URL(string: "https://play.google.com/store/search?q=PrivioWear&c=apps")!
        case .watchOS:
            return URL(string: "https://apps.apple.com/pl/search?term=PrivioWear")!
        case .android:
            return URL(string: "https://play.google.com/store/search?q=PrivioMobile&c=apps")!
        case .iOS:
            return URL(string: "https://apps.apple.com/pl/search?term=PrivioMobile")!
        }
    }
}

private struct PrivioDownloadQRCode: View {
    let value: String
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
            } else {
                FAIcon("qrcode", size: 120)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var image: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = Self.context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct AddProximityDeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(ProximityController.self) private var proximity
    @Environment(\.dismiss) private var dismiss
    @State private var discoveredIDs: [String] = []
    @State private var showingQRScanner = false
    @State private var showingManualPairing = false
    @State private var manualCode = ""
    @State private var pairingError: String?
    @State private var cameraDenied = false
    @State private var cameraStatus = ""
    @State private var showsCompanionApps = false

    private var availableDevices: [ProximityDeviceInfo] {
        discoveredIDs
            .filter { !model.proximityConfig.trustedDeviceIDs.contains($0) }
            .map { proximity.deviceInfo(for: $0) }
    }
    private var privioDevices: [ProximityDeviceInfo] { availableDevices.filter { $0.id.hasPrefix("ble:privio:") } }
    private var pairedDevices: [ProximityDeviceInfo] { availableDevices.filter { !$0.id.hasPrefix("ble:") } }
    private var nearbyDevices: [ProximityDeviceInfo] {
        availableDevices.filter { $0.id.hasPrefix("ble:") && !$0.id.hasPrefix("ble:privio:") }
    }

    var body: some View {
        PrivioModal(title: "Add Device",
                    subtitle: "Choose a nearby or paired Bluetooth device.",
                    width: 520, height: 470) {
          Group {
            if proximity.bluetoothDenied {
                VStack(spacing: 12) {
                    FAIcon("exclamationmark.triangle.fill", size: 30).foregroundStyle(.orange)
                    Text("Bluetooth access is off").font(.privioSystem(size: 14, weight: .semibold))
                    Text("Allow Bluetooth for Privio in System Settings, then return here.")
                        .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        privioPairingSection
                        if !privioDevices.isEmpty {
                            ForEach(privioDevices) { device in privioDetectedRow(device) }
                        }
                        if !pairedDevices.isEmpty {
                            deviceSectionHeader("Paired with this Mac",
                                                subtitle: "Your devices from macOS Bluetooth settings.")
                                .padding(.top, 8)
                            ForEach(pairedDevices) { device in
                                addDeviceRow(device, paired: true)
                            }
                        }
                        if !nearbyDevices.isEmpty {
                            deviceSectionHeader("Nearby Bluetooth devices",
                                                subtitle: "Not paired - these may belong to people nearby.")
                                .padding(.top, pairedDevices.isEmpty ? 0 : 8)
                            ForEach(nearbyDevices) { device in
                                addDeviceRow(device, paired: false)
                            }
                        }
                        if availableDevices.isEmpty {
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Searching for other Bluetooth devices…")
                                    .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                    }.padding(.bottom, 4)
                }
            }
          }
        } footer: {
            Spacer()
            Button("Done") { dismiss() }.privioPrimaryButton().keyboardShortcut(.defaultAction)
        }
        .onAppear { appendNewDevices(proximity.devices) }
        .onChange(of: proximity.devices.map(\.id)) { _, _ in appendNewDevices(proximity.devices) }
        .sheet(isPresented: $showingQRScanner) {
            VStack(spacing: 14) {
                Text("Scan the QR code on your watch").font(.privioSystem(size: 17, weight: .bold))
                Text("Keep the Privio Beacon QR code inside the camera frame.")
                    .font(.privioSystem(size: 12)).foregroundStyle(Color.privioTextTertiary)
                PrivioQRScannerView(onCode: { pair($0); showingQRScanner = false },
                                    onFailure: { pairingError = $0; showingQRScanner = false },
                                    onCameraDenied: { showingQRScanner = false; cameraDenied = true },
                                    onStatus: { cameraStatus = $0 })
                    .frame(width: 440, height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                if !cameraStatus.isEmpty {
                    Text(cameraStatus)
                        .font(.privioSystem(size: 11)).foregroundStyle(Color.privioTextTertiary)
                }
                HStack {
                    Button("Cancel") { showingQRScanner = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Enter code instead") {
                        showingQRScanner = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            manualCode = ""; showingManualPairing = true
                        }
                    }
                }
            }.padding(22).frame(width: 490).privioSheetCloseButton()
        }
        .sheet(isPresented: $showingManualPairing) {
            PrivioModal(title: "Enter the watch pairing code",
                        subtitle: "Enter the 26-character code shown under the QR code. Hyphens are optional.",
                        width: 460) {
                PrivioModalField {
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX", text: $manualCode)
                        .textFieldStyle(.plain)
                        .font(.privioSystem(size: 14, design: .monospaced))
                }
            } footer: {
                Button("Cancel") { showingManualPairing = false }.privioSecondaryButton()
                Spacer()
                Button("Pair") { pair(manualCode); showingManualPairing = false }
                    .privioPrimaryButton()
                    .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Pairing failed", isPresented: Binding(
            get: { pairingError != nil }, set: { if !$0 { pairingError = nil } }
        )) { Button("OK") { pairingError = nil } } message: { Text(pairingError ?? "") }
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") { openCameraPrivacySettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Privio needs the camera to scan the watch QR code. Turn it on for Privio in System Settings, then scan again. You can also use \u{201E}Enter code\u{201D} instead.")
        }
    }

    private func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private var privioPairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showsCompanionApps.toggle() } } label: {
                HStack(spacing: 12) {
                    ZStack {
                        FAIcon("iphone")
                            .offset(x: -7, y: 2)
                        FAIcon("applewatch")
                            .offset(x: 8, y: -2)
                    }
                    .font(.privioSystem(size: 18, weight: .medium))
                    .foregroundStyle(Color.privioPrimary)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Color.privioPrimary.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair with a Privio companion app")
                            .font(.privioSystem(size: 14, weight: .bold))
                            .foregroundStyle(Color.privioTextPrimary)
                        Text("Use PrivioWear on a watch or PrivioMobile on a phone.")
                            .font(.privioSystem(size: 10.5))
                            .foregroundStyle(Color.privioTextTertiary)
                    }
                    Spacer()
                    Text(showsCompanionApps ? "Hide apps" : "Show apps")
                        .font(.privioSystem(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.privioPrimary)
                    FAIcon("chevron.down", size: 10)
                        .foregroundStyle(Color.privioTextTertiary)
                        .rotationEffect(.degrees(showsCompanionApps ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsCompanionApps {
                Divider().overlay(Color.privioSeparator)
                VStack(spacing: 8) {
                    ForEach(PrivioCompanionApp.allCases) { app in
                        companionAppRow(app)
                    }
                }
                HStack(spacing: 8) {
                    Button { showingQRScanner = true } label: {
                        Label("Scan pairing QR", fa: "qrcode.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.privioPrimary)
                    Button("Enter pairing code") {
                        manualCode = ""
                        showingManualPairing = true
                    }
                    .buttonStyle(.bordered)
                }
                Text("Pairing is currently available for PrivioWear on Wear OS. Other companion apps are interface previews.")
                    .font(.privioSystem(size: 10.5))
                    .foregroundStyle(Color.privioTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.privioPrimary.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.privioPrimary.opacity(0.28))))
    }

    private func companionAppRow(_ app: PrivioCompanionApp) -> some View {
        HStack(spacing: 11) {
            FAIcon(app.symbol, size: 18)
                .foregroundStyle(Color.privioPrimary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.privioPrimary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.productName)
                    .font(.privioSystem(size: 13, weight: .semibold))
                    .foregroundStyle(Color.privioTextPrimary)
                Text(app.platformName)
                    .font(.privioSystem(size: 10.5))
                    .foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Link(destination: app.downloadURL) {
                    HStack(spacing: 4) {
                        Text(app.storeName)
                        FAIcon("arrow.up.right", size: 8)
                    }
                }
                    .font(.privioSystem(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.privioPrimary)
                Text("Coming soon")
                    .font(.privioSystem(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.privioPrimary)
            }
            PrivioDownloadQRCode(value: app.downloadURL.absoluteString)
                .frame(width: 52, height: 52)
                .help("Download QR preview - coming soon")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.privioSurface)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.privioSeparator)))
    }

    private func privioDetectedRow(_ device: ProximityDeviceInfo) -> some View {
        HStack(spacing: 12) {
            FAIcon("applewatch").foregroundStyle(Color.privioPrimary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.privioSystem(size: 13.5, weight: .semibold))
                Text("PrivioWear detected - confirm it using the pairing QR or code above.")
                    .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            Text(device.rssi.map { "\($0) dBm" } ?? "")
                .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
        }.padding(12).background(RoundedRectangle(cornerRadius: 11).fill(Color.privioSurface))
    }

    private func pair(_ text: String) {
        do {
            let pairing = try PrivioBeaconPairingStore.shared.save(pairingText: text)
            model.setProximityConfig { cfg in
                // Jedna aplikacja zegarkowa może dostać nowy sekret po reinstalacji/resetowaniu.
                // Ponowne parowanie zastępuje starszy Privio Watch zamiast zostawiać martwy wpis.
                let stale = cfg.trustedDeviceIDs.filter {
                    $0.hasPrefix("ble:privio:") && $0 != pairing.deviceID
                }
                stale.forEach { PrivioBeaconPairingStore.shared.remove(deviceID: $0) }
                cfg.trustedDeviceIDs.removeAll { stale.contains($0) }
                guard cfg.trustedDeviceIDs.count < ProximityConfig.maxTrustedDevices else {
                    pairingError = String(localized: "Remove another trusted device before pairing this watch.")
                    return
                }
                if !cfg.trustedDeviceIDs.contains(pairing.deviceID) { cfg.trustedDeviceIDs.append(pairing.deviceID) }
            }
            if pairingError == nil { dismiss() }
        } catch {
            pairingError = error.localizedDescription
        }
    }

    private func add(_ device: ProximityDeviceInfo) {
        model.setProximityConfig { cfg in
            guard cfg.trustedDeviceIDs.count < ProximityConfig.maxTrustedDevices,
                  !cfg.trustedDeviceIDs.contains(device.id) else { return }
            cfg.trustedDeviceIDs.append(device.id)
        }
        if model.proximityConfig.trustedDeviceIDs.count >= ProximityConfig.maxTrustedDevices { dismiss() }
    }

    private func appendNewDevices(_ devices: [ProximityDeviceInfo]) {
        let existing = Set(discoveredIDs)
        discoveredIDs.append(contentsOf: devices.map(\.id).filter { !existing.contains($0) })
    }

    private func deviceSectionHeader(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.privioSystem(size: 13, weight: .semibold)).foregroundStyle(Color.privioTextPrimary)
            Text(subtitle).font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
        }
    }

    /// Ikona wg typu urządzenia (słuchawki/mysz/klawiatura/telefon/zegarek), a nie
    /// generyczny łańcuszek - spójnie z listą zaufanych urządzeń.
    private static func kindSymbol(_ kind: ProximityDeviceKind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    private func addDeviceRow(_ device: ProximityDeviceInfo, paired: Bool) -> some View {
        HStack(spacing: 12) {
            FAIcon(Self.kindSymbol(device.kind))
                .foregroundStyle(paired ? Color.privioUnlocked : Color.privioPrimary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(device.name).font(.privioSystem(size: 13.5, weight: .semibold))
                    if paired {
                        Text("Paired").font(.privioSystem(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.privioUnlocked)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.privioUnlocked.opacity(0.12)))
                    }
                }
                Text(device.rssi.map { "\($0) dBm" } ?? String(localized: "Signal unavailable"))
                    .font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
                if let code = BLEProximityScanner.formattedPairingCode(fromDeviceID: device.id) {
                    Text("Pairing code: \(code)")
                        .font(.privioSystem(size: 10.5, weight: .medium).monospaced())
                        .foregroundStyle(Color.privioPrimary)
                }
            }
            Spacer()
            Button("Add") { add(device) }.buttonStyle(.borderedProminent).tint(.privioPrimary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.privioSurface)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.privioSeparator)))
    }

    private func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Wiersz pojedynczego urządzenia: ikona rodzaju, nazwa, stan, RSSI, bateria + zaufanie.
private struct DeviceRow: View {
    let device: ProximityDeviceInfo
    let threshold: Int
    let isTrusted: Bool
    let canTrustMore: Bool
    let setTrusted: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            FAIcon(symbol, size: 17)
                .foregroundStyle(device.isConnected ? Color.privioPrimary : Color.privioTextTertiary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.privioSystem(size: 13.5)).foregroundStyle(Color.privioTextPrimary)
                Text(subtitle).font(.privioSystem(size: 10.5)).foregroundStyle(Color.privioTextTertiary)
            }
            Spacer()
            if distanceUnavailable {
                DeviceActivityStatusView(isActive: device.isConnected)
                    .frame(width: 26, height: 18)
            } else {
                SignalStrengthView(rssi: device.isConnected ? device.rssi : nil, threshold: threshold)
                    .frame(width: 26, height: 18)
            }
            batteryView
                .frame(width: 46, alignment: .trailing)
            Toggle("", isOn: Binding(get: { isTrusted }, set: setTrusted))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.privioPrimary)
                .disabled(!isTrusted && !canTrustMore)
        }
        .padding(.vertical, 9)
    }

    private var symbol: String {
        switch device.kind {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    private var subtitle: String {
        if distanceUnavailable {
            return String(localized: device.isConnected ? "Active" : "Inactive")
        }
        if !device.isConnected { return NSLocalizedString("No current signal", comment: "BT device state") }
        if let rssi = device.rssi {
            let inRange = rssi >= threshold
                ? NSLocalizedString("In range", comment: "BT range")
                : NSLocalizedString("Out of range", comment: "BT range")
            return "\(inRange) · \(rssi) dBm"
        }
        return NSLocalizedString("Connected", comment: "BT device state")
    }

    private var distanceUnavailable: Bool {
        !device.id.hasPrefix("ble:privio:") && device.rssi == nil
    }

    @ViewBuilder private var batteryView: some View {
        if let battery = device.batteryPercent {
            HStack(spacing: 3) {
                FAIcon(batterySymbol(battery))
                    .foregroundStyle(battery <= 15 ? Color.orange : Color.privioTextSecondary)
                Text("\(battery)%").font(.privioSystem(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.privioTextSecondary)
            }
        } else {
            Text("-").font(.privioSystem(size: 11)).foregroundStyle(Color.privioTextTertiary)
        }
    }

    private func batterySymbol(_ p: Int) -> String {
        switch p {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Stan urządzenia, którego odległości macOS nie potrafi zmierzyć. Taki sprzęt
/// pokazujemy binarnie: zielony = połączony/aktywny, szary = nieaktywny.
private struct DeviceActivityStatusView: View {
    let isActive: Bool
    var showsLabel = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? Color.privioUnlocked : Color.privioTextTertiary.opacity(0.38))
                .frame(width: 9, height: 9)
            if showsLabel {
                Text(isActive ? "Active" : "Inactive")
                    .font(.privioSystem(size: 12))
                    .foregroundStyle(Color.privioTextSecondary)
            }
        }
    }
}

/// Cztery słupki siły sygnału na podstawie RSSI, z progiem „w zasięgu".
private struct SignalStrengthView: View {
    let rssi: Int?
    let threshold: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? barColor : Color.privioTextTertiary.opacity(0.25))
                    .frame(width: 4, height: 6 + CGFloat(i) * 4)
            }
        }
    }

    private var bars: Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 4
        case (-67)..<(-55): return 3
        case (-78)..<(-67): return 2
        default: return 1
        }
    }

    private var barColor: Color {
        guard let rssi else { return Color.privioTextTertiary.opacity(0.25) }
        return rssi >= threshold ? Color.privioUnlocked : Color.orange
    }
}
