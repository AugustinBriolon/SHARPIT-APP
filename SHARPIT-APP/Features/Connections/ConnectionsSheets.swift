import SwiftUI

/// The sheet a connected source opens: what it brings, how it stands, and the way out. The
/// confirmation lives here so the sheet and the question it asks leave together.
struct SourceManageSheet: View {
    let source: ManagedSource
    let status: ConnectionsReadout.Line
    /// The picker for the calendar SharpIt writes the plan into, for the calendar sources.
    var calendarPicker: AnyView? = nil
    let onDisconnect: () -> Void

    @State private var confirming = false
    @State private var pickingCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: source.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(status.text)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(status.isProblem ? SharpitColor.signalRisk : SharpitColor.slate)
                }
            }
            Text(source.benefit)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            if calendarPicker != nil {
                Button { pickingCalendar = true } label: {
                    HStack {
                        Label("Calendrier des séances", systemImage: "calendar")
                            .font(SharpitTypography.bodyEmphasis)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(SharpitColor.foreground)
                    .padding(.vertical, SharpitSpacing.xs)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Choisis où SharpIt écrit tes séances")
            }
            SharpitPrimaryButton(title: source.disconnectLabel, style: .secondary) { confirming = true }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(source.disconnectTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(source.disconnectLabel, role: .destructive, action: onDisconnect)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(source.disconnectMessage)
        }
        .sheet(isPresented: $pickingCalendar) {
            NavigationStack { calendarPicker }
                .sharpitSheet()
        }
        .presentationDetents([.height(calendarPicker == nil ? 250 : 310)])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }
}
