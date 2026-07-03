//
//  Don_t_forgetTests.swift
//  Don't forgetTests
//
//  Created by Jens Somers on 21/06/2026.
//

import XCTest
@testable import Don_t_forget

final class Don_t_forgetTests: XCTestCase {

    @MainActor
    func testEndOfDayReminderFormattingAndDefaultTime() {
        XCTAssertEqual(EndOfDayReminderService.defaultMinutes, 21 * 60 + 50)
        XCTAssertEqual(
            EndOfDayReminderService.reminderBody(texts: [
                "paella maken",
                "sporten op werk",
                "slapen bij Fran"
            ]),
            "3x | paella maken | sporten op werk | slapen bij Fran"
        )
        XCTAssertEqual(
            EndOfDayReminderService.testReminderBody(
                texts: [],
                emptyText: "Geen openstaande taken voor vandaag"
            ),
            "0x | Geen openstaande taken voor vandaag"
        )
        XCTAssertEqual(
            EndOfDayReminderService.notificationTitle(for: .dutch),
            "Niet vergeten"
        )
        XCTAssertEqual(
            EndOfDayReminderService.notificationTitle(for: .english),
            "Don't Forget"
        )
    }

    func testStringCatalogHasCompleteEnglishAndDutchTranslations() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let catalogURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Don't forget/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], "Invalid entry for \(key)")
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "No localizations for \(key)"
            )

            for language in ["en", "nl"] {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "Missing \(language) translation for \(key)"
                )
                let stringUnit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "Missing string unit for \(language): \(key)"
                )
                XCTAssertEqual(stringUnit["state"] as? String, "translated", "Unfinished \(language): \(key)")
                XCTAssertNotNil(stringUnit["value"] as? String, "Missing value for \(language): \(key)")
            }
        }
    }

    func testHistoryMessagesDoNotMixLanguages() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let catalogURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Don't forget/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let key = "Taak verplaatst\nnaar History"
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])

        func value(_ language: String) throws -> String {
            let localization = try XCTUnwrap(localizations[language] as? [String: Any])
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            return try XCTUnwrap(unit["value"] as? String)
        }

        XCTAssertEqual(try value("nl"), "Taak verplaatst\nnaar geschiedenis")
        XCTAssertEqual(try value("en"), "Task Moved\nto History")
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
