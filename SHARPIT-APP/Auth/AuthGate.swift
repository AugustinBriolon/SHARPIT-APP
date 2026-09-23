import ClerkKit
import ClerkKitUI
import SwiftUI

/// The app's authentication gate.
///
/// Displays an Apple Design Award-grade welcome experience with precision telemetry,
/// animated chronograph gauge, live floating HUD cards, and fluid motion choreography.
struct AuthGate<SignedIn: View>: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false
    var signedIn: () -> SignedIn

    var body: some View {
        Group {
            if clerk.user != nil {
                signedIn()
            } else {
                SignInAwardWinning(onSignIn: { authIsPresented = true })
            }
        }
        .sheet(isPresented: $authIsPresented) {
            SharpitAuthDrawer()
        }
    }
}

// MARK: – Award-Winning Welcome Experience

private struct SignInAwardWinning: View {
    var onSignIn: () -> Void

    // Choreographed entrance states
    @State private var showHeader = false
    @State private var showDial = false
    @State private var dialProgress: CGFloat = 0
    @State private var showCenterBadge = false
    @State private var showFloatingCards = false
    @State private var showText = false
    @State private var showCTA = false

    // Idle ambient animation states
    @State private var radarPulse = false
    @State private var floatPhase: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1.2
    @State private var orbitRotation: Double = 0
    @State private var dialIsLive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 1 — Deep atmospheric canvas with texture & ambient glow
            SharpitColor.background.ignoresSafeArea()
            ambientAtmosphere
            PrecisionParticleField()
                .ignoresSafeArea()

            // 2 — Main Content Layout
            VStack(spacing: 0) {
                // Top status chip
                systemStatusChip
                    .padding(.top, 56)
                    .opacity(showHeader ? 1 : 0)
                    .offset(y: showHeader ? 0 : -12)

                Spacer(minLength: 16)

                // Center Telemetry Instrument with Floating HUD Cards
                telemetryHero
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 20)

