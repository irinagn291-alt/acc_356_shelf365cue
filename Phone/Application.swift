import SwiftUI

@main
struct FoodApplication: App {
    @StateObject private var launch = AppLaunch()
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ScreenshotLaunch.active {
                    ScreenshotRoot()
                } else {
                    normalRoot
                }
                #else
                normalRoot
                #endif
            }
            .environment(\.locale, Locale(identifier: "en_US"))
        }
    }

    private var normalRoot: some View {
        Group {
            switch launch.mode {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .webContent:
                if let url = launch.contentURL { InAppBrowser(url: url) }
                else { FeatureRoot() }
            case .nativeInterface:
                FeatureRoot()
            }
        }.task { launch.start() }
    }

}

#if DEBUG && targetEnvironment(simulator)
/// The factory passes a screen key directly, or a one-based index with the App Store flag.
enum ScreenshotLaunch {
    static let keys = ["my-shelves", "food-catalog", "barcode", "new-batch", "batch-ticket", "ledger"]
    private static let arguments = ProcessInfo.processInfo.arguments
    private static let environment = ProcessInfo.processInfo.environment

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var active: Bool {
        arguments.contains("-ReviewScreen") || arguments.contains("-AppStoreScreenshots") ||
        (environment["APPSTORE_SCREENSHOTS"].map { !["", "0", "false", "no"].contains($0.lowercased()) } ?? false)
    }

    static var key: String? {
        if arguments.contains("-ReviewScreen") { return value(after: "-ReviewScreen") }
        let indexText = value(after: "-AppStoreScreenshotScreen") ?? environment["APPSTORE_SCREENSHOT_SCREEN"]
        guard let indexText, let index = Int(indexText), (1...keys.count).contains(index) else { return nil }
        return keys[index - 1]
    }
}

@MainActor
private struct ScreenshotRoot: View {
    @StateObject private var stock: ShelfStock
    private let products: [OFFProduct]
    private let spaghetti: OFFProduct
    private let batchID: UUID
    private let draft: ShelfBatch

    init() {
        let url = Bundle.main.url(forResource: "StarterCatalog", withExtension: "json")!
        let products = (try? FoodCatalog.parse(Data(contentsOf: url), barcode: false)) ?? []
        let spaghetti = products.first { $0.id == "8076800195057" }!
        let weetabix = products.first { $0.id == "5010029000016" }!
        let pesto = products.first { $0.id == "8076809513753" }!
        let soon = ShelfDay(Calendar.current.date(byAdding: .day, value: 2, to: .now)!)
        let later = ShelfDay(Calendar.current.date(byAdding: .day, value: 30, to: .now)!)
        let pasta = ShelfBatch(id: UUID(uuidString: "11000000-0000-0000-0000-000000000001")!, product: spaghetti, quantity: 2, place: .cupboard, expiry: soon, note: "Open pack at the front")
        let cereal = ShelfBatch(id: UUID(uuidString: "11000000-0000-0000-0000-000000000002")!, product: weetabix, quantity: 1, place: .cupboard, expiry: later, note: "")
        let sauce = ShelfBatch(id: UUID(uuidString: "11000000-0000-0000-0000-000000000003")!, product: pesto, quantity: 1, place: .fridge, expiry: nil, note: "")
        var originalPasta = pasta
        originalPasta.quantity = 3
        originalPasta.expiry = later
        let adjustedPasta = ShelfBatch(id: pasta.id, product: spaghetti, quantity: 3, place: .cupboard, expiry: soon, note: pasta.note)
        let now = Date.now
        let archive = ShelfArchive(batches: [pasta, cereal, sauce], history: [
            StockMovement(time: now.addingTimeInterval(-3600 * 5), operation: .added, before: nil, after: originalPasta),
            StockMovement(time: now.addingTimeInterval(-3600 * 4), operation: .added, before: nil, after: cereal),
            StockMovement(time: now.addingTimeInterval(-3600 * 3), operation: .edited, before: originalPasta, after: adjustedPasta),
            StockMovement(time: now.addingTimeInterval(-3600 * 2), operation: .used, before: adjustedPasta, after: pasta),
            StockMovement(time: now.addingTimeInterval(-3600), operation: .added, before: nil, after: sauce)
        ])
        self.products = products
        self.spaghetti = spaghetti
        self.batchID = pasta.id
        self.draft = pasta
        _stock = StateObject(wrappedValue: ShelfStock(demo: archive))
    }

    var body: some View {
        Group {
            switch ScreenshotLaunch.key {
            case "my-shelves": FeatureRoot(demoStock: stock, ledger: false)
            case "food-catalog": CatalogPicker(demoProducts: products) { _ in }
            case "barcode": ScanSheet { _ in }
            case "new-batch": ShelfEditor(product: spaghetti, demoDraft: draft) { stock.save($0) }
            case "batch-ticket":
                NavigationStack { ShelfDetail(stock: stock, id: batchID, labelExpanded: true) }
            case "ledger": FeatureRoot(demoStock: stock, ledger: true)
            default: Text("Unknown screenshot screen")
            }
        }
        .tint(ShelfInk.blue)
        .foregroundStyle(ShelfInk.navy)
        .preferredColorScheme(.light)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}
#endif
