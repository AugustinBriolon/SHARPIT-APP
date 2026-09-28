import SwiftUI
import UIKit

/// The small uppercase label above a field or a row of choices.
struct SharpitFieldLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.mutedForeground)
    }
}

/// The well every input sits in: a soft filled shape, no card, no shadow — the label stays
/// outside, above. The ring appears only while the field is being answered.
private struct SharpitFieldWell: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SharpitSpacing.sm + 2)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                    .fill(SharpitColor.analysisSurfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                    .strokeBorder(SharpitColor.primary, lineWidth: 1.5)
                    .opacity(isActive ? 1 : 0)
            )
            .animation(SharpitMotion.selection, value: isActive)
    }
}

extension View {
    func sharpitFieldWell(isActive: Bool = false) -> some View {
        modifier(SharpitFieldWell(isActive: isActive))
    }
}

/// A labelled text field: the label above, the text in a soft well.
struct SharpitFormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    init(_ title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.keyboard = keyboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(title)
            TextField(placeholder, text: $text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .keyboardType(keyboard)
                .submitLabel(.done)
                .focused($isFocused)
                .sharpitFieldWell(isActive: isFocused)
        }
    }
}

/// One of a few, side by side in a track; the pick is a pill that slides to it.
struct SharpitSegmentedChoice<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    SharpitHaptics.play(.light)
                    SharpitMotion.run(SharpitMotion.selection) { selection = option }
                } label: {
                    Text(label(option))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(SharpitColor.primary)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(SharpitColor.analysisSurfaceAlt))
    }
}

/// A value picked on a ruler: the figure large above, the ruler scrolled under a fixed needle,
/// settling on each unit with a tick of haptic — a tape measure rather than a menu.
///
/// A value left unanswered stays nil: the ruler starts at `resting` but records nothing until
/// the athlete moves it.
struct SharpitRulerPicker: View {
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let unit: String
    /// Where the ruler rests before anything is picked.
    let resting: Int
    var majorEvery = 10

    /// Drives the scroll (where the ruler rests, an accessibility step).
    @State private var position: Int?
    /// Under the needle, read from the scroll's own geometry: the id a paging scroll reports
    /// lagged a unit behind the needle once it settled.
    @State private var centred: Int?
    @State private var isTouched = false

    /// Distance between two units on the ruler.
    private let pitch: CGFloat = 10

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // Unanswered, the resting value shows faded: a figure, not a dash, so the
                    // ruler reads before it is touched.
                    Text(String(value ?? resting))
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(value == nil ? SharpitColor.mutedForeground.opacity(0.45) : SharpitColor.foreground)
                        .contentTransition(.numericText(value: Double(value ?? resting)))
                        .animation(SharpitMotion.selection, value: value)
                    Text(unit)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Text("Fais glisser la règle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .opacity(value == nil ? 1 : 0)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(range), id: \.self) { mark in
                            tick(mark).frame(width: pitch).id(mark)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, max(0, proxy.size.width / 2 - pitch / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $position, anchor: .center)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting {
                        isTouched = true
                        SharpitHaptics.prepare()
                    }
                }
                .onScrollGeometryChange(for: Int.self) { geometry in
                    let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                    let index = Int((offset / pitch).rounded())
                    return min(max(range.lowerBound + index, range.lowerBound), range.upperBound)
                } action: { _, mark in
                    centred = mark
                }
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(SharpitColor.primary)
                        .frame(width: 3, height: 40)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 64)
        }
        .onAppear { position = value ?? resting }
        .onChange(of: centred) { _, mark in
            guard isTouched, let mark, mark != value else { return }
            value = mark
            // One notch per unit, a firmer one on the tens.
            SharpitHaptics.play(.notch(major: mark % majorEvery == 0))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(value.map { "\($0) \(unit)" } ?? "Non renseigné")
        .accessibilityAdjustableAction { direction in
            let current = value ?? resting
            let next = direction == .increment ? current + 1 : current - 1
            guard range.contains(next) else { return }
            value = next
            position = next
        }
    }

    private func tick(_ mark: Int) -> some View {
        let isMajor = mark % majorEvery == 0
        let isHalf = !isMajor && mark % (majorEvery / 2) == 0
        return VStack(spacing: 0) {
            Capsule()
                .fill(isMajor ? SharpitColor.foreground.opacity(0.55) : SharpitColor.mutedForeground.opacity(isHalf ? 0.45 : 0.28))
                .frame(width: isMajor ? 2 : 1.5, height: isMajor ? 30 : (isHalf ? 22 : 14))
            Spacer(minLength: 0)
        }
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            if isMajor {
                Text("\(mark)")
                    .font(SharpitTypography.meta.monospacedDigit())
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize()
            }
        }
    }
}

/// A date in a field well, with what it means beside it (an age). A tap opens the wheel in a
/// short sheet: in place it grew the page into a scroll, and the app's tint coloured its band.
struct SharpitDateField: View {
    let title: String
    @Binding var date: Date?
    let range: ClosedRange<Date>
    /// Where the wheel opens when nothing is picked yet.
    let resting: Date
    /// What the date means, shown beside it — « 30 ans ».
    var caption: (Date) -> String? = { _ in nil }

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(title)
            Button {
                SharpitHaptics.play(.light)
                isOpen = true
            } label: {
                HStack {
                    Text(date.map { $0.sharpitFormatted(.dateTime.day().month(.wide).year()) } ?? "Choisir")
                        .font(SharpitTypography.body)
                        .foregroundStyle(date == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                    Spacer()
                    if let date, let caption = caption(date) {
                        Text(caption)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .contentShape(.rect)
                .sharpitFieldWell(isActive: isOpen)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isOpen) {
            VStack(spacing: SharpitSpacing.sm) {
                HStack {
                    Text(title)
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer()
                    Button("OK") {
                        if date == nil { date = resting }
                        isOpen = false
                    }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                }
                DatePicker(title, selection: dateBinding, in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    // Neutral: the band is the system's, not the brand's green.
                    .tint(SharpitColor.foreground)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            }
            .padding(SharpitSpacing.pageInset)
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .sharpitSheet()
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { date ?? resting }, set: { date = $0 })
    }
}
