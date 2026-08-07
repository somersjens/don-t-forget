//
//  Don_t_forgetTests.swift
//  Forget ItTests
//
//  Created by Jens Somers on 21/06/2026.
//

import XCTest
import SwiftData
import SwiftUI
@testable import Don_t_forget

final class Don_t_forgetTests: XCTestCase {

    func testAutomatedReviewUsesEachUsageMilestoneOnce() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        XCTAssertEqual(
            AutomatedReviewPolicy.eligibleMilestone(
                totalActiveDuration: 15 * 60,
                completedMilestoneCount: 0,
                requestDates: [],
                sessionActiveDuration: 90,
                idleDuration: 5,
                isTextInputActive: false,
                now: now
            ),
            0
        )
        XCTAssertEqual(
            AutomatedReviewPolicy.eligibleMilestone(
                totalActiveDuration: 60 * 60,
                completedMilestoneCount: 1,
                requestDates: [now.addingTimeInterval(-15 * 24 * 60 * 60)],
                sessionActiveDuration: 90,
                idleDuration: 5,
                isTextInputActive: false,
                now: now
            ),
            1
        )
        XCTAssertEqual(
            AutomatedReviewPolicy.eligibleMilestone(
                totalActiveDuration: 180 * 60,
                completedMilestoneCount: 2,
                requestDates: [now.addingTimeInterval(-30 * 24 * 60 * 60)],
                sessionActiveDuration: 90,
                idleDuration: 5,
                isTextInputActive: false,
                now: now
            ),
            2
        )
    }

    func testAutomatedReviewWaitsForCalmEligibleMoment() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        XCTAssertNil(AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: 15 * 60,
            completedMilestoneCount: 0,
            requestDates: [],
            sessionActiveDuration: 89,
            idleDuration: 5,
            isTextInputActive: false,
            now: now
        ))
        XCTAssertNil(AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: 15 * 60,
            completedMilestoneCount: 0,
            requestDates: [],
            sessionActiveDuration: 90,
            idleDuration: 4.9,
            isTextInputActive: false,
            now: now
        ))
        XCTAssertNil(AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: 15 * 60,
            completedMilestoneCount: 0,
            requestDates: [],
            sessionActiveDuration: 90,
            idleDuration: 5,
            isTextInputActive: true,
            now: now
        ))
    }

    func testAutomatedReviewEnforcesRollingYearLimitAndCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 40_000_000)
        let day: TimeInterval = 24 * 60 * 60

        XCTAssertNil(AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: 180 * 60,
            completedMilestoneCount: 2,
            requestDates: [
                now.addingTimeInterval(-300 * day),
                now.addingTimeInterval(-100 * day),
                now.addingTimeInterval(-15 * day)
            ],
            sessionActiveDuration: 90,
            idleDuration: 5,
            isTextInputActive: false,
            now: now
        ))
        XCTAssertNil(AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: 60 * 60,
            completedMilestoneCount: 1,
            requestDates: [now.addingTimeInterval(-13 * day)],
            sessionActiveDuration: 90,
            idleDuration: 5,
            isTextInputActive: false,
            now: now
        ))
    }

    func testRightToLeftLanguagesResolveTheirWritingDirection() {
        for code in ["ar", "fa", "he", "ur", "ug"] {
            XCTAssertEqual(AppLanguage(rawValue: code)?.layoutDirection, .rightToLeft)
        }
    }

    func testLeftToRightLanguagesKeepTheirWritingDirection() {
        for code in ["nl", "en", "fr", "de"] {
            XCTAssertEqual(AppLanguage(rawValue: code)?.layoutDirection, .leftToRight)
        }
    }

    private var sourceFixturesRoot: URL {
        get throws {
            let sourceTreeRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: sourceTreeRoot.appendingPathComponent("Don't forget").path) {
                return sourceTreeRoot
            }

            return try XCTUnwrap(
                Bundle(for: Self.self).resourceURL?.appendingPathComponent("SourceFixtures"),
                "Source fixtures are missing from the test bundle"
            )
        }
    }

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
    func testResetDefaultsPreservesLanguageAndReviewThrottle() throws {
        let suiteName = "AppResetServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.english.rawValue, forKey: SettingsKeys.language)
        defaults.set(true, forKey: SettingsKeys.hasCompletedWelcome)
        defaults.set("temporary", forKey: SettingsKeys.historyTutorialExampleID)
        defaults.set(
            2,
            forKey: AutomatedReviewPersistence.completedMilestoneCount
        )

        AppResetService.clearDefaultsPreservingLanguage(
            defaults: defaults,
            domainName: suiteName,
            preservedLanguage: AppLanguage.english.rawValue
        )

        XCTAssertEqual(defaults.string(forKey: SettingsKeys.language), AppLanguage.english.rawValue)
        XCTAssertEqual(
            defaults.integer(forKey: AutomatedReviewPersistence.completedMilestoneCount),
            2
        )
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
        let projectRoot = try sourceFixturesRoot
        let catalogPaths = [
            "Don't forget/Localizable.xcstrings",
            "Don't forgetWidget/Localizable.xcstrings"
        ]

        for catalogPath in catalogPaths {
            let data = try Data(contentsOf: projectRoot.appendingPathComponent(catalogPath))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try XCTUnwrap(json["strings"] as? [String: Any])

            for (key, rawEntry) in strings {
                let entry = try XCTUnwrap(rawEntry as? [String: Any], "Invalid entry for \(key)")
                let localizations = try XCTUnwrap(
                    entry["localizations"] as? [String: Any],
                    "No localizations for \(catalogPath): \(key)"
                )

                for language in ["en", "nl"] {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "Missing \(language) translation for \(catalogPath): \(key)"
                    )
                    let stringUnit = try XCTUnwrap(
                        localization["stringUnit"] as? [String: Any],
                        "Missing string unit for \(language): \(catalogPath): \(key)"
                    )
                    XCTAssertEqual(stringUnit["state"] as? String, "translated", "Unfinished \(language): \(catalogPath): \(key)")
                    XCTAssertNotNil(stringUnit["value"] as? String, "Missing value for \(language): \(catalogPath): \(key)")
                }
            }
        }
    }

    func testUIStringsDoNotBranchOnDutchLanguage() throws {
        let sourceRoot = try sourceFixturesRoot.appendingPathComponent("Don't forget")
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(
                source.contains(#"languageCode?.identifier == "nl""#),
                "Use a String Catalog key instead of a Dutch/English branch in \(sourceFile.lastPathComponent)"
            )
        }
    }

    func testHistoryMessagesDoNotMixLanguages() throws {
        let catalogURL = try sourceFixturesRoot.appendingPathComponent("Don't forget/Localizable.xcstrings")
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
        let projectRoot = try sourceFixturesRoot
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

    @MainActor
    func testRecurringOccurrenceKeepsIdentityAfterIgnoredMoveThenSeriesMove() throws {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext
        let start = try date(2027, 1, 1)
        let item = RecurringItem(
            title: "Dagtaak",
            nextDate: start,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .day
        )
        context.insert(item)
        RecurringScheduler.syncAll(
            items: [item],
            in: context,
            through: try date(2027, 1, 6)
        )
        try context.save()

        let entries = try context.fetch(FetchDescriptor<DayEntry>())
        let first = try XCTUnwrap(entries.first(where: {
            $0.recurringOccurrenceKey == "occurrence-v2:2027-01-01"
        }))
        let originalID = first.id

        // The first move is deliberately kept as a one-off override.
        first.date = try date(2027, 1, 2)
        first.recurringDateOverride = first.date

        // A later "yes" must use the unshifted series position, not the
        // already overridden card date. This produces a total +2 day shift.
        let position = try XCTUnwrap(RecurrenceEngine.scheduledEntryDate(
            for: first.recurringOccurrenceKey,
            item: item
        ))
        XCTAssertEqual(position.entryDate, start)
        first.date = try date(2027, 1, 3)
        first.recurringDateOverride = first.date
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: position.effectiveFrom,
            dayOffset: 2,
            to: item
        )
        let plan = RecurringScheduler.seriesPlan(
            for: item,
            from: AppCalendar.startOfDay(.now),
            through: try date(2027, 1, 8)
        )
        try context.save()
        XCTAssertTrue(try RecurringSeriesWorker.sync(
            itemID: item.id,
            plan: plan,
            in: container
        ))

        let verificationContext = ModelContext(container)
        let shifted = try verificationContext.fetch(FetchDescriptor<DayEntry>())
            .filter { $0.recurringItemIdentifier == item.id }
        let sameOccurrence = try XCTUnwrap(shifted.first(where: { $0.id == originalID }))
        XCTAssertEqual(sameOccurrence.recurringOccurrenceKey, "occurrence-v2:2027-01-01")
        XCTAssertEqual(sameOccurrence.date, try date(2027, 1, 3))
        XCTAssertEqual(
            shifted.first(where: {
                $0.recurringOccurrenceKey == "occurrence-v2:2027-01-02"
            })?.date,
            try date(2027, 1, 4)
        )
    }

    @MainActor
    func testFullRecurringWorkerKeepsCompletedDailyOccurrenceAndIsIdempotent() throws {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configuration
        )
        let today = AppCalendar.startOfDay(.now)
        let endDate = try XCTUnwrap(AppCalendar.calendar.date(
            byAdding: .day,
            value: 30,
            to: today
        ))
        let item = RecurringItem(
            title: "Dagtaak",
            nextDate: today,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .day
        )
        let plan = RecurringScheduler.fullSyncPlan(items: [item], through: endDate)

        try RecurringFullSyncWorker.sync(plan: plan, in: container)

        let completionContext = ModelContext(container)
        let initialEntries = try completionContext.fetch(FetchDescriptor<DayEntry>())
        XCTAssertEqual(initialEntries.count, 31)
        let completed = try XCTUnwrap(initialEntries.first)
        let completedID = completed.id
        completed.isDone = true
        completed.completedAt = .now
        try completionContext.save()

        try RecurringFullSyncWorker.sync(plan: plan, in: container)

        let verificationContext = ModelContext(container)
        let entriesAfterSecondSync = try verificationContext.fetch(FetchDescriptor<DayEntry>())
        XCTAssertEqual(entriesAfterSecondSync.count, 31)
        let preserved = try XCTUnwrap(entriesAfterSecondSync.first(where: { $0.id == completedID }))
        XCTAssertTrue(preserved.isDone)
        XCTAssertNotNil(preserved.completedAt)
    }

    @MainActor
    func testSchedulerMigratesShiftedLegacyKeyWithoutReplacingEntry() throws {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext
        let item = RecurringItem(
            title: "Weektaak",
            nextDate: try date(2027, 1, 1),
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .week
        )
        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: try date(2027, 1, 1),
            dayOffset: 2,
            to: item
        )
        let legacy = DayEntry(date: try date(2027, 1, 3), rawText: "Weektaak", source: .recurring)
        legacy.recurringItemIdentifier = item.id
        legacy.recurringOccurrenceKey = "occurrence:2027-01-03"
        context.insert(item)
        context.insert(legacy)
        try context.save()
        let legacyID = legacy.id
        let legacyPosition = try XCTUnwrap(RecurrenceEngine.scheduledEntryDate(
            for: legacy.recurringOccurrenceKey,
            item: item
        ))
        XCTAssertEqual(legacyPosition.entryDate, try date(2027, 1, 3))

        RecurringScheduler.syncAll(
            items: [item],
            in: context,
            through: try date(2027, 1, 10)
        )
        try context.save()

        let migrated = try context.fetch(FetchDescriptor<DayEntry>())
        let first = try XCTUnwrap(migrated.first(where: { $0.id == legacyID }))
        XCTAssertEqual(first.recurringOccurrenceKey, "occurrence-v2:2027-01-01")
        XCTAssertEqual(first.date, try date(2027, 1, 3))
    }

    @MainActor
    func testWeeklyDescriptionUsesShiftedWeekday() throws {
        let calendar = AppCalendar.calendar
        let today = AppCalendar.startOfDay(.now)
        let currentWeekday = calendar.component(.weekday, from: today)
        var daysUntilSunday = (1 - currentWeekday + 7) % 7
        if daysUntilSunday == 0 { daysUntilSunday = 7 }
        let sunday = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: daysUntilSunday,
            to: today
        ))
        let item = RecurringItem(
            title: "Weektaak",
            nextDate: sunday,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .week
        )

        RecurrenceEngine.appendScheduleShift(
            effectiveFrom: sunday,
            dayOffset: 1,
            to: item
        )

        XCTAssertEqual(
            RecurrenceEngine.description(for: item),
            AppCalendar.locale.localizedFormat(
                "recurrence.weeklyOn",
                RecurrenceEngine.weekdayName(2)
            )
        )
    }

    /// A device with a short horizon must leave the occurrences a device with
    /// a long horizon generated in place. Deleting them made the two devices
    /// delete and recreate each other's series through iCloud.
    @MainActor
    func testShortHorizonSyncKeepsOccurrencesGeneratedBeyondItsWindow() throws {
        let container = try inMemoryContainer()
        let context = container.mainContext
        let today = AppCalendar.startOfDay(.now)
        let item = RecurringItem(
            title: "Dagtaak",
            nextDate: today,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .day
        )
        context.insert(item)

        let longHorizon = try XCTUnwrap(
            AppCalendar.calendar.date(byAdding: .day, value: 60, to: today)
        )
        RecurringScheduler.syncAll(items: [item], in: context, through: longHorizon)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayEntry>()).count, 61)

        let shortHorizon = try XCTUnwrap(
            AppCalendar.calendar.date(byAdding: .day, value: 10, to: today)
        )
        RecurringScheduler.syncAll(items: [item], in: context, through: shortHorizon)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<DayEntry>()).count, 61)
    }

    /// iCloud merges two independently generated copies of one occurrence into
    /// two rows. Every device has to collapse them onto the same survivor and
    /// keep the state the user set on either copy.
    @MainActor
    func testMergedDuplicateOccurrencesCollapseOntoOneRowKeepingUserState() throws {
        let container = try inMemoryContainer()
        let context = container.mainContext
        let today = AppCalendar.startOfDay(.now)
        let item = RecurringItem(
            title: "Verjaardag",
            nextDate: today,
            recurrenceKind: .interval,
            intervalValue: 1,
            intervalUnit: .day
        )
        context.insert(item)

        let endDate = try XCTUnwrap(
            AppCalendar.calendar.date(byAdding: .day, value: 3, to: today)
        )
        RecurringScheduler.syncAll(items: [item], in: context, through: endDate)
        try context.save()

        let original = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DayEntry>())
                .first { $0.recurringOccurrenceKey != nil && $0.date == today }
        )

        // The copy another device generated for the same occurrence.
        let imported = DayEntry(date: today, rawText: original.rawText, source: .recurring)
        imported.recurringItemIdentifier = original.recurringItemIdentifier
        imported.recurringOccurrenceKey = original.recurringOccurrenceKey
        imported.isDone = true
        imported.completedAt = .now
        context.insert(imported)
        try context.save()

        let expectedSurvivorID = min(original.id.uuidString, imported.id.uuidString)
        RecurringScheduler.syncAll(items: [item], in: context, through: endDate)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<DayEntry>())
            .filter { $0.recurringOccurrenceKey == original.recurringOccurrenceKey }
        XCTAssertEqual(remaining.count, 1)
        let survivor = try XCTUnwrap(remaining.first)
        XCTAssertEqual(survivor.id.uuidString, expectedSurvivorID)
        XCTAssertTrue(survivor.isDone)
        XCTAssertNotNil(survivor.completedAt)
    }

    /// Confirming the same holiday selection twice must not replace the rows:
    /// a new identifier reads as a delete plus an insert on every other
    /// device, which is what duplicated holidays through iCloud.
    @MainActor
    func testReapplyingTheSameHolidaySelectionKeepsTheExistingItems() throws {
        let container = try inMemoryContainer()
        let context = container.mainContext
        let options = HolidayCatalog.options(for: .netherlands, onlyLocal: true)
        let selection = Set(options.prefix(3).map(\.id))

        func managedItems() throws -> [RecurringItem] {
            try context.fetch(FetchDescriptor<RecurringItem>())
                .filter { HolidayCatalog.managedHoliday(from: $0.notes) != nil }
        }

        HolidayReconciler.apply(
            selectedIDs: selection,
            options: options,
            managedItems: try managedItems(),
            categoryID: "holidays",
            in: context
        )
        try context.save()
        let firstIDs = Set(try managedItems().map(\.id))
        XCTAssertEqual(firstIDs.count, 3)

        HolidayReconciler.apply(
            selectedIDs: selection,
            options: options,
            managedItems: try managedItems(),
            categoryID: "holidays",
            in: context
        )
        try context.save()

        XCTAssertEqual(Set(try managedItems().map(\.id)), firstIDs)
    }

    /// The shared day zone is derived from the rows the user already has, so
    /// every existing day has to keep the label it has today — including rows
    /// written on both sides of a daylight saving change.
    @MainActor
    func testDerivedDayTimeZoneKeepsExistingDayLabels() throws {
        for identifier in ["Europe/Amsterdam", "America/New_York", "Pacific/Auckland"] {
            let home = try XCTUnwrap(TimeZone(identifier: identifier))
            var writer = Calendar(identifier: .gregorian)
            writer.timeZone = home

            let days = [
                DateComponents(year: 2026, month: 7, day: 15),
                DateComponents(year: 2026, month: 12, day: 24),
                DateComponents(year: 2027, month: 3, day: 1)
            ]
            let storedDays = try days.map { try XCTUnwrap(writer.date(from: $0)) }
            let offsets = storedDays.map {
                DayTimeZonePin.impliedOffset(
                    of: $0,
                    deviceOffset: home.secondsFromGMT(for: $0)
                )
            }

            var reader = Calendar(identifier: .gregorian)
            reader.timeZone = try XCTUnwrap(
                TimeZone(secondsFromGMT: DayTimeZonePin.resolvedOffset(from: offsets))
            )

            for (expected, storedDay) in zip(days, storedDays) {
                let actual = reader.dateComponents([.year, .month, .day], from: storedDay)
                XCTAssertEqual(actual.year, expected.year, identifier)
                XCTAssertEqual(actual.month, expected.month, identifier)
                XCTAssertEqual(actual.day, expected.day, identifier)
            }
        }
    }

    /// Installing the update while abroad must not repin the day zone to
    /// wherever the user happens to be; the rows still say where they are from.
    @MainActor
    func testDayTimeZoneIsDerivedFromDataNotFromATravellingDevice() throws {
        let home = try XCTUnwrap(TimeZone(identifier: "Europe/Amsterdam"))
        var writer = Calendar(identifier: .gregorian)
        writer.timeZone = home
        let storedDay = try XCTUnwrap(
            writer.date(from: DateComponents(year: 2026, month: 7, day: 15))
        )

        for abroad in ["America/New_York", "Asia/Tokyo", "America/Los_Angeles"] {
            let deviceZone = try XCTUnwrap(TimeZone(identifier: abroad))
            XCTAssertEqual(
                DayTimeZonePin.impliedOffset(
                    of: storedDay,
                    deviceOffset: deviceZone.secondsFromGMT(for: storedDay)
                ),
                home.secondsFromGMT(for: storedDay),
                abroad
            )
        }
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppSchemaMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
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
