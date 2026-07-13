//
//  Don_t_forgetUITests.swift
//  Forget ItUITests
//
//  Created by Jens Somers on 21/06/2026.
//

import XCTest

final class Don_t_forgetUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        executionTimeAllowance = 90

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testFinishedOnboardingFlowSupportsGoingBack() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-settings.language", "en",
            "-settings.hasCompletedWelcome", "YES",
            "-settings.iCloudSyncEnabled", "NO"
        ]
        app.launchEnvironment["UI_TEST_RESET_HISTORY_ONBOARDING"] = "1"
        app.launch()

        app.tabBars.buttons["Finished"].tap()

        let help = app.buttons["Finished help"]
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.tap()

        XCTAssertTrue(app.staticTexts["Step 1/6"].waitForExistence(timeout: 2))
        app.buttons["history.filter.Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Step 2/6"].waitForExistence(timeout: 2))

        app.buttons["Next step"].tap()
        XCTAssertTrue(app.textFields["Search Finished"].value as? String == "example")
        XCTAssertTrue(app.staticTexts["Step 3/6"].waitForExistence(timeout: 2))

        app.buttons.matching(identifier: "arrow.uturn.backward").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Step 4/6"].waitForExistence(timeout: 2))
        sleep(6)
        XCTAssertTrue(app.buttons["Undo"].exists, "Tutorial undo must not disappear after five seconds")

        app.buttons["Previous step"].tap()
        XCTAssertTrue(app.staticTexts["Step 3/6"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This is an example"].exists)

        app.buttons["Next step"].tap()
        app.staticTexts["‘This is an example’ restored"].tap()
        XCTAssertTrue(app.staticTexts["Step 5/6"].waitForExistence(timeout: 2))

        app.buttons["Actions for This is an example"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete Permanently"].waitForExistence(timeout: 2))
        app.staticTexts["This is an example"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Delete Permanently"].exists)

        app.buttons["Actions for This is an example"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete Permanently"].waitForExistence(timeout: 2))
        app.buttons["Delete Permanently"].tap()
        XCTAssertTrue(app.staticTexts["Step 6/6"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Ideas for the app? Send us an email"].exists)
        XCTAssertTrue(app.buttons["Write a review of the app"].exists)

        app.buttons["Previous step"].tap()
        XCTAssertTrue(app.staticTexts["This is an example"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Step 5/6"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
