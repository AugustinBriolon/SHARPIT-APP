import CoreText
import Foundation

/// Registers the bundled brand typefaces with the text system at launch.
///
/// Registration is done in code rather than through `UIAppFonts` so that adding a face is
/// a file drop: `scripts/fetch-brand-fonts.sh` writes into `Resources/Fonts`, the
/// synchronized Xcode group picks the files up, and this walks whatever it finds. Nothing
/// here hard-codes a filename, so a weight the ramp does not ask for is harmless and a
/// missing one degrades to the system face rather than crashing (see `SharpitTypography`).
enum SharpitFonts {
    /// Font file extensions Core Text can register.
    private static let supportedExtensions = ["ttf", "otf", "ttc"]

    /// Registers every bundled face. Safe to call more than once.
    @discardableResult
    static func register(in bundle: Bundle = .main) -> Int {
        urls(in: bundle).reduce(into: 0) { registered, url in
            if register(url) { registered += 1 }
        }
    }

    private static func urls(in bundle: Bundle) -> [URL] {
        supportedExtensions
            .flatMap { bundle.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        guard !didRegister, let failure = error?.takeRetainedValue() else {
            return didRegister
        }

        // A face already registered by an earlier call is not a failure.
        let code = CFErrorGetCode(failure)
        return code == CTFontManagerError.alreadyRegistered.rawValue
    }
}
