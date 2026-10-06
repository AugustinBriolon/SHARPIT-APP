import SwiftUI
import UIKit

/// A file made on demand, handed to the system's share sheet once it exists — `ShareLink`
/// needs its item before the tap, and an export is only written after it.
struct SharpitSharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system's share sheet (`UIActivityViewController`) for one file: AirDrop, Fichiers, Mail…
/// Presented with `.sheet(item:)`; the system draws its own chrome.
struct SharpitShareSheet: UIViewControllerRepresentable {
    let file: SharpitSharedFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
