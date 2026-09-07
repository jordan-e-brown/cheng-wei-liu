import XCTest

final class StudyFlowTests: XCTestCase {
    @MainActor
    func testSampleImportRecallRatingExportAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["quick-study"].tap()
        let sample = app.buttons["Try sample decks"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        let replacement = app.buttons["Load sample"]
        if replacement.waitForExistence(timeout: 2) { replacement.tap() }
        let imported = app.alerts["Import complete"]
        XCTAssertTrue(imported.waitForExistence(timeout: 15), app.debugDescription)
        imported.buttons["OK"].tap()
        app.buttons["deck-Neri's Chinese Course"].tap()
        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 5))
        app.buttons["Show answer"].tap()
        XCTAssertTrue(app.staticTexts["to know; recognize"].exists)
        app.buttons["Good"].tap()
        XCTAssertTrue(app.staticTexts["Rating saved. Continue to the next note."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Imported card with persisted rating"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeUp()
        let counter = app.staticTexts["activity-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        let before = counter.label
        app.buttons["Export study activity"].tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 5) || app.buttons["Save"].exists || app.buttons["Move"].exists)
        app.terminate()
        app.launch()
        app.buttons["quick-study"].tap()
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["activity-count"].label, before)
    }
}
