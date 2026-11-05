import XCTest
@testable import ShelfCue

@MainActor
final class PantryActivityTests: XCTestCase {
    private func file() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: dir) }
        return dir.appending(path: "pantry.json")
    }
    private func batch(_ quantity: Int = 4) -> ShelfBatch {
        ShelfBatch(product: OFFProduct(record: ["code": "0123456789012", "product_name": "Oat drink"])!, quantity: quantity, place: .fridge, expiry: ShelfDay(.now), note: "")
    }
    func testOldArchiveMigratesWithoutLosingStockOrHistory() throws {
        let url = try file()
        let stock = ShelfStock(file: url)
        XCTAssertTrue(stock.save(batch()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for key in ["scans", "notes", "stocktakes"] { json.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let migrated = ShelfStock(file: url)
        XCTAssertEqual(migrated.archive.batches, stock.archive.batches)
        XCTAssertEqual(migrated.archive.history.count, 1)
        XCTAssertTrue(migrated.archive.scans.isEmpty)
        XCTAssertTrue(migrated.saveNote(PantryNote(date: .now, text: "Check fridge")))
        XCTAssertEqual(ShelfStock(file: url).archive.batches, stock.archive.batches)
    }
    func testStocktakeCommitsCountsTogetherAndKeepsCorrectionsSeparate() throws {
        let url = try file(), stock = ShelfStock(file: url)
        let a = batch(), b = batch(2)
        XCTAssertTrue(stock.save(a)); XCTAssertTrue(stock.save(b))
        XCTAssertFalse(stock.completeStocktake(expected: [a, b], counts: [a.id: 3]))
        XCTAssertEqual(stock.archive.batches.count, 2)
        XCTAssertTrue(stock.completeStocktake(expected: [a, b], counts: [a.id: 3, b.id: 0]))
        let restored = ShelfStock(file: url)
        XCTAssertEqual(restored.archive.batches.count, 1)
        XCTAssertEqual(restored.archive.batches[0].quantity, 3)
        XCTAssertEqual(restored.archive.stocktakes[0].difference, -3)
        let report = PantryReport(archive: restored.archive, period: .all)
        XCTAssertEqual(report.stocked, 6); XCTAssertEqual(report.used, 0); XCTAssertEqual(report.discarded, 0)
        XCTAssertEqual(report.adjustment, -3)
        XCTAssertTrue(restored.undo(restored.archive.history.last!.id))
        XCTAssertEqual(restored.archive.batches.first { $0.id == b.id }?.quantity, 2)
    }
    func testStaleAndInvalidStocktakeCannotOverwriteNewMovements() throws {
        let stock = ShelfStock(file: try file()), a = batch()
        XCTAssertTrue(stock.save(a))
        XCTAssertTrue(stock.removeUnits(1, from: a.id, operation: .used))
        XCTAssertFalse(stock.completeStocktake(expected: [a], counts: [a.id: 4]))
        let latest = stock.archive.batches
        XCTAssertFalse(stock.completeStocktake(expected: latest, counts: [a.id: -1]))
        XCTAssertFalse(stock.completeStocktake(expected: latest, counts: [a.id: 10000]))
        XCTAssertEqual(stock.archive.batches[0].quantity, 3)
        XCTAssertTrue(stock.archive.stocktakes.isEmpty)
        XCTAssertTrue(stock.completeStocktake(expected: latest, counts: [a.id: 3]))
        XCTAssertEqual(stock.archive.history.count, 2)
        XCTAssertEqual(stock.archive.stocktakes.count, 1)
    }
    func testScanRecordsPersistIndependentlyOfAddingStock() throws {
        let url = try file(), stock = ShelfStock(file: url)
        XCTAssertNil(stock.logScan("hello", source: .camera))
        let id = try XCTUnwrap(stock.logScan("0123456789012", source: .typed))
        XCTAssertTrue(stock.finishScan(id, product: batch().product, result: .found))
        let failed = try XCTUnwrap(stock.logScan("12345678", source: .camera))
        XCTAssertTrue(stock.finishScan(failed, product: nil, result: .failed))
        let restored = ShelfStock(file: url)
        XCTAssertEqual(restored.archive.scans.map(\.result), [.found, .failed])
        XCTAssertEqual(restored.archive.scans[0].code, "0123456789012")
        XCTAssertEqual(restored.archive.scans[1].source, .camera)
        XCTAssertTrue(restored.archive.batches.isEmpty)
        XCTAssertEqual(PantryReport(archive: restored.archive, period: .week).matchedScans, 1)
    }
    func testNotesEditDeleteAndDayMarkers() throws {
        let stock = ShelfStock(file: try file()), a = batch()
        XCTAssertTrue(stock.save(a))
        var note = PantryNote(date: .now, text: "  Use for breakfast  ", product: a.product)
        XCTAssertTrue(stock.saveNote(note))
        XCTAssertEqual(stock.archive.notes[0].text, "Use for breakfast")
        note.text = "Use tomorrow"
        XCTAssertTrue(stock.saveNote(note)); XCTAssertEqual(stock.archive.notes.count, 1)
        XCTAssertFalse(stock.saveNote(PantryNote(date: .now, text: "  ")))
        _ = stock.logScan(a.product.id, source: .typed)
        let day = PantryDayEvents(archive: stock.archive, day: ShelfDay(.now))
        XCTAssertEqual(day.batches.count, 1); XCTAssertEqual(day.scans.count, 1); XCTAssertEqual(day.notes.count, 1)
        XCTAssertTrue(day.hasActivity)
        XCTAssertTrue(stock.deleteNote(note.id)); XCTAssertTrue(stock.archive.notes.isEmpty)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertTrue(PantryDayEvents(archive: stock.archive, day: ShelfDay(tomorrow)).isEmpty)
    }
    func testReportPeriodSeparatesActualUseFromCorrections() {
        let now = Date(), a = batch(4)
        var next = a; next.quantity = 3
        let old = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        let archive = ShelfArchive(batches: [next], history: [
            StockMovement(time: old, operation: .added, before: nil, after: a),
            StockMovement(time: now, operation: .used, before: a, after: next),
            StockMovement(time: now, operation: .discarded, before: next, after: nil)
        ])
        let report = PantryReport(archive: archive, period: .week, now: now)
        XCTAssertEqual(report.stocked, 0); XCTAssertEqual(report.used, 1); XCTAssertEqual(report.discarded, 3)
        XCTAssertEqual(report.days.count, 1); XCTAssertEqual(report.days[0].used, 1)
        XCTAssertEqual(PantryReport(archive: archive, period: .all, now: now).stocked, 4)
    }
}
