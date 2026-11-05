import XCTest

@MainActor
final class PantryJourney: XCTestCase {
    func testBarcodeStocktakeDiaryCalendarAndStatistics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-registration_attempted", "YES", "-cached_content_url", "", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf.find"].waitForExistence(timeout: 15))
        app.buttons["shelf.find"].tap()
        app.buttons["Scan"].tap()
        let code = app.textFields["scanner.manual"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap(); code.typeText("8076800195057")
        app.buttons["scanner.lookup"].tap()
        let product = app.buttons["catalog.product.8076800195057"]
        XCTAssertTrue(product.waitForExistence(timeout: 10)); product.tap()
        XCTAssertTrue(app.buttons["shelf.stock"].waitForExistence(timeout: 10))
        let dated = app.switches["Record the package date"]
        dated.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(dated.value as? String, "1")
        reveal(app.buttons["shelf.stock"], app); app.buttons["shelf.stock"].tap()
        reveal(app.buttons["shelf.stocktake"], app); app.buttons["shelf.stocktake"].tap()
        XCTAssertTrue(app.staticTexts["Count the packs you actually have"].waitForExistence(timeout: 10))
        let count = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "stocktake.count.")).firstMatch
        count.tap(); count.typeText("3")
        app.buttons["Done"].firstMatch.tap()
        // Other batches can exist from prior journey tests in the same isolated install.
        let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "stocktake.match."))
        if matches.count > 1 {
            for i in 1..<matches.count { reveal(matches.element(boundBy: i), app); matches.element(boundBy: i).tap() }
        }
        reveal(app.buttons["stocktake.save"], app); app.buttons["stocktake.save"].tap()
        XCTAssertTrue(app.staticTexts["Stocktake saved"].waitForExistence(timeout: 10))
        screenshot(app, "Stocktake result")
        app.buttons["Done"].firstMatch.tap()
        let ticket = app.buttons["shelf.batch.8076800195057"].firstMatch
        reveal(ticket, app); ticket.tap()
        XCTAssertTrue(app.buttons["shelf.use"].waitForExistence(timeout: 10)); app.buttons["shelf.use"].tap()
        XCTAssertTrue(app.staticTexts["Packs in stock · 2"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tab.diary"].tap()
        app.buttons["Scans"].tap()
        XCTAssertTrue(app.staticTexts["Product found"].waitForExistence(timeout: 10))
        screenshot(app, "Scan diary")
        app.buttons["diary.add"].tap()
        app.descendants(matching: .any).matching(identifier: "diary.text").firstMatch.tap(); app.descendants(matching: .any).matching(identifier: "diary.text").firstMatch.typeText("Use pasta for dinner")
        app.buttons["diary.save"].tap()
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Use pasta for dinner"].waitForExistence(timeout: 10))
        screenshot(app, "Diary notes")
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1 package dates, 1 barcode lookups")).firstMatch.exists)
        screenshot(app, "Calendar markers")
        app.buttons["tab.insights"].tap()
        XCTAssertTrue(app.staticTexts["Your stock, in numbers"].waitForExistence(timeout: 10))
        screenshot(app, "Pantry statistics")
        app.terminate(); app.launch()
        app.buttons["tab.diary"].tap(); app.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Use pasta for dinner"].waitForExistence(timeout: 10))
    }
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if target.exists && target.isHittable && target.frame.midY > 100 && target.frame.maxY < app.frame.height - 100 { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable)
    }
    private func screenshot(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
