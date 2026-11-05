import SwiftUI
import Charts

enum PantryPeriod: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", all = "All time"
    var id: Self { self }
    func start(now: Date) -> Date {
        let days: Int
        switch self { case .week: days = 6; case .month: days = 29; case .quarter: days = 89; case .all: return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: now)) ?? now
    }
}

struct PantryReport {
    let movements: [StockMovement]
    let scans: [ScanRecord]
    let stocktakes: [StocktakeRecord]
    init(archive: ShelfArchive, period: PantryPeriod, now: Date = .now) {
        let start = period.start(now: now)
        movements = archive.history.filter { $0.time >= start && $0.time <= now }
        scans = archive.scans.filter { $0.time >= start && $0.time <= now }
        stocktakes = archive.stocktakes.filter { $0.time >= start && $0.time <= now }
    }
    var stocked: Int { movements.filter { $0.operation == .added }.reduce(0) { $0 + $1.difference } }
    var used: Int { -movements.filter { $0.operation == .used }.reduce(0) { $0 + $1.difference } }
    var discarded: Int { -movements.filter { $0.operation == .discarded }.reduce(0) { $0 + $1.difference } }
    var adjustment: Int { movements.filter { $0.operation == .edited || $0.operation == .counted }.reduce(0) { $0 + $1.difference } }
    var matchedScans: Int { scans.filter { $0.result == .found }.count }
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let used: Int
        let discarded: Int
    }
    var days: [Day] {
        Dictionary(grouping: movements.filter { $0.operation == .used || $0.operation == .discarded }, by: { Calendar.current.startOfDay(for: $0.time) })
            .map { date, records in Day(date: date,
                used: -records.filter { $0.operation == .used }.reduce(0) { $0 + $1.difference },
                discarded: -records.filter { $0.operation == .discarded }.reduce(0) { $0 + $1.difference }) }
            .sorted { $0.date < $1.date }
    }
}

struct PantryDayEvents {
    let batches: [ShelfBatch]
    let movements: [StockMovement]
    let scans: [ScanRecord]
    let notes: [PantryNote]
    let stocktakes: [StocktakeRecord]
    init(archive: ShelfArchive, day: ShelfDay) {
        batches = archive.batches.filter { $0.expiry == day }
        movements = archive.history.filter { ShelfDay($0.time) == day }
        scans = archive.scans.filter { ShelfDay($0.time) == day }
        notes = archive.notes.filter { ShelfDay($0.date) == day }
        stocktakes = archive.stocktakes.filter { ShelfDay($0.time) == day }
    }
    var hasActivity: Bool { !movements.isEmpty || !notes.isEmpty || !stocktakes.isEmpty }
    var isEmpty: Bool { batches.isEmpty && scans.isEmpty && !hasActivity }
}

struct PantryMetric: View {
    let name: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(name, systemImage: symbol).font(.caption.bold())
            Text(value).font(.system(.title, design: .rounded, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, minHeight: 75, alignment: .leading).padding(14)
            .background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(ShelfInk.line) }
    }
}

