import SwiftUI

/// „Schedules" jest w projekcie graficznym, ale nie ma go w zakresie specyfikacji.
/// FAZA 1: uczciwy placeholder (nie udajemy funkcji, której nie ma). Ewentualne
/// harmonogramy blokad to kandydat na przyszłą fazę.
struct SchedulesView: View {
    var body: some View {
        VStack(spacing: 12) {
            FAIcon("calendar.badge.clock", size: 44)
                .foregroundStyle(Color.privioPrimary)
            Text("Schedules")
                .font(.privioSystem(size: 20, weight: .semibold))
                .foregroundStyle(Color.privioTextPrimary)
            Text("Time-based locking rules are planned for a future version.")
                .font(.privioSystem(size: 13))
                .foregroundStyle(Color.privioTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.privioBackground)
    }
}
