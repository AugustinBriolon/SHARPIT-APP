import SwiftUI
import Vision
import VisionKit

/// The camera reading a food's barcode, through VisionKit's live scanner. Images never leave
/// the iPhone: only the digits read go to the server, which asks Open Food Facts.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    /// The scanner needs a camera and the Neural Engine, and the athlete's permission; without
    /// any of them the scan button is not offered.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    /// Started here rather than when made: the scanner only runs once its view is on screen.
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        /// One code per sighting: the scanner reports the same label many times a second.
        private var lastCode: String?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            lastCode = nil
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                guard case .barcode(let barcode) = item,
                      let code = FoodBarcode.normalized(barcode.payloadStringValue),
                      code != lastCode
                else { continue }
                lastCode = code
                SharpitHaptics.play(.soft)
                onCode(code)
                return
            }
        }
    }
}
