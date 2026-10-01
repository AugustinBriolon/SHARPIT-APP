import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The athlete's own MyFitnessPal export, imported once (docs/adr/0010). The app never signs in
/// to MyFitnessPal: the athlete exports their data there and hands SHARPIT the file. The export
/// holds each meal's total, not its foods, so imported days read as meals, read-only.
nonisolated enum MyFitnessPalImport {
    /// The server's limit; checked here too, so a file too large is never uploaded.
    static let maximumBytes = 4 * 1024 * 1024

    /// What `.fileImporter` offers: the ZIP MyFitnessPal mails, or the nutrition CSV inside it.
    static let contentTypes: [UTType] = [.zip, .commaSeparatedText, .plainText]

    /// The file at `url`, read whole, typed by its extension as a browser would.
    static func file(at url: URL) throws -> FoodLogImportFile {
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw FoodLogError.fileTooLarge }
        return FoodLogImportFile(filename: url.lastPathComponent, contentType: contentType(forExtension: url.pathExtension), data: data)
    }

    static func contentType(forExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "zip": "application/zip"
        case "csv": "text/csv"
        default: "text/plain"
        }
    }

    // MARK: Readout

    /// « 412 jours importés, du 3 janv. 2024 au 30 sept. 2026 ».
    static func summary(of result: V1FoodLogImportResult) -> String {
        guard result.importedDays > 0 else { return "Aucun jour à importer dans ce fichier." }
        let count = result.importedDays == 1 ? "1 jour importé" : "\(result.importedDays) jours importés"
        let first = result.firstDay.flatMap(dayLabel)
        let last = result.lastDay.flatMap(dayLabel)
        switch (first, last) {
        case let (first?, last?) where first == last: return "\(count), le \(first)"
        case let (first?, last?): return "\(count), du \(first) au \(last)"
        default: return count
        }
    }

    /// Nil when every line was read.
    static func skippedNote(of result: V1FoodLogImportResult) -> String? {
        switch result.skippedRows {
        case ...0: nil
        case 1: "1 ligne illisible a été ignorée."
        default: "\(result.skippedRows) lignes illisibles ont été ignorées."
        }
    }

    /// What a failed import says: the server's own words when it refused the file.
    static func message(for error: Error) -> String {
        switch error {
        case SharpitAPIError.message(let text): text
        case FoodLogError.fileTooLarge: FoodLogError.fileTooLarge.errorDescription ?? ""
        case let error as SharpitAPIError where error == .rateLimited:
            "Un import vient d'être lancé. Réessaie dans quelques minutes."
        case let error as SharpitAPIError where error == .badRequest:
            "Ce fichier n'est pas un export MyFitnessPal lisible."
        case let error as SharpitAPIError where error == .transport || error == .unauthorized:
            SharpitErrorGuidance.message(for: error, subject: "L'import")
        case is CocoaError:
            "Ce fichier n'a pas pu être lu. Enregistre-le dans Fichiers, puis réessaie."
        default:
            "L'import n'a pas abouti. Réessaie dans un instant."
        }
    }

    /// `2024-01-03` → `3 janv. 2024`. Read in UTC: a training day is a date, not an instant.
    static func dayLabel(_ trainingDayId: String) -> String? {
        let parts = trainingDayId.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        let style = Date.FormatStyle(locale: Locale(identifier: "fr_FR"), calendar: calendar, timeZone: .gmt)
            .day().month(.abbreviated).year()
        return date.formatted(style)
    }
}

/// One import, from the picked file to its result. Never retried: a second upload of the same
/// export would only meet the rate limit.
@MainActor
@Observable
final class MyFitnessPalImportStore {
    enum Phase: Equatable {
        case idle
        case importing
        case imported(V1FoodLogImportResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let client: any FoodLogServing
    private let tokenProvider: () async throws -> String
    private let onImported: @MainActor () async -> Void

    init(
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        onImported: @escaping @MainActor () async -> Void = {}
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.onImported = onImported
    }

    var isImporting: Bool { phase == .importing }

    /// The file picked in Fichiers: read under its security scope, then uploaded.
    func importFile(at url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        let file: FoodLogImportFile
        do {
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            file = try MyFitnessPalImport.file(at: url)
        } catch {
            phase = .failed(MyFitnessPalImport.message(for: error))
            return
        }
        await upload(file)
    }

    func upload(_ file: FoodLogImportFile) async {
        guard !isImporting else { return }
        phase = .importing
        do {
            let result = try await client.importMyFitnessPal(file, token: try await tokenProvider())
            phase = .imported(result)
            if result.importedDays > 0 {
                SharpitHaptics.play(.success)
                await onImported()
            }
        } catch {
            phase = .failed(MyFitnessPalImport.message(for: error))
        }
    }

    func pickerFailed(_ error: Error) {
        phase = .failed(MyFitnessPalImport.message(for: error))
    }
}

/// « Importer depuis MyFitnessPal »: how to get the export, the file picker, then what came in.
struct MyFitnessPalImportSheet: View {
    @State private var store: MyFitnessPalImportStore
    @State private var isPicking = false
    @Environment(\.dismiss) private var dismiss

    init(store: MyFitnessPalImportStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(eyebrow: "Depuis MyFitnessPal") {
                    step(1, "MyFitnessPal Premium : Rapports → Exporter, choisis la période.")
                    step(2, "Tu reçois un e-mail avec un fichier ZIP : enregistre-le dans Fichiers puis importe-le ici.")
                }
                .sharpitListRows()

                Section {
                    Label {
                        Text("Le détail des aliments n'est pas dans l'export : SHARPIT reprend le total de chaque repas, jour par jour.")
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .sharpitListRows()

                outcome
            }
            .sharpitGroupedList()
            .safeAreaInset(edge: .bottom) {
                SharpitActionDock {
                    if case .imported(let result) = store.phase, result.importedDays > 0 {
                        SharpitPrimaryButton(title: "Terminé") { dismiss() }
                    } else {
                        SharpitPrimaryButton(title: store.isImporting ? "Import en cours…" : "Choisir le fichier", isBusy: store.isImporting) {
                            isPicking = true
                        }
                        .disabled(store.isImporting)
                    }
                }
            }
            .navigationTitle("Importer MyFitnessPal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .disabled(store.isImporting)
                }
            }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: MyFitnessPalImport.contentTypes) { picked in
                switch picked {
                case .success(let url): Task { await store.importFile(at: url) }
                case .failure(let error): store.pickerFailed(error)
                }
            }
        }
        .interactiveDismissDisabled(store.isImporting)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    @ViewBuilder
    private var outcome: some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .importing:
            Section {
                HStack(spacing: SharpitSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Lecture de ton export… Ça peut prendre une minute.")
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .sharpitListRows()
        case .imported(let result):
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MyFitnessPalImport.summary(of: result))
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        if let note = MyFitnessPalImport.skippedNote(of: result) {
                            Text(note)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                } icon: {
                    Image(systemName: result.importedDays > 0 ? "checkmark.circle.fill" : "tray")
                        .foregroundStyle(result.importedDays > 0 ? SharpitColor.primary : SharpitColor.mutedForeground)
                }
            }
            .sharpitListRows()
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SharpitColor.signalCaution)
            }
            .sharpitListRows()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Text("\(number)")
                .font(SharpitTypography.meta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 22, height: 22)
                .background(SharpitColor.primary.opacity(0.10), in: Circle())
            Text(text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
