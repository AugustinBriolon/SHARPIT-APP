import SwiftUI

/// BLE heart-rate device picker — scan, pick, disconnect.
struct GuidedHeartRatePickerSheet: View {
    @ObservedObject var monitor: GuidedHeartRateMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if monitor.status == .unauthorized || monitor.status == .unavailable {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bluetooth indisponible")
                                    .font(SharpitTypography.bodyEmphasis)
                                Text(
                                    monitor.status == .unauthorized
                                        ? "Autorise Bluetooth pour SharpIt dans Réglages."
                                        : "Active Bluetooth, puis réessaie."
                                )
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            }
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    .sharpitListRows()
                } else {
                    if monitor.status == .connected {
                        Section {
                            connectedRow
                            Button("Déconnecter", role: .destructive) {
                                monitor.disconnectAndDisable()
                            }
                        } header: {
                            Text("Connecté")
                        }
                        .sharpitListRows()
                    }

                    Section {
                        if monitor.devices.isEmpty {
                            HStack(spacing: SharpitSpacing.sm) {
                                ProgressView()
                                Text("Recherche de capteurs…")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            }
                            .padding(.vertical, SharpitSpacing.xs)
                        } else {
                            ForEach(monitor.devices) { device in
                                Button {
                                    monitor.connect(to: device.id)
                                    dismiss()
                                } label: {
                                    deviceRow(device)
                                }
                                .buttonStyle(.plain)
                                .disabled(monitor.status == .connecting)
                            }
                        }
                    } header: {
                        Text("Appareils")
                    } footer: {
                        SharpitListFooter(
                            "Ceinture, brassard ou montre qui diffuse la FC en Bluetooth (profil Heart Rate)."
                        )
                    }
                    .sharpitListRows()
                }
            }
            .sharpitGroupedList()
            .navigationTitle("Fréquence cardiaque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear { monitor.startScanningForPicker() }
        .onDisappear { monitor.endPickerScan() }
        .presentationDetents([.medium, .large])
    }

    private var connectedRow: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: "heart.fill")
                .foregroundStyle(SharpitColor.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.peripheralName ?? "Capteur")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let bpm = monitor.bpm {
                    Text("\(bpm) bpm")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(SharpitColor.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func deviceRow(_ device: GuidedHeartRateMonitor.Device) -> some View {
        let isConnected = monitor.status == .connected
            && GuidedHeartRatePreference.lastPeripheralUUID == device.id
        return HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: "heart")
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(device.name)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: 0)
            if isConnected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
            } else if monitor.status == .connecting,
                      GuidedHeartRatePreference.lastPeripheralUUID == device.id {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isConnected ? [.isButton, .isSelected] : .isButton)
    }
}
