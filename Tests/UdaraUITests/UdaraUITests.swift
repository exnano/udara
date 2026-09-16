import XCTest

@MainActor final class UdaraUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testEmptyStateAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-host", "--empty"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["A little clarity, city by city"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current location"].exists)
        XCTAssertTrue(app.staticTexts["Estimated PM2.5 AQI"].exists)
        XCTAssertTrue(app.buttons["Enable location"].exists)
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
        XCTAssertTrue(app.staticTexts["Every hour"].waitForExistence(timeout: 3))
    }
    func testMenuBarOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-host", "--light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.staticTexts["Current location"].waitForExistence(timeout: 10))
        app.buttons["settings"].click()
        let dynamic = app.radioButtons["Dynamic AQI icon"]
        if !dynamic.waitForExistence(timeout: 3), app.staticTexts["Current location"].exists {
            // macOS can activate another app between launch and the first click.
            app.activate()
            app.buttons["settings"].click()
        }
        XCTAssertTrue(dynamic.waitForExistence(timeout: 3))
        dynamic.click()
        let item = app.descendants(matching: .any).matching(identifier: "udaraMenuBar").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual((dynamic.value as? NSNumber)?.intValue, 1)
        XCTAssertGreaterThan(item.frame.width, 40)
        let dynamicCapture = XCTAttachment(screenshot: item.screenshot())
        dynamicCapture.name = "Menu bar dynamic 340"; dynamicCapture.lifetime = .keepAlways
        add(dynamicCapture)
        app.radioButtons["Udara icon"].click()
        XCTAssertEqual((app.radioButtons["Udara icon"].value as? NSNumber)?.intValue, 1)
        let udaraCapture = XCTAttachment(screenshot: item.screenshot())
        udaraCapture.name = "Menu bar Udara 340"; udaraCapture.lifetime = .keepAlways
        add(udaraCapture)
    }
    func testFixtureRendering() throws {
        for appearance in ["--light", "--dark", "--reduced-transparency", "--location-denied", "--location-unavailable"] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview-host", appearance]
            app.launch()
            app.activate()
            XCTAssertTrue(app.staticTexts["Hazardous"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Current location"].exists)
            if appearance == "--location-denied" { XCTAssertTrue(app.buttons["Location Settings"].exists) }
            else if appearance == "--location-unavailable" { XCTAssertTrue(app.buttons["Try again"].exists) }
            else {
                XCTAssertTrue(app.staticTexts["Petaling Jaya"].exists)
                XCTAssertLessThan(app.staticTexts["Petaling Jaya"].frame.minY, app.staticTexts["Hazardous"].frame.minY)
                XCTAssertFalse(app.buttons["Actions for Petaling Jaya"].exists)
            }
            let screenshot = XCTAttachment(screenshot: app.windows["Udara Preview"].screenshot())
            screenshot.name = "Udara \(appearance)"; screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
