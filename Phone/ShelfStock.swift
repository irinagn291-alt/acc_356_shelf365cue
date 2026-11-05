import Foundation
import SwiftUI

struct ShelfDay: Codable, Equatable, Comparable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    init(_ date: Date) {
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    var date: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    func distance(from reference: Date) -> Int {
        Self.calendar.dateComponents([.day], from: Self.calendar.startOfDay(for: reference), to: Self.calendar.startOfDay(for: date)).day ?? 0
    }

    var label: String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_US")))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

enum ShelfPlace: String, CaseIterable, Codable, Identifiable {
    case cupboard = "Cupboard", fridge = "Fridge", freezer = "Freezer"
    var id: Self { self }
    var icon: String {
        switch self {
        case .cupboard: "cabinet"
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        }
    }
}

struct ShelfBatch: Codable, Identifiable, Equatable {
    var id = UUID()
    let product: OFFProduct
    var quantity: Int
    var place: ShelfPlace
    var expiry: ShelfDay?
    var note: String
    var expiryLabel: String { expiry.map { "Date · " + $0.label } ?? "Undated" }
    var companionDetail: String {
        [place.rawValue, quantity == 1 ? "1 pack" : "\(quantity) packs", expiryLabel].joined(separator: " · ")
    }
}

enum StockOperation: String, Codable {
    case added = "Stocked", edited = "Adjusted", used = "Used", discarded = "Discarded", counted = "Counted"
    var symbol: String {
        switch self {
        case .added: "tray.and.arrow.down"
        case .edited: "pencil"
        case .used: "fork.knife"
        case .discarded: "minus.circle"
        case .counted: "checklist"
        }
    }
}

struct StockMovement: Identifiable, Codable {
    var id = UUID()
    let time: Date
    let operation: StockOperation
    let before: ShelfBatch?
    let after: ShelfBatch?
    var batch: ShelfBatch? { after ?? before }
    var difference: Int { (after?.quantity ?? 0) - (before?.quantity ?? 0) }
}

struct ScanRecord: Codable, Identifiable {
    enum Source: String, Codable { case camera = "Camera", typed = "Typed barcode" }
    enum Result: String, Codable { case pending = "Not completed", found = "Product found", missing = "No matching product", failed = "Lookup unavailable" }
    var id = UUID()
    var time = Date()
    let code: String
    let source: Source
    var result: Result = .pending
    var product: OFFProduct?
}

struct PantryNote: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
    var product: OFFProduct?
}

struct StocktakeRecord: Codable, Identifiable {
    struct Count: Codable, Identifiable {
        var id: UUID { batch.id }
        let batch: ShelfBatch
        let actual: Int
    }
    var id = UUID()
    var time = Date()
    let counts: [Count]
    var difference: Int { counts.reduce(0) { $0 + $1.actual - $1.batch.quantity } }
}

struct ShelfArchive: Codable {
    var batches = [ShelfBatch]()
    var history = [StockMovement]()
    var scans = [ScanRecord]()
    var notes = [PantryNote]()
    var stocktakes = [StocktakeRecord]()

    init(batches: [ShelfBatch] = [], history: [StockMovement] = [], scans: [ScanRecord] = [], notes: [PantryNote] = [], stocktakes: [StocktakeRecord] = []) {
        self.batches = batches; self.history = history; self.scans = scans; self.notes = notes; self.stocktakes = stocktakes
    }
    enum CodingKeys: String, CodingKey { case batches, history, scans, notes, stocktakes }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        batches = try data.decode([ShelfBatch].self, forKey: .batches)
        history = try data.decode([StockMovement].self, forKey: .history)
        scans = try data.decodeIfPresent([ScanRecord].self, forKey: .scans) ?? []
        notes = try data.decodeIfPresent([PantryNote].self, forKey: .notes) ?? []
        stocktakes = try data.decodeIfPresent([StocktakeRecord].self, forKey: .stocktakes) ?? []
    }
}

@MainActor final class ShelfStock: ObservableObject {
    static let shared = ShelfStock()
    @Published private(set) var archive = ShelfArchive()
    @Published var problem: String?
    private let file: URL
    private var readable = true
    #if DEBUG && targetEnvironment(simulator)
    private var isDemo = false

    init(demo: ShelfArchive) {
        // This store never reads or writes the user's archive or companion snapshot.
        file = URL.temporaryDirectory.appending(path: "ShelfCue.screenshot-unused")
        archive = demo
        isDemo = true
    }
    #endif

    init(file: URL = URL.applicationSupportDirectory.appending(path: "ShelfCue.stock.v1.json")) {
        self.file = file
        do {
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(ShelfArchive.self, from: data)
            guard decoded.batches.allSatisfy({ (1...9999).contains($0.quantity) }),
                  Set(decoded.batches.map(\.id)).count == decoded.batches.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            archive = decoded
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // The first delivery creates the local archive.
        } catch {
            readable = false
            problem = "The pantry archive could not be read. Changes are paused to protect your saved stock."
        }
    }

