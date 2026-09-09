import SwiftUI

/// Semantyczne kolory Privio z katalogu assetów (light + dark).
/// Nie hardkodujemy kolorów w widokach (sekcja 21) - wszystko przez te nazwy.
extension Color {
    static let privioPrimary          = Color("PrivioPrimary")
    static let privioBright           = Color("PrivioBright")
    static let privioDeep             = Color("PrivioDeep")
    static let privioBackground       = Color("PrivioBackground")
    static let privioBackgroundRaised = Color("PrivioBackgroundRaised")
    static let privioSurface          = Color("PrivioSurface")
    static let privioSurfaceSelected  = Color("PrivioSurfaceSelected")
    static let privioSeparator        = Color("PrivioSeparator")
    static let privioTextPrimary      = Color("PrivioTextPrimary")
    static let privioTextSecondary    = Color("PrivioTextSecondary")
    static let privioTextTertiary     = Color("PrivioTextTertiary")
    static let privioUnlocked         = Color("PrivioUnlocked")
    static let privioLockedTint       = Color("PrivioLockedTint")
    static let privioDanger           = Color("PrivioDanger")
    static let privioIconTop          = Color("PrivioIconTop")
    static let privioIconBottom       = Color("PrivioIconBottom")
    static let privioAuthCardTop      = Color("PrivioAuthCardTop")
    static let privioAuthCardBottom   = Color("PrivioAuthCardBottom")
}

/// Gradienty wielokrotnego użytku.
enum PrivioGradient {
    /// Niebieski gradient znaku logo / ikony.
    static let brand = LinearGradient(
        colors: [.privioBright, .privioPrimary],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Ciemna, granatowa karta okna uwierzytelnienia (jak w mockupie).
    static let authCard = LinearGradient(
        colors: [.privioAuthCardTop, .privioAuthCardBottom],
        startPoint: .top, endPoint: .bottom)
}
