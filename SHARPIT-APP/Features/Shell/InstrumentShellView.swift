import SwiftUI

struct InstrumentShellView<Accessory: View>: View {
    let destination: ShellDestination
    @ViewBuilder var accessory: () -> Accessory

    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: SharpitSpacing.sm),
        GridItem(.flexible(), spacing: SharpitSpacing.sm),
    ]

    init(destination: ShellDestination, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.destination = destination
        self.accessory = accessory
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: SharpitSpacing.section) {
                    VStack(spacing: SharpitSpacing.md) {
                        InstrumentHeroMark(
                            symbolName: destination.systemImage,
                            cue: destination.horizonCue
                        )
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 10)
                    }
                    .padding(.top, SharpitSpacing.md)

                    LazyVGrid(columns: columns, spacing: SharpitSpacing.sm) {
                        ForEach(Array(destination.surfaces.enumerated()), id: \.element.id) { index, surface in
                            InstrumentMarkTile(
                                symbolName: surface.symbolName,
                                label: surface.label
                            )
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 8)
                            .animation(
                                SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: index)),
                                value: revealed
                            )
                        }
                    }

                    accessory()
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.lg)
            }
            .background(SharpitCanvasBackground())
            .modifier(ScrollUnderGlass())
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .onAppear(perform: runArrival)
        }
    }

    private func runArrival() {
        if SharpitMotion.reduceMotion || reduceMotion {
            revealed = true
            return
        }
        SharpitMotion.run {
            revealed = true
        }
    }
}
