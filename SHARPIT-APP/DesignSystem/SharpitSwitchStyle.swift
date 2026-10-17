import SwiftUI

/// Every switch in the app: the native switch on a lime track. The app tint is `primary`,
/// near-white in dark mode, which left a white knob on a white track. Set by `AccountGate` for
/// the app and by `sharpitSheet()` for each sheet, which does not inherit it.
struct SharpitSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(SharpitColor.highlight)
    }
}

extension ToggleStyle where Self == SharpitSwitchStyle {
    static var sharpitSwitch: SharpitSwitchStyle { SharpitSwitchStyle() }
}
