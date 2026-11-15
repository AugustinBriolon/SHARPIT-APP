import SwiftUI

/// Every switch in the app: the native switch on the brand's lime, darkened as the mock-ups draw it. The app tint is `primary`,
/// near-white in dark mode, which left a white knob on a white track. Set by `AccountGate` for
/// the app and by `sharpitSheet()` for each sheet, which does not inherit it.
struct SharpitSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(SharpitColor.pillarRecovery)
    }
}

extension ToggleStyle where Self == SharpitSwitchStyle {
    static var sharpitSwitch: SharpitSwitchStyle { SharpitSwitchStyle() }
}
