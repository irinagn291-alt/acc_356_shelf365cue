import AVFoundation
import SwiftUI
import VisionKit

struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ready = false
    @State private var issue = ""
    @State private var denied = false
    @State private var typed = ""
    let onTyped: ((String) -> Void)?
    let onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void, onTyped: ((String) -> Void)? = nil) {
        self.onCode = onCode
        self.onTyped = onTyped
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotLaunch.active {
            _issue = State(initialValue: "Type the barcode from the package on this device.")
        }
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if ready && issue.isEmpty {
                    ScannerCamera(onCode: onCode, onFailure: { issue = "The camera is unavailable. Type the barcode from the package into the search field." })
                } else if !issue.isEmpty {
                    ContentUnavailableView {
                        Label("Scanner unavailable", systemImage: "barcode.viewfinder")
                    } description: { Text(issue) } actions: {
                        if denied, let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
                        TextField("Barcode digits", text: $typed).keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 280).accessibilityIdentifier("scanner.manual")
                        Button("Look up barcode") { (onTyped ?? onCode)(typed) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!(4...14).contains(typed.count) || !typed.allSatisfy { $0.isASCII && $0.isNumber })
                            .accessibilityIdentifier("scanner.lookup")
                    }
                } else { ProgressView("Preparing camera") }
            }
            .navigationTitle("Barcode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                #if DEBUG && targetEnvironment(simulator)
                if ScreenshotLaunch.active { return }
                #endif
                guard DataScannerViewController.isSupported else {
                    issue = "Type the barcode from the package on this device."
                    return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                denied = !allowed
                if allowed && DataScannerViewController.isAvailable { ready = true }
                else { issue = "Type the barcode or check camera access in Settings." }
            }
        }
    }
}

private struct ScannerCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onFailure: () -> Void
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let owner: ScannerCamera
        var handled = false
        init(_ owner: ScannerCamera) { self.owner = owner }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(item) in addedItems {
                guard !handled, let code = item.payloadStringValue else { continue }
                handled = true
                dataScanner.stopScanning()
                owner.onCode(code)
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            owner.onFailure()
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])], qualityLevel: .balanced, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        Task { @MainActor in
            do { try controller.startScanning() } catch { onFailure() }
        }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
}
