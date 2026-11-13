import SwiftUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - Santé entry

/// Santé's way in to blood tests: the history, from which a report is imported.
struct BloodTestsCard: View {
    let tokenProvider: () async throws -> String

    var body: some View {
        NavigationLink {
            BloodTestsView(tokenProvider: tokenProvider)
        } label: {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitCardHeader(title: String(localized: "Analyses de sang"), symbol: "drop")
                Text("Importe un compte rendu : seules les valeurs sont gardées, jamais le document.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre tes analyses de sang")
    }
}

// MARK: - Import

/// Pick or scan a report, then check what was read before it is saved.
struct BloodTestImportView: View {
    @State private var store: BloodTestImportStore
    @State private var isPickingFile = false
    @State private var isScanning = false
    @Environment(\.dismiss) private var dismiss

    init(tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: BloodTestImportStore(tokenProvider: tokenProvider))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .idle: source
            case .reading: ProgressView("Lecture sur ton iPhone…")
            case .review, .saving: BloodTestReviewView(store: store)
            case .saved:
                SharpitStateMessage(
                    title: String(localized: "Analyse enregistrée"),
                    symbol: "checkmark.seal",
                    detail: String(localized: "Tes valeurs sont chiffrées. Le document n'a pas quitté ton iPhone.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitCanvasBackground())
        .navigationTitle("Analyse de sang")
        .navigationBarTitleDisplayMode(.inline)
        // Back to the history, where the new test is the news.
        .onChange(of: store.phase) { _, phase in
            if phase == .saved { dismiss() }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            Task { await store.readFile(at: url) }
        }
        .fullScreenCover(isPresented: $isScanning) {
            BloodReportScanner { pages in
                isScanning = false
                guard !pages.isEmpty else { return }
                Task { await store.readScan(pages) }
            }
            .ignoresSafeArea()
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitCardHeader(title: String(localized: "Importer un compte rendu"), symbol: "doc.text.viewfinder", showsChevron: false)
                Text("Le document est lu sur ton iPhone. Ton nom, ton adresse et ton médecin ne sont ni lus ni envoyés : seules les valeurs que tu confirmes sont enregistrées.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = store.errorMessage {
                    Text(message)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)

            SharpitPrimaryButton(title: String(localized: "Choisir le PDF du laboratoire")) { isPickingFile = true }
            if VNDocumentCameraViewController.isSupported {
                SharpitPrimaryButton(title: String(localized: "Scanner le papier"), style: .secondary) { isScanning = true }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
    }
}

// MARK: - Review

/// What was read, one row per marker, corrected by the athlete before anything is sent.
struct BloodTestReviewView: View {
    @Bindable var store: BloodTestImportStore

    var body: some View {
        if let draft = Binding($store.draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    card(draft)
                    if let message = store.errorMessage {
                        Text(message)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    SharpitPrimaryButton(title: String(localized: "Enregistrer"), isBusy: store.phase == .saving) {
                        Task { await store.save() }
                    }
                    .disabled(!draft.wrappedValue.canSave || store.phase == .saving)
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Recommencer") { store.discard() }
                }
            }
        }
    }

    private func card(_ draft: Binding<BloodTestDraft>) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: String(localized: "\(draft.wrappedValue.rows.count) marqueurs lus"),
                symbol: "checklist",
                subtitle: draft.wrappedValue.isRecognised ? String(localized: "Lu depuis une image : vérifie chaque valeur.") : nil,
                showsChevron: false
            )
            DatePicker("Prélèvement", selection: draft.sampledAt, in: ...Date.now, displayedComponents: .date)
                .font(SharpitTypography.bodyEmphasis)
            SharpitInsetGroup {
                ForEach(draft.rows) { row in
                    BloodTestReviewRow(row: row) {
                        draft.wrappedValue.rows.removeAll { $0.id == row.wrappedValue.id }
                    }
                }
            }
            if !draft.wrappedValue.missingMarkers.isEmpty {
                Menu {
                    ForEach(draft.wrappedValue.missingMarkers, id: \.key) { marker in
                        Button(marker.label) { draft.wrappedValue.add(marker) }
                    }
                } label: {
                    Label("Ajouter un marqueur", systemImage: "plus")
                        .font(SharpitTypography.bodyEmphasis)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct BloodTestReviewRow: View {
    @Binding var row: BloodTestDraft.Row
    let remove: () -> Void

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.marker?.label ?? row.markerKey)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(caption)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(captionTone)
            }
            Spacer(minLength: SharpitSpacing.xs)
            TextField("Valeur", value: $row.value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(SharpitTypography.bodyEmphasis)
                .monospacedDigit()
                .frame(maxWidth: 84)
                .accessibilityLabel(row.marker?.label ?? row.markerKey)
            Text(row.marker?.unit ?? "")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer \(row.marker?.label ?? row.markerKey)")
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        // A two-line marker name with its caption outgrows the row height: keep air at the hairlines.
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.rowHeight)
    }

    private var caption: String {
        guard row.isPlausible, let status = row.status else { return String(localized: "Valeur à corriger") }
        return BloodMarkerReadout.caption(status: status, low: row.refLow, high: row.refHigh)
    }

    private var captionTone: Color {
        guard row.isPlausible, let status = row.status else { return SharpitColor.signalRisk }
        return BloodMarkerReadout.isOutOfRange(status) ? SharpitColor.signalCaution : SharpitColor.mutedForeground
    }
}

// MARK: - Scanner

/// The system's document camera: it straightens the page, and hands the pages back as images.
private struct BloodReportScanner: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CGImage]) -> Void

        init(onFinish: @escaping ([CGImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish([])
        }
    }
}
