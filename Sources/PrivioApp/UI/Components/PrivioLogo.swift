import SwiftUI

/// Znak Privio: litera „P" zbudowana z linii papilarnych (sekcja 22).
///
/// Rysowany wektorowo w `Canvas` - ostry w każdej skali (od 16 px ikony menu bar
/// po pełną ikonę aplikacji). Parametry (`ridgeCount`, grubości, kąty) są zebrane
/// na górze, by łatwo dostroić proporcje. Kolor przez `tint` (domyślnie gradient
/// marki); dla wariantu monochromatycznego / template menu bar podajemy jeden kolor.
struct PrivioLogo: View {
    enum Fill {
        case gradient
        case solid(Color)
    }

    var fill: Fill = .gradient
    /// Grubość linii względem szerokości (0-1). Domyślnie wg projektu (12/312).
    var lineWidthRatio: CGFloat = PrivioLogoGeometry.designLineWidthRatio

    var body: some View {
        Canvas { context, size in
            let shape = PrivioLogoGeometry.path(in: size, lineWidthRatio: lineWidthRatio)
            let style = StrokeStyle(lineWidth: size.width * lineWidthRatio,
                                    lineCap: .round, lineJoin: .round)
            switch fill {
            case .gradient:
                context.stroke(shape, with: .linearGradient(
                    Gradient(colors: [Color.privioBright, Color.privioPrimary]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)),
                    style: style)
            case .solid(let color):
                context.stroke(shape, with: .color(color), style: style)
            }
        }
        .aspectRatio(PrivioLogoGeometry.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Uproszczony wariant znaku przeznaczony do bardzo małych rozmiarów.
struct PrivioSmallLogo: View {
    var fill: PrivioLogo.Fill = .gradient

    var body: some View {
        Canvas { context, size in
            let shape = PrivioSmallLogoGeometry.path(in: size)
            let style = StrokeStyle(
                lineWidth: size.width * PrivioSmallLogoGeometry.designLineWidthRatio,
                lineCap: .round,
                lineJoin: .round
            )
            switch fill {
            case .gradient:
                context.stroke(shape, with: .linearGradient(
                    Gradient(colors: [Color.privioBright, Color.privioPrimary]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                ), style: style)
            case .solid(let color):
                context.stroke(shape, with: .color(color), style: style)
            }
        }
        .aspectRatio(PrivioSmallLogoGeometry.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Geometria znaku = dokładna ścieżka z `logo_privio.svg` (projekt użytkownika),
/// parsowana raz i skalowana do żądanego rozmiaru. Ten sam kształt w aplikacji
/// (recolorowalny stroke) i w generatorze ikon.
enum PrivioLogoGeometry {
    /// viewBox znaku (z SVG) i wynikające proporcje / grubość linii.
    static let viewBox = CGSize(width: 312, height: 400)
    static let aspect: CGFloat = 312.0 / 400.0
    static let designLineWidthRatio: CGFloat = 12.0 / 312.0

    /// Ścieżka w układzie viewBox (parsowana raz z zasobu w bundlu).
    private static let nativePath: Path = {
        guard let url = Bundle.main.url(forResource: "logo_privio", withExtension: "svg"),
              let svg = try? String(contentsOf: url, encoding: .utf8) else {
            return Path()
        }
        return SVGPath.combinedPath(fromSVG: svg)
    }()

    static func path(in size: CGSize, lineWidthRatio: CGFloat = designLineWidthRatio) -> Path {
        let transform = CGAffineTransform(scaleX: size.width / viewBox.width,
                                          y: size.height / viewBox.height)
        return nativePath.applying(transform)
    }
}

enum PrivioSmallLogoGeometry {
    static let viewBox = CGSize(width: 211, height: 310)
    static let aspect: CGFloat = 211.0 / 310.0
    static let designLineWidthRatio: CGFloat = 12.0 / 211.0

    private static let nativePath: Path = {
        guard let url = Bundle.main.url(forResource: "logo_privio_small", withExtension: "svg"),
              let svg = try? String(contentsOf: url, encoding: .utf8) else {
            return Path()
        }
        return SVGPath.combinedPath(fromSVG: svg)
    }()

    static func path(in size: CGSize) -> Path {
        nativePath.applying(CGAffineTransform(
            scaleX: size.width / viewBox.width,
            y: size.height / viewBox.height
        ))
    }
}

#if DEBUG
#Preview("Logo") {
    HStack(spacing: 24) {
        PrivioLogo().frame(width: 120, height: 150)
        PrivioLogo(fill: .solid(.privioPrimary)).frame(width: 48, height: 60)
        PrivioLogo(fill: .solid(.privioTextPrimary)).frame(width: 20, height: 25)
    }
    .padding(40)
    .background(Color.privioBackground)
}
#endif
