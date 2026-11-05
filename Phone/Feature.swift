import SwiftUI

private enum ShelfTab: String, CaseIterable {
    case stock = "Shelves", history = "Diary", calendar = "Calendar", insights = "Insights"
    var symbol: String { switch self { case .stock: "cabinet.fill"; case .history: "book.closed"; case .calendar: "calendar"; case .insights: "chart.bar" } }
}
private enum ShelfWindow: String, CaseIterable { case all = "All batches", soon = "Check soon", undated = "Undated" }
private enum ShelfSort: String, CaseIterable { case expiry = "By date", name = "By name", quantity = "By quantity" }

struct FeatureRoot: View {
    @StateObject private var stock: ShelfStock
    @State private var tab = ShelfTab.stock
    @State private var window = ShelfWindow.all
    @State private var place: ShelfPlace?
    @State private var order = ShelfSort.expiry
    @State private var path = [UUID]()
    @State private var picker = false
    @State private var contact = false
    @State private var stocktake = false
    @State private var selection: OFFProduct?
    @State private var newProduct: OFFProduct?
    @State private var today = Date.now
    @Environment(\.scenePhase) private var phase

    init() {
        _stock = StateObject(wrappedValue: ShelfStock.shared)
    }

    #if DEBUG && targetEnvironment(simulator)
    init(demoStock: ShelfStock, ledger: Bool) {
        _stock = StateObject(wrappedValue: demoStock)
        _tab = State(initialValue: ledger ? .history : .stock)
    }
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        HStack(spacing: 7) {
                            Image(systemName: "shippingbox.fill")
                            Text("Shelf365Cue").font(.headline.weight(.black))
                        }.foregroundStyle(ShelfInk.blue)
                        Spacer()
                        Text(today.formatted(.dateTime.day().month(.abbreviated).locale(.init(identifier: "en_US"))))
                            .font(.caption.monospaced().bold())
                    }
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(ShelfInk.blue).frame(height: 1) }

                    HStack {
                        Text(tab == .stock ? "My shelves" : tab.rawValue).font(.system(.largeTitle, design: .rounded, weight: .black))
                        Spacer()
                        Text("0\((ShelfTab.allCases.firstIndex(of: tab) ?? 0) + 1) / 04")
                            .font(.caption.monospaced().bold()).foregroundStyle(ShelfInk.blue)
                            .accessibilityHidden(true)
                    }
                    switch tab {
                    case .stock: inventory
                    case .history: PantryDiary(stock: stock)
                    case .calendar: PantryCalendar(stock: stock)
                    case .insights: PantryInsights(stock: stock)
                    }
                    Button { contact = true } label: {
                        Label("Contact Us", systemImage: "envelope")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("shelf.contact")
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(ShelfInk.paper)
            .id(tab)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(ShelfTab.allCases, id: \.self) { item in
                        Button { tab = item } label: {
                            VStack(spacing: 5) {
                                Image(systemName: item.symbol).font(.title3)
                                Text(item.rawValue).font(.caption2.bold())
                            }.padding(.vertical, 10).frame(maxWidth: .infinity)
                                .foregroundStyle(tab == item ? .white : ShelfInk.blue)
                                .background(tab == item ? ShelfInk.blue : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tab." + item.rawValue.lowercased())
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                }.padding(5).background(ShelfInk.label, in: Capsule()).overlay { Capsule().strokeBorder(ShelfInk.line) }
                    .frame(maxWidth: 470).padding(.horizontal, 20).padding(.vertical, 7)
                    .frame(maxWidth: .infinity).background(ShelfInk.paper)
            }
            .navigationDestination(for: UUID.self) { id in ShelfDetail(stock: stock, id: id) }
        }
        .tint(ShelfInk.blue).foregroundStyle(ShelfInk.navy).preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .sheet(isPresented: $contact) { ContactPage() }
        .sheet(isPresented: $stocktake) { StocktakeSheet(stock: stock) }
        .sheet(isPresented: $picker, onDismiss: {
            newProduct = selection
            selection = nil
        }) {
            CatalogPicker(stock: stock) { product in selection = product }
        }
        .sheet(item: $newProduct) { product in
            ShelfEditor(product: product) { batch in
                guard stock.save(batch) else { return false }
                window = .all
                place = nil
                return true
            }
        }
        .alert("Pantry archive", isPresented: Binding(get: { stock.problem != nil }, set: { if !$0 { stock.problem = nil } })) {
            Button("Close") { stock.problem = nil }
        } message: { Text(stock.problem ?? "") }
        .onAppear { stock.publish() }
        .onChange(of: stock.archive.batches) { _, _ in stock.publish() }
        .onChange(of: phase) { _, next in if next == .active { today = .now; stock.publish() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = .now }
        .onOpenURL { url in
            guard url.scheme == "shelfcue", url.host == "dashboard" else { return }
            selection = nil
            picker = false
            newProduct = nil
            tab = .stock
            path = []
            place = nil
            window = .all
            order = .expiry
        }
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        ShelfKicker(text: "Pantry overview").foregroundStyle(ShelfInk.lime)
                        Text("\(stock.archive.batches.reduce(0) { $0 + $1.quantity })").font(.system(size: 54, weight: .black, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        Text(stock.archive.batches.reduce(0) { $0 + $1.quantity } == 1 ? "pack on hand" : "packs on hand").font(.subheadline.weight(.medium))
                    }
                    Spacer(minLength: 0)
                    ShelfPrint().frame(maxWidth: 145).frame(height: 101)
                }
                Divider().overlay(.white.opacity(0.4))
                Label(stock.archive.batches.isEmpty ? "Start with a pack from your kitchen" : urgentSummary,
                      systemImage: "calendar.badge.clock")
                    .font(.subheadline.bold())
            }.padding(17).foregroundStyle(.white)
                .background(ShelfInk.blue, in: RoundedRectangle(cornerRadius: 18))
            Button { picker = true } label: {
                Label("Find a product", systemImage: "plus.magnifyingglass")
            }.buttonStyle(ShelfAction(secondary: true)).accessibilityIdentifier("shelf.find")
            VStack(alignment: .leading, spacing: 10) {
                Text("How your shelves work").font(.headline)
                Text("1. Find or scan a product and save a batch.\n2. Open its ticket to mark packs used or discarded.\n3. Run a stocktake to compare saved quantities with your kitchen.").font(.subheadline)
                Button { stocktake = true } label: { Label("Start stocktake", systemImage: "checklist") }
                    .buttonStyle(ShelfAction()).disabled(stock.archive.batches.isEmpty).accessibilityIdentifier("shelf.stocktake")
                if stock.archive.batches.isEmpty { Text("Add your first batch to start a stocktake.").font(.caption) }
            }.padding(16).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 14))
            if stock.archive.batches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ShelfKicker(text: "First delivery").foregroundStyle(ShelfInk.blue)
                    Text("What's on your shelf?").font(.title3.weight(.bold))
                    Text("Search by name or barcode. Add the number of packs, where you keep them and the date on the label.")
                        .font(.subheadline)
                }.padding(.vertical, 6)
            } else {
                controls
                if filtered.isEmpty {
                    ContentUnavailableView("No matching batches", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try another location or date filter."))
                    Button("Clear filters") { place = nil; window = .all }.buttonStyle(ShelfAction(secondary: true))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { batch in
                            NavigationLink(value: batch.id) { ShelfTicket(batch: batch, today: today) }.buttonStyle(.plain)
                                .accessibilityIdentifier("shelf.batch." + batch.product.id)
                        }
                    }
                }
            }
        }
    }

    private var soonCount: Int {
        stock.archive.batches.filter { ($0.expiry?.distance(from: today) ?? Int.max) <= 3 }.count
    }
    private var urgentSummary: String {
        let undated = stock.archive.batches.filter { $0.expiry == nil }.count
        if undated == stock.archive.batches.count { return "No package dates recorded" }
        let summary = soonCount == 0 ? "No recorded dates due soon" : "Past or approaching date · \(soonCount)"
        return undated > 0 ? summary + " · \(undated) undated" : summary
    }
    private var filtered: [ShelfBatch] {
        let batches = stock.archive.batches.filter { batch in
            guard place == nil || batch.place == place else { return false }
            switch window {
            case .all: return true
            case .undated: return batch.expiry == nil
            case .soon: return (batch.expiry?.distance(from: today) ?? Int.max) <= 3
            }
        }
        let sorted = ShelfStock.nearest(batches)
        switch order {
        case .expiry: return sorted
        case .name: return sorted.sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
        case .quantity: return sorted.sorted { $0.quantity > $1.quantity }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Batches").font(.title2.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(ShelfWindow.allCases, id: \.self) { item in
                        Button(item.rawValue) { window = item }
                            .font(.subheadline.bold()).padding(.horizontal, 13).frame(minHeight: 44)
                            .background(window == item ? ShelfInk.lime : ShelfInk.label, in: Capsule())
                            .overlay { Capsule().strokeBorder(window == item ? ShelfInk.navy : ShelfInk.line) }
                            .buttonStyle(.plain).accessibilityAddTraits(window == item ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            HStack {
                Menu {
                    Picker("Location", selection: $place) {
                        Text("All locations").tag(nil as ShelfPlace?)
                        ForEach(ShelfPlace.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                } label: { Label(place?.rawValue ?? "All locations", systemImage: "line.3.horizontal.decrease.circle") }
                Spacer()
                Menu {
                    Picker("Sort", selection: $order) {
                        ForEach(ShelfSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label(order.rawValue, systemImage: "arrow.up.arrow.down") }
            }.font(.caption.bold()).frame(minHeight: 44)
            if window == .soon { Text("Includes past dates and dates within the next three days.").font(.caption) }
        }
    }
}

private struct ShelfTicket: View {
    let batch: ShelfBatch
    let today: Date
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ShelfKicker(text: batch.place.rawValue).foregroundStyle(ShelfInk.blue)
                Text(batch.product.name).font(.headline)
                ShelfExpiry(batch: batch, today: today)
            }
            Spacer()
            VStack {
                Text("\(batch.quantity)").font(.title2.monospacedDigit().bold())
                Text(batch.quantity == 1 ? "pack" : "packs").font(.caption)
            }.foregroundStyle(ShelfInk.blue)
            Image(systemName: "chevron.right").font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfInk.line) }
    }
}