    @discardableResult
    func save(_ batch: ShelfBatch, replacing expected: ShelfBatch? = nil) -> Bool {
        let previous = archive.batches.first { $0.id == batch.id }
        guard previous == expected else {
            problem = "This batch has changed. Reopen its ticket before editing."
            return false
        }
        guard (1...9999).contains(batch.quantity) else { return false }
        guard previous != batch else { return true }
        return record(previous, batch, previous == nil ? .added : .edited)
    }

    @discardableResult
    func removeUnits(_ units: Int, from id: UUID, operation: StockOperation) -> Bool {
        guard let original = archive.batches.first(where: { $0.id == id }),
              (1...original.quantity).contains(units), operation == .used || operation == .discarded else { return false }
        var next = original
        next.quantity -= units
        return record(original, next.quantity > 0 ? next : nil, operation)
    }

    @discardableResult
    func undo(_ id: UUID) -> Bool {
        guard let index = archive.history.firstIndex(where: { $0.id == id }),
              let batch = archive.history[index].batch,
              !archive.history.suffix(from: index + 1).contains(where: { $0.batch?.id == batch.id })
        else { return false }
        let event = archive.history[index]
        var next = archive
        next.batches.removeAll { $0.id == batch.id }
        if let original = event.before { next.batches.append(original) }
        next.history.remove(at: index)
        return persist(next)
    }

    private func record(_ before: ShelfBatch?, _ after: ShelfBatch?, _ operation: StockOperation) -> Bool {
        guard let batch = after ?? before else { return false }
        var next = archive
        next.batches.removeAll { $0.id == batch.id }
        if let after { next.batches.append(after) }
        next.history.append(.init(time: .now, operation: operation, before: before, after: after))
        return persist(next)
    }

    @discardableResult
    func logScan(_ code: String, source: ScanRecord.Source) -> UUID? {
        guard (4...14).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let scan = ScanRecord(code: code, source: source)
        var next = archive
        next.scans.append(scan)
        return persist(next) ? scan.id : nil
    }

    @discardableResult
    func finishScan(_ id: UUID, product: OFFProduct?, result: ScanRecord.Result) -> Bool {
        guard let index = archive.scans.firstIndex(where: { $0.id == id }) else { return false }
        var next = archive
        next.scans[index].product = product
        next.scans[index].result = result
        return persist(next)
    }

    @discardableResult
    func saveNote(_ note: PantryNote) -> Bool {
        var clean = note
        clean.text = clean.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.text.isEmpty, clean.text.count <= 2000 else { return false }
        var next = archive
        next.notes.removeAll { $0.id == clean.id }
        next.notes.append(clean)
        return persist(next)
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        var next = archive
        next.notes.removeAll { $0.id == id }
        return persist(next)
    }

    /// Counts are committed together; a stale screen must never overwrite newer stock.
    @discardableResult
    func completeStocktake(expected: [ShelfBatch], counts: [UUID: Int]) -> Bool {
        guard !expected.isEmpty, Set(expected.map(\.id)).count == expected.count,
              expected.count == archive.batches.count,
              expected.allSatisfy({ batch in archive.batches.contains(batch) }),
              Set(counts.keys) == Set(expected.map(\.id)), counts.values.allSatisfy({ (0...9999).contains($0) }) else {
            problem = "Stock changed or a count is missing. Close this stocktake and start again with the current batches."
            return false
        }
        var next = archive
        for original in expected {
            let quantity = counts[original.id]!
            guard quantity != original.quantity else { continue }
            var updated = original
            updated.quantity = quantity
            next.batches.removeAll { $0.id == original.id }
            if quantity > 0 { next.batches.append(updated) }
            next.history.append(StockMovement(time: .now, operation: .counted, before: original, after: quantity > 0 ? updated : nil))
        }
        next.stocktakes.append(StocktakeRecord(counts: expected.map { .init(batch: $0, actual: counts[$0.id]!) }))
        return persist(next)
    }

    private func persist(_ next: ShelfArchive) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if isDemo { archive = next; return true }
        #endif
        guard readable else {
            problem = "The pantry archive is unavailable. Changes cannot be saved."
            return false
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            archive = next
            return true
        } catch {
            problem = "Your changes could not be saved. Check the available storage and try again."
            return false
        }
    }

    static func nearest(_ batches: [ShelfBatch]) -> [ShelfBatch] {
        batches.sorted {
            if $0.expiry != $1.expiry {
                guard let a = $0.expiry else { return false }
                guard let b = $1.expiry else { return true }
                return a < b
            }
            let order = $0.product.name.localizedStandardCompare($1.product.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    func publish() {
        #if DEBUG && targetEnvironment(simulator)
        if isDemo { return }
        #endif
        guard readable else { return }
        let sorted = Self.nearest(archive.batches)
        let first = sorted.first
        WidgetPublisher.shared.publish(title: "Pantry check", value: first?.product.name ?? "Empty shelves",
                                    detail: first?.companionDetail ?? "Stock your first batch on iPhone",
                                    items: sorted.prefix(20).map { CompanionItem(id: $0.id.uuidString, title: $0.product.name, detail: $0.companionDetail) })
    }
}
