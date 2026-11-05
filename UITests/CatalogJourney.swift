import XCTest

@MainActor
final class CatalogJourney: XCTestCase {
    func testProductFromCatalogToSavedRecord() {
        let app = XCUIApplication()
        app.launchArguments = ["-registration_attempted", "YES", "-cached_content_url", ""]
        app.launch()
        let find = app.buttons["shelf.find"]
        XCTAssertTrue(find.waitForExistence(timeout: 10))
        find.tap()
        let product = app.buttons["catalog.product.5010029000016"]
        XCTAssertTrue(product.waitForExistence(timeout: 10))
        product.tap()
        let save = app.buttons["shelf.stock"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let result = app.buttons["shelf.batch.5010029000016"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved product"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(result.waitForExistence(timeout: 10))
    }
}
