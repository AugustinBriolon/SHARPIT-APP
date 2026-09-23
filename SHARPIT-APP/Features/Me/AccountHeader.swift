import ClerkKit
import ClerkKitUI
import SwiftUI

/// Moi's first row: who is signed in, the way Settings opens on the Apple Account.
///
/// The whole row opens the Clerk profile, not only the avatar: a row that looks tappable end
/// to end must be, and a 36pt avatar alone is a smaller target than the row it sits in.
struct AccountHeader: View {
    @Environment(Clerk.self) private var clerk
    @State private var isShowingProfile = false
    @State private var chevronBounce = false
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 56

    var body: some View {
        Button {
            isShowingProfile = true
            // Subtle bounce on the chevron at tap — tactile visual echo.
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    chevronBounce = true
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(320))
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.70)) {
                        chevronBounce = false
                    }
                }
            }
        } label: {
            HStack(spacing: SharpitSpacing.md) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)
                    if let email {
                        Text(email)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .scaleEffect(chevronBounce ? 1.22 : 1.0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, SharpitSpacing.xxs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre ton compte")
        .sheet(isPresented: $isShowingProfile) {
            SharpitUserProfileSheet()
        }
    }

    private var avatar: some View {
        AsyncImage(url: clerk.user.flatMap { URL(string: $0.imageUrl) }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(SharpitColor.primary.opacity(0.35), lineWidth: 2)
        )
        .accessibilityHidden(true)
    }

    private var name: String {
        let first = clerk.user?.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Ton compte" : first
    }

    private var email: String? {
        clerk.user?.primaryEmailAddress?.emailAddress
    }
}

// MARK: – SharpIT-themed Clerk profile sheet

/// Wraps Clerk's `UserProfileView` with a SharpIT canvas background and full-height
/// sheet presentation so the white system surface is replaced by the app's own palette.
private struct SharpitUserProfileSheet: View {
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
