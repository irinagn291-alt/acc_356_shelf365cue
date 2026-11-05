import XCTest
@testable import ShelfCue

final class ShelfCueTests: XCTestCase {
    private func databaseFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appending(path: "stock.json")
    }

    private func batch(quantity: Int) throws -> ShelfBatch {
        let record: [String: Any] = ["code": "12345678", "product_name": "Muesli", "brands": "Grain Works",
                                     "nutriments": ["energy-kcal_100g": 370]]
        return ShelfBatch(product: try XCTUnwrap(OFFProduct(record: record)), quantity: quantity,
                          place: .cupboard, expiry: nil, note: "")
    }

    @MainActor func testUseDiscardAndUndoSurviveRestart() throws {
        let file = try databaseFile()
        let stock = ShelfStock(file: file)
        let item = try batch(quantity: 5)
        XCTAssertTrue(stock.save(item))
        XCTAssertFalse(stock.removeUnits(6, from: item.id, operation: .used))
        XCTAssertFalse(stock.removeUnits(0, from: item.id, operation: .discarded))
        XCTAssertTrue(stock.removeUnits(2, from: item.id, operation: .used))
        XCTAssertTrue(stock.removeUnits(3, from: item.id, operation: .discarded))
        XCTAssertEqual(stock.archive.batches.count, 0)
        let restored = ShelfStock(file: file)
        XCTAssertEqual(restored.archive.history.map(\.operation), [.added, .used, .discarded])
        XCTAssertEqual(restored.archive.history.map(\.difference), [5, -2, -3])
        XCTAssertFalse(restored.undo(restored.archive.history[0].id))
        XCTAssertTrue(restored.undo(try XCTUnwrap(restored.archive.history.last).id))
        XCTAssertEqual(ShelfStock(file: file).archive.batches.first?.quantity, 3)
    }

    @MainActor func testTwoLotsKeepIndependentDatesAndLocations() throws {
        let stock = ShelfStock(file: try databaseFile())
        let undated = try batch(quantity: 4)
        var dated = try batch(quantity: 1)
        dated.expiry = ShelfDay(.now)
        dated.place = .fridge
        XCTAssertTrue(stock.save(undated))
        XCTAssertTrue(stock.save(dated))
        XCTAssertEqual(ShelfStock.nearest(stock.archive.batches).map(\.id), [dated.id, undated.id])
        let original = dated
        dated.place = .freezer
        dated.note = "Moved to freezer"
        XCTAssertTrue(stock.save(dated, replacing: original))
        XCTAssertEqual(stock.archive.history.last?.after, dated)
        XCTAssertFalse(stock.save(original, replacing: original))
        XCTAssertTrue(stock.undo(try XCTUnwrap(stock.archive.history.last).id))
        XCTAssertEqual(stock.archive.batches.first { $0.id == original.id }, original)
        XCTAssertEqual(stock.archive.batches.first { $0.id == undated.id }, undated)
    }


    func testApproachingDateChangesAtLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let recorded = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12)))
        let day = ShelfDay(recorded)
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0)))
        XCTAssertEqual(day.distance(from: before), 1)
        XCTAssertEqual(day.distance(from: after), 0)
    }

    @MainActor func testUndoForOneLotLeavesLaterMovementInAnotherLot() throws {
        let stock = ShelfStock(file: try databaseFile())
        let first = try batch(quantity: 4)
        let second = try batch(quantity: 2)
        XCTAssertTrue(stock.save(first))
        XCTAssertTrue(stock.removeUnits(1, from: first.id, operation: .used))
        let receipt = try XCTUnwrap(stock.archive.history.last).id
        XCTAssertTrue(stock.save(second))
        XCTAssertTrue(stock.undo(receipt))
        XCTAssertEqual(Set(stock.archive.batches.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(stock.archive.batches.first { $0.id == first.id }?.quantity, 4)
        XCTAssertEqual(stock.archive.history.map(\.operation), [.added, .added])
    }

    @MainActor func testArchiveWithDamagedContentIsPreserved() throws {
        let file = try databaseFile()
        let initial = Data("unreadable".utf8)
        try initial.write(to: file)
        let stock = ShelfStock(file: file)
        XCTAssertNotNil(stock.problem)
        XCTAssertFalse(stock.save(try batch(quantity: 1)))
        XCTAssertEqual(try Data(contentsOf: file), initial)
    }
}

final class CatalogParsingTests: XCTestCase {
    private func barcode(_ fields: [String: Any]) throws -> OFFProduct {
        var record: [String: Any] = ["code": "0123456789012", "product_name": "Oat drink"]
        record.merge(fields) { _, updated in updated }
        let data = try JSONSerialization.data(withJSONObject: ["status": 1, "product": record])
        return try XCTUnwrap(FoodCatalog.parse(data, barcode: true).first)
    }

    func testMissingNutritionZeroAndKilojoules() throws {
        let drink = try barcode(["nutriments": ["energy-kj_100g": "418.4", "sugars_100g": 0, "salt_100g": -2]])
        XCTAssertEqual(try XCTUnwrap(drink.kcal), 100, accuracy: 0.0001)
        XCTAssertEqual(drink.sugars, 0)
        XCTAssertNil(drink.protein)
        XCTAssertNil(drink.salt)
        let explicitZero = try barcode(["nutriments": ["energy-kcal_100g": 0, "energy_100g": 418.4]])
        XCTAssertEqual(explicitZero.kcal, 0)
        XCTAssertNil(try barcode([:]).kcal)
    }

    func testEnglishNamesAndIngredientsPreferEnglishLabels() throws {
        let translated = try barcode(["lang": "fr", "product_name": "Boisson", "product_name_en": "Oat drink",
                                      "ingredients_text": "Eau, avoine", "ingredients_text_en": " Water, oats "])
        XCTAssertEqual(translated.name, "Oat drink")
        XCTAssertEqual(translated.ingredients, "Water, oats")

        let unlabelled = try barcode(["lang": "fr", "product_name": "Boisson", "ingredients_text": "Eau, avoine"])
        XCTAssertEqual(unlabelled.name, "Boisson")
        XCTAssertNil(unlabelled.ingredients)
        XCTAssertEqual(try barcode(["lang": "en", "ingredients_text": "Water, oats"]).ingredients, "Water, oats")
    }

    func testExplicitNutritionBasisBeforePackageVolume() throws {
        XCTAssertEqual(try barcode(["nutrition_data_per": "100g", "product_quantity_unit": "ml"]).amountUnit, "g")
        XCTAssertEqual(try barcode(["nutrition_data_per": "100ml", "product_quantity_unit": "g"]).amountUnit, "ml")
        XCTAssertEqual(try barcode(["product_quantity_unit": "cl"]).amountUnit, "ml")
        XCTAssertEqual(try barcode(["quantity": "1.5 L"]).amountUnit, "ml")
        XCTAssertEqual(try barcode(["quantity": "500 g"]).amountUnit, "g")
    }

    func testSearchDeduplicatesByBarcodeAndPreservesLeadingZeroes() throws {
        let records = [
            ["code": "0123456789012", "product_name": "First label"],
            ["code": "not-a-code", "product_name": "Invalid"],
            ["code": "0123456789012", "product_name": "Duplicate"],
            ["code": "5012345678910", "product_name": "Another label"]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["products": records])
        let products = try FoodCatalog.parse(data, barcode: false)
        XCTAssertEqual(products.map(\.id), ["0123456789012", "5012345678910"])
        XCTAssertEqual(products.map(\.name), ["First label", "Another label"])
    }
}
