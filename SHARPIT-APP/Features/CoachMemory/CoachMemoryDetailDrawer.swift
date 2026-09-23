import SwiftUI

/// Drawer presenting the complete details of a travel or constraint from the coach memory,
/// with the ability to delete it directly.
struct CoachMemoryDetailDrawer: View {
    let entry: CoachMemoryEntry
    let onDelete: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SharpitSpacing.lg) {
                    headerCard

                    VStack(spacing: SharpitSpacing.sm) {
                        detailRow(
                            title: "Dates",
                            value: entry.formattedDateRange,
                            symbol: "calendar"
                        )

                        if let loc = entry.locationLabel, !loc.isEmpty {
                            detailRow(
                                title: "Lieu",
                                value: loc,
                                symbol: "mappin.and.ellipse"
                            )
                        }

                        detailRow(
                            title: "Impact entraînement",
                            value: entry.trainingConstraint.label,
                            symbol: "figure.run",
                            badgeText: entry.trainingConstraint.badgeText,
                            badgeColor: constraintColor(entry.trainingConstraint)
                        )

                        if let disciplines = entry.allowedDisciplines, !disciplines.isEmpty {
                            allowedDisciplinesCard(disciplines)
                        }

                        if let note = entry.note, !note.isEmpty {
                            notesCard(note)
                        }
                    }

                    deleteButton
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.md)
            }
            .background(SharpitCanvasBackground())
            .navigationTitle(entry.type == .travel ? "Déplacement" : "Contrainte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .font(SharpitTypography.bodyEmphasis)
                }
            }
            .confirmationDialog(
                "Supprimer cette entrée ?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isDeleting = true
                        await onDelete()
                        isDeleting = false
                        dismiss()
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est irréversible. Le coach réadaptera les séances sans cette contrainte.")
            }
        }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
    }

    private var headerCard: some View {
        HStack(spacing: SharpitSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .fill(SharpitColor.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: entry.type == .travel ? "airplane" : "clock.badge.exclamationmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)

                Text(entry.formattedDateRange)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer()

            Text(entry.trainingConstraint.badgeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(constraintColor(entry.trainingConstraint))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(constraintColor(entry.trainingConstraint).opacity(0.12), in: Capsule())
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func detailRow(
        title: String,
        value: String,
        symbol: String,
        badgeText: String? = nil,
        badgeColor: Color? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 24)

            Text(title)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

            Spacer()

            if let badgeText, let badgeColor {
                Text(badgeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.12), in: Capsule())
            } else {
                Text(value)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    private func allowedDisciplinesCard(_ disciplines: [String]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text("Sports possibles")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

            HStack(spacing: SharpitSpacing.xs) {
                ForEach(disciplines, id: \.self) { raw in
                    if let disc = AllowedDiscipline(rawValue: raw) {
                        HStack(spacing: 4) {
                            Image(systemName: disc.symbol)
                                .font(.system(size: 12))
                            Text(disc.label)
                                .font(SharpitTypography.meta)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                        .foregroundStyle(SharpitColor.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    private func notesCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes pour le coach")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

            Text(note)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Supprimer")
                        .font(SharpitTypography.bodyEmphasis)
                }
            }
            .foregroundStyle(SharpitColor.signalRisk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(SharpitColor.signalRisk.opacity(0.1), in: RoundedRectangle(cornerRadius: SharpitRadius.small))
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .padding(.top, SharpitSpacing.xs)
    }

    private func constraintColor(_ constraint: TravelTrainingConstraint) -> Color {
        switch constraint {
        case .full: SharpitColor.primary
        case .reduced: SharpitColor.signalCaution
        case .mobilityOnly: SharpitColor.signalCaution
        case .none: SharpitColor.signalRisk
        }
    }
}
