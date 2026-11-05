import XCTest
import UIKit

@MainActor
final class BrowserJourney: XCTestCase {
    func testNativeContactIsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-registration_attempted", "YES", "-cached_content_url", ""]
        app.launch()
        let contact = app.descendants(matching: .any).matching(identifier: "shelf.contact").firstMatch
        for _ in 0..<10 {
            if contact.exists && contact.isHittable && contact.frame.midY > 100 && contact.frame.maxY < app.frame.height - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(contact.exists)
        XCTAssertTrue(contact.isHittable)
        contact.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["contact.done"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        saveScreenshot(app, name: "Contact Us inside app")
        if app.alerts["Unable to load page"].exists { app.alerts.buttons["Close"].tap() }
        app.buttons["contact.done"].tap()
    }

    func testCachedLaunchKeepsBlackSafeAreas() async throws {
        try await requireFixture()
        let app = XCUIApplication()
        app.launchArguments = ["-registration_attempted", "YES", "-cached_content_url", "http://127.0.0.1:8786/"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Launch fixture"].waitForExistence(timeout: 20))
        assertLaunchLayout(app)
        web.buttons["Show alert"].tap()
        XCTAssertTrue(app.alerts.staticTexts["JavaScript works"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        web.links["Next page"].tap()
        XCTAssertTrue(web.staticTexts["Second page"].waitForExistence(timeout: 10))
        web.links["Return to first page"].tap()
        XCTAssertTrue(web.staticTexts["Launch fixture"].waitForExistence(timeout: 10))
        saveScreenshot(app, name: "WebView inside black safe areas")
    }

    func testFirstRegistrationLoadsReturnedURLRedirectAndSafariAgent() async throws {
        try await requireFixture()
        let app = registrationApp(path: "register")
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Registration redirect reached"].waitForExistence(timeout: 20))
        let version = UIDevice.current.systemVersion
        let token = version.replacingOccurrences(of: ".", with: "_")
        let expectedAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(token) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label == %@", expectedAgent)).firstMatch.waitForExistence(timeout: 5))
        assertLaunchLayout(app)
        saveScreenshot(app, name: "First registration WebView")
    }

    func testLaunchFailureCanRetryWithoutModal() async throws {
        try await requireFixture()
        let app = registrationApp(path: "register-retry")
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        let retry = app.buttons["browser.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts["Unable to load page"].exists)
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8786/allow-retry")!)
        retry.tap()
        XCTAssertTrue(app.webViews.staticTexts["Recovered page"].waitForExistence(timeout: 15))
        XCTAssertFalse(retry.exists)
        assertLaunchLayout(app)
        saveScreenshot(app, name: "Page recovered after retry")
    }

    private func registrationApp(path: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--browser-ui-test", "-registration_attempted", "NO", "-cached_content_url", ""]
        app.launchEnvironment["BROWSER_TEST_REGISTRATION_URL"] = "http://127.0.0.1:8786/" + path
        return app
    }

    private func requireFixture() async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8786/")!)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Launch fixture"))
    }

    private func assertLaunchLayout(_ app: XCUIApplication) {
        XCTAssertFalse(app.buttons["browser.contact"].exists)
        XCTAssertFalse(app.buttons["Back"].exists)
        XCTAssertEqual(app.toolbars.count, 0)
        XCTAssertGreaterThan(app.webViews.firstMatch.frame.minY, app.frame.minY)
        XCTAssertLessThan(app.webViews.firstMatch.frame.maxY, app.frame.maxY)
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
