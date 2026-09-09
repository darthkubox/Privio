import SwiftUI
import PrivioCore

/// Widok umów/licencji. Przełącza między wszystkimi dokumentami (EULA, licencja kodu)
/// oraz językami. Dwa tryby:
/// - `requireAcceptance == true` → pierwszy start: Accept / Decline & Quit (bez zamknięcia bez decyzji),
/// - `requireAcceptance == false` → podgląd z About: Close.
struct LicenseAgreementView: View {
    var requireAcceptance: Bool
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}
    /// Dokument otwarty na starcie (domyślnie pierwszy - EULA).
    var startDocumentID: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var lang = LicenseAgreement.defaultLang
    @State private var doc: LicenseAgreement.Document

    init(requireAcceptance: Bool,
         onAccept: @escaping () -> Void = {},
         onDecline: @escaping () -> Void = {},
         startDocumentID: String? = nil) {
        self.requireAcceptance = requireAcceptance
        self.onAccept = onAccept
        self.onDecline = onDecline
        self.startDocumentID = startDocumentID
        let start = LicenseAgreement.documents.first { $0.id == startDocumentID }
            ?? LicenseAgreement.documents[0]
        _doc = State(initialValue: start)
    }

    /// Język faktycznie użyty (gdy wybrany brakuje w tym dokumencie - pierwszy dostępny).
    private var effectiveLang: LicenseAgreement.Lang {
        doc.languages.contains(lang) ? lang : (doc.languages.first ?? lang)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PrivioLogo().frame(width: 20, height: 25)
                Text(LicenseAgreement.title(for: lang))
                    .font(.privioSystem(size: 15, weight: .bold))
                    .foregroundStyle(Color.privioTextPrimary)
                Spacer()
                // Wybór języka - tylko gdy dokument ma więcej niż jeden.
                if doc.languages.count > 1 {
                    Picker("Language", selection: $lang) {
                        ForEach(doc.languages) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .tint(Color.privioTextPrimary)
                    .fixedSize()
                    .accessibilityLabel("Language")
                } else if let only = doc.languages.first {
                    Text(only.title)
                        .font(.privioSystem(size: 11, weight: .medium))
                        .foregroundStyle(Color.privioTextSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.privioSeparator.opacity(0.5)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().overlay(Color.privioSeparator)

            HStack(spacing: 0) {
                documentNavigation

                Divider().overlay(Color.privioSeparator)

                VStack(spacing: 0) {
                    documentHeader

                    Divider().overlay(Color.privioSeparator)

                    ScrollView {
                        MarkdownDocumentView(markdown: LicenseAgreement.text(for: doc, lang: effectiveLang))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 24)
                    }
                    .id(doc.id + effectiveLang.rawValue)
                    .environment(\.openURL, OpenURLAction { url in
                        openDocumentLink(url)
                    })
                }
            }

            Divider().overlay(Color.privioSeparator)

            HStack {
                if requireAcceptance {
                    Button(action: onDecline) {
                        Text("Decline & Quit")
                            .font(.privioSystem(size: 13, weight: .medium))
                            .foregroundStyle(Color.privioDanger)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.privioSystem(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PrivioGradient.brand))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 900, height: 700)
        .background(Color.privioBackground)
        .interactiveDismissDisabled(requireAcceptance)
    }

    private func openDocumentLink(_ url: URL) -> OpenURLAction.Result {
        if let destination = LicenseAgreement.destination(for: url, currentLang: effectiveLang) {
            lang = destination.language
            withAnimation(.easeOut(duration: 0.14)) {
                doc = destination.document
            }
            return .handled
        }

        switch url.scheme?.lowercased() {
        case "https", "http", "mailto":
            return .systemAction
        default:
            // Nie przekazuj nierozpoznanych względnych ścieżek do Findera.
            // Zapobiega to alertowi „Nie można otworzyć aplikacji. -50”.
            return .discarded
        }
    }

    private var documentNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lang == .pl ? "DOKUMENTY" : "DOCUMENTS")
                .font(.privioSystem(size: 10.5, weight: .bold))
                .foregroundStyle(Color.privioTextSecondary)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(LicenseAgreement.documents) { document in
                        documentButton(document)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 248)
        .background(Color.privioBackgroundRaised.opacity(0.58))
    }

    private func documentButton(_ document: LicenseAgreement.Document) -> some View {
        let selected = doc == document
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { doc = document }
        } label: {
            HStack(spacing: 11) {
                FAIcon(document.symbol, size: 13)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.white : Color.privioPrimary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title(for: lang))
                        .font(.privioSystem(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.privioTextPrimary)
                        .lineLimit(1)

                    Text(document.subtitle(for: lang))
                        .font(.privioSystem(size: 9.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.76) : Color.privioTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.privioPrimary : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(document.title(for: lang))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(doc.title(for: lang))
                .font(.privioSystem(size: 17, weight: .bold))
                .foregroundStyle(Color.privioTextPrimary)
            Text(doc.subtitle(for: lang))
                .font(.privioSystem(size: 11.5))
                .foregroundStyle(Color.privioTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }
}

/// Lekki renderer dokumentów prawnych. Obsługuje strukturę używaną w naszych
/// plikach Markdown (nagłówki, akapity, listy, cytaty, tabele i separatory), dzięki czemu
/// użytkownik nie ogląda surowych znaczników `#`, `**` i `>`.
private struct MarkdownDocumentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(markdown) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(.privioSystem(size: level == 1 ? 22 : level == 2 ? 17 : 14,
                              weight: level <= 2 ? .bold : .semibold))
                .foregroundStyle(Color.privioTextPrimary)
                .padding(.top, level == 1 ? 2 : 10)
                .padding(.bottom, level == 1 ? 4 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            inlineText(text)
                .font(.privioSystem(size: 13))
                .foregroundStyle(Color.privioTextSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color.privioPrimary)
                    .frame(width: 5, height: 5)
                inlineText(text)
                    .font(.privioSystem(size: 13))
                    .foregroundStyle(Color.privioTextSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case let .quote(text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.privioPrimary)
                    .frame(width: 3)
                inlineText(text)
                    .font(.privioSystem(size: 12.5))
                    .foregroundStyle(Color.privioTextSecondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.privioSurface)
            )

        case let .table(headers, rows):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(header.uppercased())
                                    .font(.privioSystem(size: 9, weight: .bold))
                                    .foregroundStyle(Color.privioTextSecondary)
                                    .tracking(0.5)
                                inlineText(index < row.count ? row[index] : "")
                                    .font(.privioSystem(size: index == 0 ? 12.5 : 12,
                                                  weight: index == 0 ? .semibold : .regular))
                                    .foregroundStyle(index == 0 ? Color.privioTextPrimary : Color.privioTextSecondary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if index < headers.count - 1 {
                                Divider().overlay(Color.privioSeparator.opacity(0.75))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.privioSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.privioSeparator, lineWidth: 1)
                    )
                }
            }

        case .divider:
            Divider().overlay(Color.privioSeparator).padding(.vertical, 4)
        }
    }

    private func inlineText(_ markdown: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
        return Text(attributed)
    }
}

private enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case quote(String)
    case table([String], [[String]])
    case divider

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var bullet: [String] = []
        var table: [[String]] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        func flushQuote() {
            guard !quote.isEmpty else { return }
            result.append(.quote(quote.joined(separator: " ")))
            quote.removeAll()
        }

        func flushBullet() {
            guard !bullet.isEmpty else { return }
            result.append(.bullet(bullet.joined(separator: " ")))
            bullet.removeAll()
        }

        func flushTable() {
            guard !table.isEmpty else { return }
            if table.count >= 2, isTableSeparator(table[1]) {
                result.append(.table(table[0], Array(table.dropFirst(2))))
            } else {
                result.append(.table(table[0], Array(table.dropFirst())))
            }
            table.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("|"), line.hasSuffix("|") {
                flushParagraph(); flushQuote(); flushBullet()
                table.append(parseTableRow(line))
                continue
            } else {
                flushTable()
            }

            if line.isEmpty {
                flushParagraph()
                flushQuote()
                flushBullet()
                continue
            }

            if line == "---" || line == "***" {
                flushParagraph(); flushQuote(); flushBullet()
                result.append(.divider)
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                flushBullet()
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            } else {
                flushQuote()
            }

            let hashes = line.prefix { $0 == "#" }.count
            if hashes > 0, hashes <= 6, line.dropFirst(hashes).first == " " {
                flushParagraph()
                flushBullet()
                result.append(.heading(hashes, String(line.dropFirst(hashes + 1))))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushParagraph()
                flushBullet()
                bullet.append(String(line.dropFirst(2)))
                continue
            }

            if bullet.isEmpty {
                paragraph.append(line)
            } else {
                bullet.append(line)
            }
        }

        flushParagraph()
        flushQuote()
        flushBullet()
        flushTable()
        return result
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ row: [String]) -> Bool {
        !row.isEmpty && row.allSatisfy { cell in
            let marker = cell.replacingOccurrences(of: ":", with: "")
            return marker.count >= 3 && marker.allSatisfy { $0 == "-" }
        }
    }
}
