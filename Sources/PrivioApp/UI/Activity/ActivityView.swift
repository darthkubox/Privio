import SwiftUI
import PrivioCore

/// Lokalna, prywatna historia zdarzeń (sekcja 19). Bez treści apek, bez chmury.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedPhoto: ActivityPhotoPreview?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.privioSystem(size: 24, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
                Button(role: .destructive) { model.clearActivity() } label: {
                    Text("Clear History")
                        .font(.privioSystem(size: 13, weight: .medium))
                        .foregroundStyle(Color.privioDanger)
                }
                .buttonStyle(.plain)
                .disabled(model.state.recentActivity.isEmpty)
            }
            .padding(.horizontal, PrivioLayout.pagePadding)
            .padding(.top, PrivioLayout.headerTop)
            .padding(.bottom, PrivioLayout.headerBottom)

            Divider().overlay(Color.privioSeparator)

            if model.state.recentActivity.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    FAIcon("clock.badge.questionmark", size: 36)
                        .foregroundStyle(Color.privioTextTertiary)
                    Text("No activity yet")
                        .font(.privioSystem(size: 14))
                        .foregroundStyle(Color.privioTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: PrivioLayout.rowSpacing) {
                        ForEach(model.state.recentActivity) { event in
                            ActivityRow(event: event,
                                        photoURL: model.failedAttemptPhotoURL(for: event),
                                        onOpenPhoto: { url in selectedPhoto = ActivityPhotoPreview(url: url) })
                        }
                    }
                    .padding(PrivioLayout.pagePadding)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { model.markActivitySeen() }
        .sheet(item: $selectedPhoto) { preview in
            FailedAttemptPhotoPreview(url: preview.url)
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent
    let photoURL: URL?
    let onOpenPhoto: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            FAIcon(event.symbolName, size: 14)
                .foregroundStyle(event.kind == .authFailed ? Color.privioDanger : Color.privioPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill((event.kind == .authFailed ? Color.privioDanger : Color.privioPrimary).opacity(0.12)))
            Text(event.summary)
                .font(.privioSystem(size: 13.5))
                .foregroundStyle(Color.privioTextPrimary)
            Spacer()
            if let photoURL, let image = NSImage(contentsOf: photoURL) {
                Button { onOpenPhoto(photoURL) } label: {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Open photo")
            }
            Text(event.date, format: .dateTime.hour().minute())
                .font(.privioSystem(size: 12))
                .foregroundStyle(Color.privioTextTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.privioSurface)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(event.kind == .authFailed ? Color.privioDanger.opacity(0.55) : Color.privioSeparator,
                                  lineWidth: event.kind == .authFailed ? 1.5 : 1))
        )
    }
}

private struct ActivityPhotoPreview: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct FailedAttemptPhotoPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PrivioModal(title: "Failed authentication photo", width: 720) {
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 620)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ContentUnavailableView {
                        Label { Text("Photo unavailable") } icon: { FAIcon("photo.badge.exclamationmark") }
                    }
                }
            }
        } footer: {
            Spacer()
            Button("Close photo") { dismiss() }.privioPrimaryButton()
        }
    }
}
