import XCTest

@MainActor final class UdaraUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testEmptyStateAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-host", "--empty"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["A little clarity, city by city"].waitForExistence(timeout: 10))
        app.buttons["Add your first city"].click()
        let search = app.textFields["citySearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click(); search.typeText("Kuala")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kuala Lumpur, Kuala Lumpur, Malaysia, add city")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        app.buttons["Done"].click()
        XCTAssertTrue(app.staticTexts["Kuala Lumpur"].waitForExistence(timeout: 3))
        app.buttons["settings"].click()
        XCTAssertTrue(app.staticTexts["Air quality, quietly close"].waitForExistence(timeout: 3))
    }
    func testFixtureRendering() throws {
        for appearance in ["--light", "--dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview-host", appearance]
            app.launch()
        app.activate()
            XCTAssertTrue(app.staticTexts["Hazardous"].waitForExistence(timeout: 10))
            let screenshot = XCTAttachment(screenshot: app.windows["Udara Preview"].screenshot())
            screenshot.name = "Udara \(appearance)"; screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