                // Typography & Value Props
                brandingBlock
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 16)
                    .padding(.bottom, 32)

                // Bottom Action Deck
                ctaDeck
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.bottom, 36)
                    .opacity(showCTA ? 1 : 0)
                    .offset(y: showCTA ? 0 : 20)
            }
        }
        .ignoresSafeArea(.keyboard)
        .task { await runChoreography() }
    }

    // MARK: – Ambient Atmosphere

    private var ambientAtmosphere: some View {
        ZStack {
            // Primary Forest Green Halo behind the hero
            RadialGradient(
                colors: [
                    SharpitColor.primary.opacity(0.18),
                    SharpitColor.primary.opacity(0.06),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 260
            )
            .offset(y: -50)

            // Accent Lime Pulse Glow near the top
            RadialGradient(
                colors: [
                    SharpitColor.highlight.opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.2, y: 0.25),
                startRadius: 10,
                endRadius: 220
            )

            // Subtle warm grounding glow near the bottom
            RadialGradient(
                colors: [
                    SharpitColor.primary.opacity(0.09),
                    .clear
                ],
                center: UnitPoint(x: 0.8, y: 0.85),
                startRadius: 20,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }

    // MARK: – Top Status Chip

    private var systemStatusChip: some View {
        HStack(spacing: 7) {
            // Live pulsing beacon dot
            ZStack {
                Circle()
                    .fill(SharpitColor.highlight.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .scaleEffect(radarPulse ? 1.6 : 0.9)
                    .opacity(radarPulse ? 0 : 0.8)
                Circle()
                    .fill(SharpitColor.primary)
                    .frame(width: 7, height: 7)
            }

            Text("ANALYSE ATHLÉTIQUE")
                .font(.custom(SharpitFontFamily.data.resolvedName(for: .medium) ?? "Menlo", size: 10.5))
                .tracking(1.4)
                .foregroundStyle(SharpitColor.foreground.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(SharpitColor.card)
                .overlay(Capsule().strokeBorder(SharpitColor.border, lineWidth: 1))
                .sharpitShadow(.control)
        }
    }

    // MARK: – Center Telemetry Hero

    private var telemetryHero: some View {
        ZStack {
            // 1. Radar wave expanding outwards from center
            Circle()
                .stroke(SharpitColor.highlight.opacity(radarPulse ? 0.0 : 0.45), lineWidth: 1.5)
                .frame(width: 180, height: 180)
                .scaleEffect(radarPulse ? 1.55 : 0.9)

            // 2. Precision 64-tick chronograph scale with live kinetic ripple
            ChronographDial(progress: dialProgress, isLive: dialIsLive)
                .frame(width: 250, height: 250)

            // 3. Counter-rotating dashed orbit track
            Circle()
                .stroke(
                    SharpitColor.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 6])
                )
                .frame(width: 216, height: 216)
                .rotationEffect(.degrees(orbitRotation))

            // 4. Center Runner Badge with luminous depth
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(SharpitColor.primary.opacity(0.25), lineWidth: 2)
                    .frame(width: 86, height: 86)

                // Dark ink core
                Circle()
                    .fill(SharpitColor.inkSurface)
                    .frame(width: 76, height: 76)
                    .sharpitShadow(.panel)
                    .overlay(
                        Circle().strokeBorder(SharpitColor.highlight.opacity(0.35), lineWidth: 1)
                    )

                Image(systemName: "figure.run")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
            }
            .scaleEffect(showCenterBadge ? 1.0 : 0.35)
            .opacity(showCenterBadge ? 1.0 : 0.0)

            // 5. Floating HUD Card 1 (Top Left) — Sleep / HRV
            floatingSleepCard
                .offset(x: -95, y: -90 + (sin(floatPhase) * 5))
                .opacity(showFloatingCards ? 1 : 0)
                .scaleEffect(showFloatingCards ? 1 : 0.8)

            // 6. Floating HUD Card 2 (Bottom Right) — Recovery / Readiness
            floatingRecoveryCard
                .offset(x: 88, y: 92 + (cos(floatPhase) * 5))
                .opacity(showFloatingCards ? 1 : 0)
                .scaleEffect(showFloatingCards ? 1 : 0.8)
        }
        .frame(width: 310, height: 310)
    }

    // MARK: – Floating HUD Cards

    private var floatingSleepCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(SharpitColor.primary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SOMMEIL")
                    .font(.custom(SharpitFontFamily.data.resolvedName(for: .medium) ?? "Menlo", size: 9))
                    .tracking(0.8)
                    .foregroundStyle(SharpitColor.mutedForeground)

                Text("8h 24m · 94%")
                    .font(.custom(SharpitFontFamily.data.resolvedName(for: .regular) ?? "Menlo", size: 13))
                    .fontWeight(.semibold)
                    .foregroundStyle(SharpitColor.cardForeground)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SharpitColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SharpitColor.border, lineWidth: 1)
                )
                .sharpitShadow(.panel)
        }
    }

    private var floatingRecoveryCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(SharpitColor.highlight.opacity(0.25))
                    .frame(width: 32, height: 32)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SharpitColor.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("RÉCUPÉRATION")
                    .font(.custom(SharpitFontFamily.data.resolvedName(for: .medium) ?? "Menlo", size: 9))
                    .tracking(0.8)
                    .foregroundStyle(SharpitColor.mutedForeground)

                HStack(spacing: 4) {
                    Circle()
                        .fill(SharpitColor.signalRecovery)
                        .frame(width: 6, height: 6)
                    Text("Feu Vert · Prêt")
                        .font(.custom(SharpitFontFamily.data.resolvedName(for: .regular) ?? "Menlo", size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(SharpitColor.cardForeground)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SharpitColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SharpitColor.border, lineWidth: 1)
                )
                .sharpitShadow(.panel)
        }
    }

    // MARK: – Typography & Value Props

    private var brandingBlock: some View {
        VStack(spacing: 12) {
            // Main App Wordmark
            Text("SharpIt")
                .font(.custom(SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System", size: 36, relativeTo: .largeTitle))
                .tracking(-1.0)
                .foregroundStyle(SharpitColor.foreground)

            // Punchy Tagline
            Text("L'intelligence de ton entraînement.")
                .font(.custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 16, relativeTo: .headline))
                .foregroundStyle(SharpitColor.mutedForeground)

            // Value Pillar Badges
            HStack(spacing: 8) {
                pillarPill(title: "Sommeil & VRC")
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
                pillarPill(title: "Charge TSS")
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
                pillarPill(title: "Planification")
            }
            .padding(.top, 4)
        }
    }

    private func pillarPill(title: String) -> some View {
        Text(title)
            .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12))
            .foregroundStyle(SharpitColor.mutedForeground.opacity(0.9))
    }

    // MARK: – Action Deck

    private var ctaDeck: some View {
        VStack(spacing: 14) {
            Button {
                SharpitHaptics.play(.light)
                onSignIn()
            } label: {
                HStack(spacing: 10) {
                    Text("Se connecter")
                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 17))
                        .foregroundStyle(SharpitColor.primaryForeground)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharpitColor.primaryForeground.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                            .fill(SharpitColor.primary)

                        // Shimmer sweep highlight
                        RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, SharpitColor.highlight.opacity(0.42), .clear],
                                    startPoint: UnitPoint(x: shimmerOffset, y: 0),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.5, y: 1)
                                )
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                        .strokeBorder(SharpitColor.highlight.opacity(0.2), lineWidth: 1)
                )
                .sharpitShadow(.panel)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Se connecter à SharpIt")
            .prefetchClerkImages()

            // Trust reassurance microcopy
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(SharpitColor.primary.opacity(0.8))
                Text("Connexion instantanée · Données synchronisées")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    // MARK: – Choreography Execution

    private func runChoreography() async {
        guard !reduceMotion else {
            showHeader = true
            showDial = true
            dialProgress = 0.88
            showCenterBadge = true
            showFloatingCards = true
            showText = true
            showCTA = true
            return
        }

        // 1. Header chip reveals
        withAnimation(.easeOut(duration: 0.45)) { showHeader = true }

        // 2. Dial sweeps around
        try? await Task.sleep(for: .milliseconds(120))
        showDial = true
        withAnimation(.spring(response: 1.1, dampingFraction: 0.82)) {
            dialProgress = 0.88
        }

        // 3. Center badge pops with energetic spring overshoot
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            showCenterBadge = true
        }

        // 4. Floating HUD Cards glide in from sides
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.60, dampingFraction: 0.72)) {
            showFloatingCards = true
        }

        // 5. Typography reveals smoothly
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.45)) {
            showText = true
        }

        // 6. CTA deck slides in
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.spring(response: 0.50, dampingFraction: 0.75)) {
            showCTA = true
        }

        // 7. Initiate infinite ambient micro-motions
        startAmbientLoops()
    }

    private func startAmbientLoops() {
        guard !reduceMotion else { return }

        // Radar heartbeat pulse
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
            radarPulse = true
        }

        // Orbital slow rotation
        withAnimation(.linear(duration: 32).repeatForever(autoreverses: false)) {
            orbitRotation = 360
        }

        // Periodic button shimmer sweep
        withAnimation(.easeInOut(duration: 1.9).delay(1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.8
        }

        // Gentle floating HUD motion
        withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
            floatPhase = .pi * 2
        }

        // Activate dynamic telemetry motion on the chronograph dial
        dialIsLive = true
    }
}