struct PantryInsights: View {
    @ObservedObject var stock: ShelfStock
    @State private var period = PantryPeriod.month
    private var report: PantryReport { PantryReport(archive: stock.archive, period: period) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ShelfKicker(text: "Know your pantry").foregroundStyle(ShelfInk.blue)
            Text("Your stock, in numbers").font(.title2.bold())
            PantryMetric(name: "Packs on hand now", value: "\(stock.archive.batches.reduce(0) { $0 + $1.quantity })", symbol: "shippingbox")
            Picker("Report period", selection: $period) { ForEach(PantryPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PantryMetric(name: "Packs stocked", value: "\(report.stocked)", symbol: "tray.and.arrow.down")
                PantryMetric(name: "Packs used", value: "\(report.used)", symbol: "fork.knife")
                PantryMetric(name: "Packs discarded", value: "\(report.discarded)", symbol: "minus.circle")
                PantryMetric(name: "Barcode lookups", value: "\(report.scans.count)", symbol: "barcode.viewfinder")
            }
            Text("Used & discarded").font(.title3.bold())
            if report.days.isEmpty {
                Text("Mark packs as used or discarded from a batch ticket to see your daily trend.").font(.subheadline)
            } else {
                Chart(report.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Packs", day.used)).foregroundStyle(by: .value("Activity", "Used"))
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Packs", day.discarded)).foregroundStyle(by: .value("Activity", "Discarded"))
                }
                .chartForegroundStyleScale(["Used": ShelfInk.blue, "Discarded": Color.orange])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, (Calendar.current.dateComponents([.day], from: report.days.first!.date, to: report.days.last!.date).day ?? 0) / 4))) {
                        AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }.frame(height: 190)
            }
            Text("Current storage").font(.title3.bold())
            ForEach(ShelfPlace.allCases) { place in
                HStack {
                    Label(place.rawValue, systemImage: place.icon)
                    Spacer()
                    Text("\(stock.archive.batches.filter { $0.place == place }.reduce(0) { $0 + $1.quantity }) packs").bold()
                }.padding(12).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("\(report.matchedScans) matched barcode lookups · \(report.stocktakes.count) stocktakes").font(.subheadline.bold())
            Text("Quantity corrections: \(report.adjustment.formatted(.number.sign(strategy: .always()))) packs. Counts track packages, not servings. Scanning a barcode does not add stock; save a batch to add it. Undone movements are excluded from reports.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PantryDiary: View {
    @ObservedObject var stock: ShelfStock
    @State private var section = "Activity"
    @State private var note: PantryNote?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your pantry, day by day").font(.title2.bold())
            Text("Stock movements and barcode lookups are recorded automatically. Add your own notes about products, meals or shopping.").font(.subheadline)
            Button { note = PantryNote(date: .now, text: "") } label: { Label("Add a note", systemImage: "square.and.pencil") }
                .buttonStyle(ShelfAction(secondary: true)).accessibilityIdentifier("diary.add")
            Picker("Diary section", selection: $section) {
                ForEach(["Activity", "Scans", "Notes"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            if section == "Activity" {
                ForEach(stock.archive.stocktakes.sorted { $0.time > $1.time }.prefix(5)) { check in
                    NavigationLink { StocktakeReceipt(check: check) } label: {
                        Label("Stocktake · \(check.time.formatted(.dateTime.month(.abbreviated).day().locale(.init(identifier: "en_US")))) · \(check.counts.count) batches", systemImage: "checklist")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(ShelfInk.lime, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                ShelfJournal(stock: stock)
            } else if section == "Scans" {
                if stock.archive.scans.isEmpty {
                    ContentUnavailableView("No barcode lookups yet", systemImage: "barcode.viewfinder", description: Text("Open Find a product, then scan a package or search its barcode. Both are saved here."))
                }
                ForEach(stock.archive.scans.sorted { $0.time > $1.time }) { ScanRecordCard(scan: $0) }
            } else {
                if stock.archive.notes.isEmpty {
                    ContentUnavailableView("A fresh page", systemImage: "book", description: Text("Keep a dated note and optionally link it to a product."))
                }
                ForEach(stock.archive.notes.sorted { $0.date > $1.date }) { entry in
                    Button { note = entry } label: { PantryNoteCard(note: entry) }.buttonStyle(.plain)
                }
            }
        }.sheet(item: $note) { PantryNoteEditor(stock: stock, original: $0) }
    }
}

struct ScanRecordCard: View {
    let scan: ScanRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Label(scan.source.rawValue, systemImage: "barcode.viewfinder"); Spacer(); Text(scan.time, format: .dateTime.month(.abbreviated).day().hour().minute()) }.font(.caption)
            Text(scan.product?.name ?? scan.code).font(.headline)
            Text(scan.result.rawValue).font(.subheadline.bold()).foregroundStyle(ShelfInk.blue)
            Text(scan.code).font(.caption.monospaced())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PantryNoteCard: View {
    let note: PantryNote
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.date, format: .dateTime.month(.abbreviated).day().year()).font(.caption.bold()).foregroundStyle(ShelfInk.blue)
            if let product = note.product { Label(product.name, systemImage: "shippingbox").font(.headline) }
            Text(note.text).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PantryNoteEditor: View {
    @ObservedObject var stock: ShelfStock
    let original: PantryNote
    @State private var text: String
    @State private var date: Date
    @State private var productID: String?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    init(stock: ShelfStock, original: PantryNote) {
        self.stock = stock; self.original = original
        _text = State(initialValue: original.text); _date = State(initialValue: original.date)
        _productID = State(initialValue: original.product?.id)
    }
    private var products: [OFFProduct] {
        var seen = Set<String>()
        return ((original.product.map { [$0] } ?? []) + stock.archive.batches.map(\.product) + stock.archive.history.compactMap { $0.batch?.product } + stock.archive.scans.compactMap(\.product))
            .filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Product (optional)", selection: $productID) {
                    Text("General note").tag(nil as String?)
                    ForEach(products) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("Your note") {
                    TextField("What would you like to remember?", text: $text, axis: .vertical).lineLimit(5...10)
                        .focused($focused).accessibilityIdentifier("diary.text")
                    Text("\(text.count)/2000 characters").font(.caption)
                }
                if let problem = stock.problem { Text(problem).foregroundStyle(.red) }
                if stock.archive.notes.contains(where: { $0.id == original.id }) {
                    Button("Delete note", role: .destructive) { confirmDelete = true }
                }
            }.scrollContentBackground(.hidden).background(ShelfInk.paper)
            .navigationTitle("Diary note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if stock.saveNote(PantryNote(id: original.id, date: date, text: text, product: products.first { $0.id == productID })) { dismiss() }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000).accessibilityIdentifier("diary.save")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .confirmationDialog("Delete this diary note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { if stock.deleteNote(original.id) { dismiss() } }
            }
        }
    }
}
