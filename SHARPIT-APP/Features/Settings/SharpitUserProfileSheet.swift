import ClerkKit
import ClerkKitUI
import SwiftUI

// MARK: – SharpIT-themed Clerk profile sheet

/// Wraps Clerk's `UserProfileView` with a SharpIT canvas background and full-height
/// sheet presentation so the white system surface is replaced by the app's own palette.
struct SharpitUserProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // SharpIT header above the Clerk component.
            VStack(spacing: 0) {
                sharpitHeader
                Divider()
                    .overlay(SharpitColor.border)
                // The Clerk profile — opaque component, we can't restyle its internals.
                UserProfileView()
            }
            .background(SharpitCanvasBackground())
            .navigationBarHidden(true)
        }
        // Sheet presentation that matches other drawers in the app.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Replace the white system sheet background with the app canvas.
        .presentationBackground(SharpitColor.background)
    }

    private var sharpitHeader: some View {
        HStack {
            // Small brand mark — the app name acts as a context anchor.
            Text("SharpIt")
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .sharpitGlassCircle()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(SharpitColor.foreground)
            }
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.vertical, SharpitSpacing.sm)
    }
}