// MARK: – Precision Chronograph Dial with Kinetic Motion

/// An Apple Design Award-grade dynamic mechanical chronograph dial.
/// Features:
/// - 64 precision ticks with dynamic ripple expansion as the telemetry radar sweeps
/// - Continuous 360° sweeping scan-beam that ignites phosphorescent Lime trails
/// - Breathing live measurement at the arc's crest with pulsating needle bead
/// - High-precision counter-rotating vernier micro-ticks for parallax mechanical depth
private struct ChronographDial: View {
    let progress: CGFloat
    let isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tickCount = 64
    private let vernierCount = 96

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radiusOuter = min(size.width, size.height) / 2
                let radiusInner = radiusOuter - 11

                // 1. Inner Vernier micro-scale (counter-rotating mechanical ring)
                let vernierRadiusOuter = radiusInner - 5
                let vernierRadiusInner = vernierRadiusOuter - 4
                let vernierRotation = CGFloat(t * 0.14) // slow counter-clockwise drift

                for j in 0..<vernierCount {
                    let fraction = CGFloat(j) / CGFloat(vernierCount)
                    let angle = (fraction * 2 * .pi) - (.pi / 2) - vernierRotation

                    let xO = center.x + vernierRadiusOuter * cos(angle)
                    let yO = center.y + vernierRadiusOuter * sin(angle)
                    let xI = center.x + vernierRadiusInner * cos(angle)
                    let yI = center.y + vernierRadiusInner * sin(angle)

                    var p = Path()
                    p.move(to: CGPoint(x: xI, y: yI))
                    p.addLine(to: CGPoint(x: xO, y: yO))

                    let isMajorVernier = j % 12 == 0
                    context.stroke(
                        p,
                        with: .color(isMajorVernier ? SharpitColor.primary.opacity(0.35) : SharpitColor.border.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                    )
                }

                // 2. Telemetry Scanner Wave Angle (sweeps around every 2.8s)
                let sweepSpeed: CGFloat = 2.24 // ~2.8s per revolution
                let sweepAngle = CGFloat(fmod(t * Double(sweepSpeed), 2 * .pi)) - (.pi / 2)

                // 3. Live breathing progress (fluctuates slightly around target reading)
                let breathOffset: CGFloat = isLive && !reduceMotion ? CGFloat(sin(t * 1.5)) * 0.025 : 0
                let activeProgress = min(max(progress + breathOffset, 0), 1.0)

                // 4. Main Chronograph 64-tick Ring with kinetic ripple
                for i in 0..<tickCount {
                    let fraction = CGFloat(i) / CGFloat(tickCount)
                    let angle = (fraction * 2 * .pi) - (.pi / 2)

                    // Angular distance to the radar sweep beam
                    var diffAngle = angle - sweepAngle
                    while diffAngle > .pi { diffAngle -= 2 * .pi }
                    while diffAngle < -.pi { diffAngle += 2 * .pi }

                    // Proximity to the sweep beam [0..1]
                    let beamWidth: CGFloat = 0.55 // ~32 degrees
                    let beamProximity = max(0, 1.0 - abs(diffAngle) / beamWidth)
                    // Trailing phosphorescent decay
                    let trailingProximity = (diffAngle < 0 && diffAngle > -1.2) ? (1.0 - abs(diffAngle) / 1.2) * 0.45 : 0
                    let sweepWave = max(beamProximity, trailingProximity)

                    let isMajor = i % 8 == 0
                    // Physical ripple: ticks lengthen dynamically as the wave passes!
                    let rippleExtension = isLive && !reduceMotion ? sweepWave * 3.5 : 0

                    let currentOuter = radiusOuter + rippleExtension * 0.4
                    let currentInner = isMajor
                        ? (radiusInner - 4 - rippleExtension * 0.6)
                        : (radiusInner - rippleExtension * 0.6)

                    let xOuter = center.x + currentOuter * cos(angle)
                    let yOuter = center.y + currentOuter * sin(angle)
                    let xInner = center.x + currentInner * cos(angle)
                    let yInner = center.y + currentInner * sin(angle)

                    var path = Path()
                    path.move(to: CGPoint(x: xInner, y: yInner))
                    path.addLine(to: CGPoint(x: xOuter, y: yOuter))

                    let isLit = fraction <= activeProgress
                    let strokeColor: Color
                    let strokeWidth: CGFloat

                    if isLit {
                        if fraction >= activeProgress - 0.12 {
                            // Crest of the arc - neon Lime
                            strokeColor = SharpitColor.highlight
                            strokeWidth = isMajor ? 2.6 : 1.8
                        } else if sweepWave > 0.15 {
                            // Wave passing over lit section: supercharged flare
                            strokeColor = SharpitColor.highlight.opacity(0.85 + Double(sweepWave) * 0.15)
                            strokeWidth = isMajor ? 2.8 : 2.0
                        } else {
                            // Standard lit Forest Green
                            strokeColor = SharpitColor.primary
                            strokeWidth = isMajor ? 2.2 : 1.5
                        }
                    } else {
                        if sweepWave > 0.05 {
                            // Wave illuminating unlit section temporarily
                            strokeColor = SharpitColor.highlight.opacity(Double(sweepWave) * 0.65)
                            strokeWidth = 1.6
                        } else {
                            // Muted standby ticks
                            strokeColor = SharpitColor.border.opacity(0.32)
                            strokeWidth = isMajor ? 1.5 : 1.1
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(strokeColor),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                }

                // 5. Active Precision Needle Bead at the arc's crest
                if activeProgress > 0.05 {
                    let headAngle = (activeProgress * 2 * .pi) - (.pi / 2)
                    let beadRadius: CGFloat = 3.6
                    let beadCenterR = radiusOuter - 5.5
                    let bx = center.x + beadCenterR * cos(headAngle)
                    let by = center.y + beadCenterR * sin(headAngle)

                    // Outer halo
                    let haloScale = isLive && !reduceMotion ? (1.0 + 0.25 * CGFloat(sin(t * 4.0))) : 1.0
                    let haloRect = CGRect(
                        x: bx - beadRadius * 2.2 * haloScale,
                        y: by - beadRadius * 2.2 * haloScale,
                        width: beadRadius * 4.4 * haloScale,
                        height: beadRadius * 4.4 * haloScale
                    )
                    context.fill(Path(ellipseIn: haloRect), with: .color(SharpitColor.highlight.opacity(0.28)))

                    // Solid bright bead
                    let beadRect = CGRect(x: bx - beadRadius, y: by - beadRadius, width: beadRadius * 2, height: beadRadius * 2)
                    context.fill(Path(ellipseIn: beadRect), with: .color(SharpitColor.highlight))
                    context.stroke(Path(ellipseIn: beadRect), with: .color(SharpitColor.card), style: StrokeStyle(lineWidth: 1.2))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: – Precision Particle Field

/// Subtle floating performance energy particles (ambient dust) drawn via TimelineView.
private struct PrecisionParticleField: View {
    private let particles: [TelemetryParticle] = (0..<36).map { _ in TelemetryParticle() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let rawX = p.x0 * size.width + CGFloat(t) * p.vx
                    let x = rawX.truncatingRemainder(dividingBy: size.width + 20) - 10
                    let y = p.y0 * size.height + sin(CGFloat(t) * p.freq + p.phase) * p.amp
                    let breath = 0.5 + 0.5 * sin(CGFloat(t) * p.pulseSpeed + p.phase)
                    let alpha = p.baseAlpha * breath

                    let dot = Path(ellipseIn: CGRect(x: x - p.r, y: y - p.r, width: p.r * 2, height: p.r * 2))
                    let color = p.isLime
                        ? SharpitColor.highlight.opacity(alpha)
                        : SharpitColor.primary.opacity(alpha * 0.7)
                    context.fill(dot, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TelemetryParticle {
    let x0: CGFloat
    let y0: CGFloat
    let vx: CGFloat
    let freq: CGFloat
    let phase: CGFloat
    let amp: CGFloat
    let r: CGFloat
    let isLime: Bool
    let baseAlpha: Double
    let pulseSpeed: CGFloat

    init() {
        x0 = .random(in: 0...1)
        y0 = .random(in: 0...1)
        vx = .random(in: 2...8)
        freq = .random(in: 0.15...0.4)
        phase = .random(in: 0...(2 * .pi))
        amp = .random(in: 12...35)
        r = .random(in: 1.0...2.8)
        isLime = Double.random(in: 0...1) < 0.4
        baseAlpha = .random(in: 0.12...0.38)
        pulseSpeed = .random(in: 0.4...0.8)
    }
}
