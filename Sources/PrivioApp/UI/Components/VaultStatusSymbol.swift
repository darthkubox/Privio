import SwiftUI

/// Własny, jednoznaczny symbol drzwi sejfu. Stan jest pokazany małą kłódką,
/// dzięki czemu ikona nie wygląda jak zwykły folder z plusem lub minusem.
struct VaultStatusSymbol: View {
    enum State {
        case neutral
        case locked
        case unlocked
    }

    var state: State

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let line = max(1, side * 0.075)

            ZStack {
                // Drzwi i rama sejfu.
                RoundedRectangle(cornerRadius: side * 0.17, style: .continuous)
                    .stroke(lineWidth: line)
                    .padding(side * 0.08)

                // Pokrętło z osią i trzema ramionami.
                Circle()
                    .stroke(lineWidth: line)
                    .frame(width: side * 0.34, height: side * 0.34)
                    .offset(x: -side * 0.07)

                Circle()
                    .fill(.foreground)
                    .frame(width: side * 0.09, height: side * 0.09)
                    .offset(x: -side * 0.07)

                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(.foreground)
                        .frame(width: line, height: side * 0.18)
                        .offset(y: -side * 0.13)
                        .rotationEffect(.degrees(Double(index) * 120), anchor: .center)
                        .offset(x: -side * 0.07)
                }

                // Uchwyt drzwi.
                Capsule()
                    .fill(.foreground)
                    .frame(width: line, height: side * 0.28)
                    .offset(x: side * 0.29)

                if state != .neutral {
                    FAIcon(state == .locked ? "lock.fill" : "lock.open.fill", size: side * 0.29)
                        .offset(x: side * 0.27, y: side * 0.28)
                }
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

