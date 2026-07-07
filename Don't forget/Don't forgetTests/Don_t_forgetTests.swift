//
//  Don_t_forgetTests.swift
//  Forget ItTests
//
//  Created by Jens Somers on 21/06/2026.
//

import XCTest
import SwiftData
@testable import Don_t_forget

final class Don_t_forgetTests: XCTestCase {

    @MainActor
    func testProductionDefaultsKeepHistoryForever() {
        XCTAssertEqual(HistoryRetentionOption.default, .never)
        XCTAssertNil(HistoryRetentionOption.default.cutoffDate(from: .now))
    }

    @MainActor
    func testFullBackupRoundTripRestoresAllModelTypesAndSettings() throws {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext
        let suiteName = "AppBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = DayEntry(date: try date(2027, 3, 4), rawText: "Afspraak 14:00")
        entry.isDone = true
        entry.completedAt = try date(2027, 3, 4)
        entry.accentRawValue = "blue"
        context.insert(entry)

        let todo = TodoItem(text: "Melk halen")
        todo.bucketRawValue = "custom-group"
        context.insert(todo)

        let recurring = RecurringItem(
            title: "Verjaardag",
            nextDate: try date(2027, 8, 9),
            recurrenceKind: .birthday,
            notes: "Cadeau regelen"
        )
        recurring.scheduleShiftsData = "[{\"offset\":1}]"
        context.insert(recurring)
        try context.save()
        defaults.set("backup-setting", forKey: SettingsKeys.todoGroups)

        let original = try AppBackupService.makeArchive(from: context, defaults: defaults)
        let decoded = try AppBackupService.decode(AppBackupService.encode(original))

        entry.rawText = "Gewijzigd"
        context.delete(todo)
        context.delete(recurring)
        try context.save()
        defaults.set("changed-setting", forKey: SettingsKeys.todoGroups)

        try AppBackupService.restore(decoded, into: context, defaults: defaults)

        let restoredEntries = try context.fetch(FetchDescriptor<DayEntry>())
        let restoredTodos = try context.fetch(FetchDescriptor<TodoItem>())
        let restoredRecurring = try context.fetch(FetchDescriptor<RecurringItem>())
        XCTAssertEqual(restoredEntries.count, 1)
        XCTAssertEqual(restoredEntries.first?.rawText, "Afspraak 14:00")
        XCTAssertEqual(restoredEntries.first?.accentRawValue, "blue")
        XCTAssertEqual(restoredTodos.first?.text, "Melk halen")
        XCTAssertEqual(restoredTodos.first?.bucketRawValue, "custom-group")
        XCTAssertEqual(restoredRecurring.first?.notes, "Cadeau regelen")
        XCTAssertEqual(restoredRecurring.first?.scheduleShiftsData, "[{\"offset\":1}]")
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.todoGroups), "backup-setting")
    }

    func testTimeParserSupportsTwentyFourHourAndDayPeriodNotations() {
        XCTAssertEqual(TimeParser.parse("16u sporten", locale: Locale(identifier: "nl_NL")).startMinutes, 16 * 60)
        XCTAssertEqual(TimeParser.parse("18u uit eten", locale: Locale(identifier: "nl_NL")).startMinutes, 18 * 60)
        XCTAssertEqual(TimeParser.parse("4PM sports", locale: Locale(identifier: "en_US")).startMinutes, 16 * 60)
        XCTAssertEqual(TimeParser.parse("6:30 pm dinner", locale: Locale(identifier: "en_US")).startMinutes, 18 * 60 + 30)

        let range = TimeParser.parse("4PM-6PM", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(range.startMinutes, 16 * 60)
        XCTAssertEqual(range.endMinutes, 18 * 60)
    }

    func testTimeParserSupportsLocalizedDayPeriodBeforeTime() throws {
        let locale = Locale(identifier: "zh_CN")
        let formatter = DateFormatter()
        formatter.locale = locale

        let pmSymbol = try XCTUnwrap(formatter.pmSymbol)
        let input = "\(pmSymbol)4:00 运动"
        XCTAssertEqual(
            TimeParser.parse(input, locale: locale).startMinutes,
            16 * 60
        )
    }

    @MainActor
    func testResetDefaultsPreservesOnlyLanguage() throws {
        let suiteName = "AppResetServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.english.rawValue, forKey: SettingsKeys.language)
        defaults.set(true, forKey: SettingsKeys.hasCompletedWelcome)
        defaults.set("temporary", forKey: SettingsKeys.historyTutorialExampleID)

        AppResetService.clearDefaultsPreservingLanguage(
            defaults: defaults,
            domainName: suiteName,
            preservedLanguage: AppLanguage.english.rawValue
        )

        XCTAssertEqual(defaults.string(forKey: SettingsKeys.language), AppLanguage.english.rawValue)
        XCTAssertNil(defaults.object(forKey: SettingsKeys.hasCompletedWelcome))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.historyTutorialExampleID))
    }

    @MainActor
    func testEndOfDayReminderFormattingAndDefaultTime() {
        XCTAssertEqual(EndOfDayReminderService.defaultMinutes, 21 * 60 + 50)
        XCTAssertEqual(EndOfDayReminderService.notificationSoundName, "Notification_sound.mp3")
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
            "Forget It"
        )
        XCTAssertEqual(
            EndOfDayReminderService.notificationTitle(for: .english),
            "Forget It"
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
        let key = "feedback.movedToFinished"
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])

        func value(_ language: String) throws -> String {
            let localization = try XCTUnwrap(localizations[language] as? [String: Any])
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            return try XCTUnwrap(unit["value"] as? String)
        }

        XCTAssertEqual(try value("nl"), "‘%@’ is verplaatst naar Afgerond")
        XCTAssertEqual(try value("en"), "‘%@’ was moved to Finished")
    }

    @MainActor
    func testCombinedHolidaySelectionContainsEveryHolidayOnlyOnce() {
        for country in HolidayCountry.allCases {
            let ids = HolidayCatalog.options(for: country, onlyLocal: false)
                .map(\.definition.id)
            XCTAssertEqual(
                ids.count,
                Set(ids).count,
                "Duplicate holiday for \(country.rawValue)"
            )
        }
    }

    func testEveryHolidayIDHasEnglishAndDutchCatalogText() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Don't forget/HolidayCatalog.swift"),
            encoding: .utf8
        )
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("Don't forget/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let regex = try NSRegularExpression(pattern: #"(?:fixed|easter|weekday|islamic)\("([^"]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        let ids = Set(regex.matches(in: source, range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })

        for id in ids {
            let entry = try XCTUnwrap(strings["holiday.\(id)"] as? [String: Any], "Missing holiday.\(id)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertNotNil(localizations["en"], "Missing English for holiday.\(id)")
            XCTAssertNotNil(localizations["nl"], "Missing Dutch for holiday.\(id)")
        }
    }

    @MainActor
    func testRecurringScheduleShiftOnlyMovesSelectedAndFollowingOccurrences() throws {
        let start = try date(2027, 1, 1)
        let item = RecurringItem(
            title: "Weektaak",
            nextDate: start,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .week
        )
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: try date(2027, 1, 15),
            dayOffset: 2,
            to: item
        )

        let dates = RecurrenceEngine.dates(
            for: item,
            from: start,
            through: try date(2027, 2, 1)
        )

        XCTAssertEqual(dates, [
            try date(2027, 1, 1),
            try date(2027, 1, 8),
            try date(2027, 1, 17),
            try date(2027, 1, 24),
            try date(2027, 1, 31)
        ])
    }

    @MainActor
    func testLaterRecurringScheduleShiftBuildsOnEarlierShift() throws {
        let start = try date(2027, 1, 1)
        let item = RecurringItem(
            title: "Weektaak",
            nextDate: start,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .week
        )
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: try date(2027, 1, 15),
            dayOffset: 2,
            to: item
        )
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: try date(2027, 1, 24),
            dayOffset: 3,
            to: item
        )

        let dates = RecurrenceEngine.dates(
            for: item,
            from: start,
            through: try date(2027, 2, 4)
        )

        XCTAssertEqual(dates, [
            try date(2027, 1, 1),
            try date(2027, 1, 8),
            try date(2027, 1, 17),
            try date(2027, 1, 27),
            try date(2027, 2, 3)
        ])
    }

    @MainActor
    func testShiftedOccurrenceIsFoundWhenNominalDateFallsBeforeRequestedRange() throws {
        let item = RecurringItem(
            title: "Weektaak",
            nextDate: try date(2027, 1, 1),
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .week
        )
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: try date(2027, 1, 8),
            dayOffset: 3,
            to: item
        )

        let dates = RecurrenceEngine.dates(
            for: item,
            from: try date(2027, 1, 10),
            through: try date(2027, 1, 12)
        )

        XCTAssertEqual(dates, [try date(2027, 1, 11)])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(AppCalendar.calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day
        )))
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
