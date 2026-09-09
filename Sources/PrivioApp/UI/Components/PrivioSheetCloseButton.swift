import SwiftUI
import AppKit

/// Pasek kontrolek modalnego arkusza w stylu macOS. Arkusz nie jest osobnym
/// oknem, dlatego żółta kontrolka minimalizuje jego najwyższe okno nadrzędne.
struct PrivioSheetWindowControls: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            trafficLight(color: Color(nsColor: .systemRed), symbol: "xmark") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")

            trafficLight(color: Color(nsColor: .systemYellow), symbol: "minus") {
                minimizeOwningWindow()
            }
            .help("Minimize")
            .accessibilityLabel("Minimize")
        }
        .onHover { isHovering = $0 }
    }

    private func trafficLight(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 13, height: 13)
                Circle().strokeBorder(.black.opacity(0.16), lineWidth: 0.5).frame(width: 13, height: 13)
                if isHovering {
                    FAIcon(symbol, size: 7)
                        .foregroundStyle(.black.opacity(0.68))
                }
            }
            .frame(width: 15, height: 15)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func minimizeOwningWindow() {
        var window = NSApp.keyWindow
        while let parent = window?.sheetParent { window = parent }
        window?.miniaturize(nil)
    }
}

extension View {
    /// `top`/`leading` = inset kropek od górnej/lewej krawędzi okna. Lewa krawędź
    /// (24) jest równa poziomemu paddingowi treści modala, więc kropki i tytuł/pola
    /// mają wspólną linię lewego marginesu - jednolita ramka ze wszystkich stron.
    func privioSheetCloseButton(top: CGFloat = PrivioModalMetrics.padding, leading: CGFloat = PrivioModalMetrics.padding) -> some View {
        VStack(spacing: 0) {
            HStack {
                PrivioSheetWindowControls()
                Spacer(minLength: 0)
            }
            .padding(.top, top)
            .padding(.horizontal, leading)

            self
        }
        .background(Color.privioBackground)
    }
}
