import SwiftUI

struct CatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var offline = FoodCatalog.offline()
    @State private var results: [OFFProduct] = []
    @State private var searched = false
    @State private var loading = false
    @State private var message: String?
    @State private var fetchingCode: String?
    @State private var incomplete: OFFProduct?
    @State private var scanning = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    private let stock: ShelfStock?
    let onPick: (OFFProduct) -> Void

    init(stock: ShelfStock? = nil, onPick: @escaping (OFFProduct) -> Void) {
        self.stock = stock
        self.onPick = onPick
    }

    #if DEBUG && targetEnvironment(simulator)
    init(demoProducts: [OFFProduct], onPick: @escaping (OFFProduct) -> Void) {
        self.onPick = onPick
        self.stock = nil
        _offline = State(initialValue: demoProducts)
    }
    #endif

    private var input: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var visibleOffline: [OFFProduct] {
        offline.filter { input.isEmpty || [$0.name, $0.brand, $0.id].contains { $0.localizedCaseInsensitiveContains(input) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Name, brand or barcode", text: $text)
                            .focused($focused).autocorrectionDisabled().submitLabel(.search)
                            .onSubmit { search(input) }.accessibilityIdentifier("catalog.query")
                        if !text.isEmpty {
                            Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).accessibilityLabel("Clear")
                        }
                    }
                    HStack {
                        Button("Search online") { search(input) }
                            .disabled(input.isEmpty || loading).accessibilityIdentifier("catalog.search")
                        Spacer()
                        Button { focused = false; scanning = true } label: { Label("Scan", systemImage: "barcode.viewfinder") }
                    }.buttonStyle(.borderless)
                } header: { Text("Open Food Facts") }
                if loading { ProgressView(fetchingCode == nil ? "Searching the catalog…" : "Opening the full label…") }
                if let problem = stock?.problem { Text(problem).foregroundStyle(.red) }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if searched && !results.isEmpty {
                    Section("Search results") { ForEach(results) { row($0, online: true) } }
                }
                if !visibleOffline.isEmpty && results.isEmpty {
                    Section {
                        ForEach(visibleOffline) { row($0, online: false) }
                    } header: { Text("Available offline") } footer: {
                        Text("Starter products and labels you open are stored on this device.")
                    }
                }
                Section {
                    Link("Open Food Facts · community data", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("Database license · ODbL", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Link("Photo license · CC BY-SA", destination: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!)
                } footer: { Text("Recipes can change. Check the printed package for current ingredients.") }
                .font(.footnote)
            }
            .navigationTitle("Food catalog").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: text) { _, new in
                // Scanning starts a request for the new input in the same transaction.
                if new != submitted { reset() }
            }
            .sheet(isPresented: $scanning) {
                ScanSheet(onCode: { code in scanning = false; text = code; search(code, source: .camera) },
                          onTyped: { code in scanning = false; text = code; search(code, source: .typed) })
            }
            .confirmationDialog("Full label unavailable", isPresented: Binding(get: { incomplete != nil }, set: { if !$0 { incomplete = nil } }), presenting: incomplete) { product in
                Button("Use available information") { finish(product) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("You can use the saved or indexed information now. Some fields may be missing.") }
            .onDisappear { task?.cancel() }
        }
    }

    @State private var submitted: String?
    private func reset() {
        task?.cancel()
        submitted = nil
        fetchingCode = nil
        incomplete = nil
        results = []; message = nil; loading = false; searched = false
    }

    private func search(_ query: String, source: ScanRecord.Source = .typed) {
        guard !query.isEmpty else { return }
        reset()
        submitted = query
        focused = false
        let isCode = query.allSatisfy { $0.isASCII && $0.isNumber }
        if query.allSatisfy({ $0.isNumber }) && (!isCode || !(4...14).contains(query.count)) {
            message = "Check the barcode digits on the package."
            return
        }
        let scanID = isCode ? stock?.logScan(query, source: source) : nil
        if isCode, let saved = offline.first(where: { $0.id == query }) {
            results = [saved]; searched = true
            message = "Saved product found. Select it to add a batch. Check the package for current details."
            if let scanID { stock?.finishScan(scanID, product: saved, result: .found) }
            return
        }
        loading = true
        task = Task { @MainActor in
            do {
                let found = try await FoodCatalog.lookup(query)
                try Task.checkCancellation()
                results = found; searched = true
                if let scanID { stock?.finishScan(scanID, product: found.first, result: found.isEmpty ? .missing : .found) }
                if found.isEmpty { message = "No matches. Try another name or scan the barcode." }

            } catch {
                guard !Task.isCancelled else { return }
                message = (error as? CatalogFailure)?.errorDescription ?? CatalogFailure.unavailable.errorDescription
                if let scanID {
                    let missing: Bool
                    if case CatalogFailure.notFound = error { missing = true } else { missing = false }
                    stock?.finishScan(scanID, product: nil, result: missing ? .missing : .failed)
                }
            }
            loading = false
        }
    }

    private func finish(_ product: OFFProduct) {
        #if DEBUG && targetEnvironment(simulator)
        if !ScreenshotLaunch.active { FoodCatalog.remember([product]) }
        #else
        FoodCatalog.remember([product])
        #endif
        dismiss()
        onPick(product)
    }

    private func choose(_ product: OFFProduct, online: Bool) {
        // Barcode and offline rows already carry their complete stored record.
        guard online, submitted?.allSatisfy({ $0.isNumber }) != true else { finish(product); return }
        task?.cancel()
        fetchingCode = product.id
        loading = true
        task = Task { @MainActor in
            do {
                let full = try await FoodCatalog.lookup(product.id)
                try Task.checkCancellation()
                guard let label = full.first else { throw CatalogFailure.notFound }
                loading = false
                fetchingCode = nil
                finish(label)
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                fetchingCode = nil
                incomplete = offline.first { $0.id == product.id } ?? product
            }
        }
    }

    private func row(_ product: OFFProduct, online: Bool) -> some View {
        Button {
            choose(product, online: online)
        } label: {
            HStack(spacing: 13) {
                AsyncImage(url: product.imageURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "shippingbox").foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 54).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.headline).foregroundStyle(.primary)
                    if !product.brand.isEmpty { Text(product.brand).font(.subheadline).foregroundStyle(.secondary) }
                    Text(product.id).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 3)
        }.disabled(fetchingCode != nil).accessibilityIdentifier("catalog.product." + product.id)
    }
}
