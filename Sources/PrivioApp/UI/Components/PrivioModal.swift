import SwiftUI
import AppKit

/// Wspólny szkielet arkusza (modala) - jedno miejsce definiujące styl, paddingi,
/// gapy, nagłówek, stopkę i przyciski kontrolne (kropki), żeby KAŻDY modal miał
/// identyczny padding wokół treści (także nowe).
///
/// To szkielet narzuca padding treści (poziomy `PrivioModalMetrics.padding`, odstęp
/// nagłówek→treść i treść→stopka = `PrivioModalMetrics.gap`) - wołający **nie** dodaje
/// własnych marginesów wokół treści. Dla list po prostu podaj `height` i wstaw
/// `ScrollView` jako treść; wiersze dziedziczą ten sam padding poziomy co nagłówek.
///
/// Użycie:
/// ```
/// PrivioModal(title: "Tytuł", subtitle: "Opis", width: 460) {
///     // treść (bez własnych marginesów zewnętrznych)
/// } footer: {
///     Button("Anuluj") { … }.privioSecondaryButton()
///     Spacer()
///     Button("OK") { … }.privioPrimaryButton()
/// }
/// ```
struct PrivioModal<ModalContent: View, Footer: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var width: CGFloat = 460
    var height: CGFloat?
    @ViewBuilder var content: () -> ModalContent
    @ViewBuilder var footer: () -> Footer

    /// Zmierzona naturalna wysokość treści - pozwala scrollować treść dłuższą niż ekran,
    /// a krótszą pokazać bez pustego miejsca (bez tego `ScrollView` byłby zachłanny).
    @State private var measuredContentHeight: CGFloat = 0

    /// Górny limit wysokości treści: nie więcej niż widoczny ekran (miejsce na nagłówek,
    /// stopkę, pasek okna i marginesy). Dzięki temu żaden modal nie wychodzi poza ekran.
    private var maxContentHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, screen - 260)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            scrollableContent
            footerBar
        }
        .privioSheetCloseButton()
        // macOS wymusza min. szerokość arkusza (~528pt). Sztywne `.frame(width:)`
        // węższe niż to centrowało modal, przez co TREŚĆ dostawała większy margines
        // niż kropki. `idealWidth` + `maxWidth: .infinity` sprawia, że modal WYPEŁNIA
        // arkusz (docelowo `width`, a jeśli arkusz jest szerszy - całą szerokość),
        // więc treść i kropki mają wspólny margines 24 z każdej strony.
        .frame(idealWidth: width, maxWidth: .infinity)
    }

    /// Treść w `ScrollView`, ograniczona do zmierzonej wysokości (maks. `maxContentHeight`
    /// lub jawne `height`). Krótsze modale zajmują tyle, ile trzeba; dłuższe scrollują.
    private var scrollableContent: some View {
        let target = height ?? min(measuredContentHeight, maxContentHeight)
        return ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PrivioModalMetrics.padding)
                .padding(.bottom, PrivioModalMetrics.gap)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: PrivioModalHeightKey.self, value: geo.size.height)
                })
        }
        .frame(height: target > 0 ? target : nil)
        .onPreferenceChange(PrivioModalHeightKey.self) { measuredContentHeight = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.privioSystem(size: 20, weight: .bold))
                .foregroundStyle(Color.privioTextPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.privioSystem(size: 13))
                    .foregroundStyle(Color.privioTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PrivioModalMetrics.padding)
        .padding(.top, PrivioModalMetrics.headerTop)
        .padding(.bottom, PrivioModalMetrics.gap)
    }

    private var footerBar: some View {
        HStack(spacing: 12) { footer() }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PrivioModalMetrics.padding)
            .padding(.bottom, PrivioModalMetrics.padding)
    }
}

/// Pomiar naturalnej wysokości treści modala (do warunkowego scrollowania).
private struct PrivioModalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Wspólne wymiary modali - jedno źródło prawdy.
enum PrivioModalMetrics {
    static let padding: CGFloat = 24   // jednolita ramka: boki + dół stopki + inset kropek (lewy)
    static let gap: CGFloat = 20       // odstęp nagłówek→treść oraz treść→stopka
    static let headerTop: CGFloat = 24 // odstęp kropki→tytuł = pełne 24 (kropki w rogu 24/24)
}

/// Jednolite pole wpisywania w modalach - ten sam wygląd „surface" (wysokość,
/// zaokrąglenie, obramowanie) dla KAŻDEGO pola tekstowego w arkuszach, zamiast
/// mieszać natywny `.roundedBorder` z własnym tłem. Do środka podaj `TextField`/
/// `SecureField` ze stylem `.textFieldStyle(.plain)`; opcjonalna ikona wiodąca
/// (nazwa jak dla `FAIcon`) pojawia się po lewej.
struct PrivioModalField<Field: View>: View {
    var icon: String?
    @ViewBuilder var field: () -> Field

    init(icon: String? = nil, @ViewBuilder field: @escaping () -> Field) {
        self.icon = icon
        self.field = field
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                FAIcon(icon).foregroundStyle(Color.privioTextTertiary)
            }
            field()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.privioSurface)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.privioSeparator))
        )
    }
}

extension View {
    /// Główny przycisk akcji modala (prawa strona stopki).
    func privioPrimaryButton() -> some View {
        buttonStyle(.borderedProminent).tint(.privioPrimary)
    }

    /// Drugorzędny przycisk/link modala (lewa strona stopki: Anuluj, Kopiuj, itp.).
    func privioSecondaryButton() -> some View {
        buttonStyle(.plain)
            .font(.privioSystem(size: 13))
            .foregroundStyle(Color.privioTextSecondary)
    }
}
