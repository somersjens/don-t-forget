import Foundation
import WidgetKit

struct CalendarWidgetItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let startMinutes: Int?
    let colorRawValue: String?
    let prefixText: String?
}

struct CalendarWidgetSnapshot: Codable {
    let generatedAt: Date
    let localeIdentifier: String
    let items: [CalendarWidgetItem]
    let dateFormat: String?
    let lockScreenItems: [CalendarWidgetItem]?
    let lockScreenDatePrefix: String?
    let lockScreenWordTruncation: String?
    let todoItems: [CalendarWidgetItem]?
    let homeWidgetContent: String?
    let homeWidgetCalendarRange: String?
    let homeWidgetDatePrefix: String?
    let homeWidgetTextFlow: String?
    let homeWidgetShowsTitle: Bool?
    let homeWidgetBackground: String?
    let homeWidgetShowsOtherWhenEmpty: Bool?
    let homeWidgetTodoCategoryID: String?
}

@MainActor
enum CalendarWidgetSnapshotPublisher {
    static let appGroupID = "group.Hakketjak.Don-t-forget"
    static let snapshotKey = "calendarWidget.snapshot.v1"
    static let widgetKind = "UpcomingCalendarWidget"

    private struct CategoryAppearance: Decodable {
        let id: String
        let colorRawValue: String
    }

    static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func publish(
        entries: [DayEntry],
        todos: [TodoItem],
        categoriesData: String,
        todoGroupsData: String,
        lockScreenContent: String,
        lockScreenDatePrefix: String,
        lockScreenItemCount: Int,
        lockScreenWordTruncation: String,
        homeWidgetContent: String,
        homeWidgetCalendarRange: String,
        homeWidgetDatePrefix: String,
        homeWidgetTextFlow: String,
        homeWidgetShowsTitle: Bool,
        homeWidgetBackground: String,
        homeWidgetShowsOtherWhenEmpty: Bool,
        homeWidgetTodoCategoryID: String
    ) {
        let today = AppCalendar.startOfDay(.now)
        let categoryColors = decodeCategoryColors(categoriesData)

        let items = entries
            .filter { $0.date >= today }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                let lhsMinutes = lhs.startMinutes ?? Int.max
                let rhsMinutes = rhs.startMinutes ?? Int.max
                if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
                if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder < rhs.manualOrder }
                return lhs.createdAt < rhs.createdAt
            }
            .prefix(50)
            .map { entry in
                let categoryID = entry.accentRawValue == "birthdayReminder"
                    ? RecurringTheme.birthday.rawValue
                    : entry.accentRawValue
                return CalendarWidgetItem(
                    id: entry.id,
                    title: entry.rawText,
                    date: entry.date,
                    startMinutes: entry.startMinutes,
                    colorRawValue: categoryColors[categoryID] ?? fallbackColor(for: categoryID),
                    prefixText: nil
                )
            }

        let lockScreenItems = makeLockScreenItems(
            entries: entries,
            todos: todos,
            todoGroupsData: todoGroupsData,
            content: ActionButtonContentOption(rawValue: lockScreenContent) ?? .today,
            datePrefix: ActionButtonDatePrefixOption(rawValue: lockScreenDatePrefix) ?? .date,
            itemCount: min(max(lockScreenItemCount, 3), 5),
            categoryColors: categoryColors
        )

        let groups = TodoGroupStore.decode(todoGroupsData)
        let groupOrder = Dictionary(uniqueKeysWithValues: groups.enumerated().map {
            ($0.element.id, $0.offset)
        })
        let groupColors = Dictionary(uniqueKeysWithValues: groups.map {
            ($0.id, $0.colorRawValue)
        })
        let selectedTodoCategoryID = groups.contains(where: { $0.id == homeWidgetTodoCategoryID })
            ? homeWidgetTodoCategoryID
            : ""
        let todoItems = todos
            .filter(\.showOnWidget)
            .filter { selectedTodoCategoryID.isEmpty || $0.bucketRawValue == selectedTodoCategoryID }
            .sorted { first, second in
                let left = groupOrder[first.bucketRawValue] ?? Int.max
                let right = groupOrder[second.bucketRawValue] ?? Int.max
                return left == right ? first.createdAt < second.createdAt : left < right
            }
            .prefix(20)
            .map { todo in
                let age = max(0, AppCalendar.calendar.dateComponents(
                    [.day],
                    from: AppCalendar.startOfDay(todo.createdAt),
                    to: today
                ).day ?? 0)
                return CalendarWidgetItem(
                    id: todo.id,
                    title: todo.text,
                    date: todo.createdAt,
                    startMinutes: nil,
                    colorRawValue: groupColors[todo.bucketRawValue] ?? nil,
                    prefixText: "\(age)d"
                )
            }

        let snapshot = CalendarWidgetSnapshot(
            generatedAt: .now,
            localeIdentifier: AppCalendar.locale.identifier,
            items: Array(items),
            dateFormat: AppCalendar.dateFormatOption.rawValue,
            lockScreenItems: lockScreenItems,
            lockScreenDatePrefix: lockScreenDatePrefix,
            lockScreenWordTruncation: lockScreenWordTruncation,
            todoItems: Array(todoItems),
            homeWidgetContent: homeWidgetContent,
            homeWidgetCalendarRange: homeWidgetCalendarRange,
            homeWidgetDatePrefix: homeWidgetDatePrefix,
            homeWidgetTextFlow: homeWidgetTextFlow,
            homeWidgetShowsTitle: homeWidgetShowsTitle,
            homeWidgetBackground: homeWidgetBackground,
            homeWidgetShowsOtherWhenEmpty: homeWidgetShowsOtherWhenEmpty,
            homeWidgetTodoCategoryID: homeWidgetTodoCategoryID
        )

        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private static func makeLockScreenItems(
        entries: [DayEntry],
        todos: [TodoItem],
        todoGroupsData: String,
        content: ActionButtonContentOption,
        datePrefix: ActionButtonDatePrefixOption,
        itemCount: Int,
        categoryColors: [String: String]
    ) -> [CalendarWidgetItem] {
        let today = AppCalendar.startOfDay(.now)

        if content == .todo {
            let groups = TodoGroupStore.decode(todoGroupsData)
            let groupOrder = Dictionary(uniqueKeysWithValues: groups.enumerated().map {
                ($0.element.id, $0.offset)
            })
            let groupColors = Dictionary(uniqueKeysWithValues: groups.map {
                ($0.id, $0.colorRawValue)
            })
            return todos
                .sorted { first, second in
                    let left = groupOrder[first.bucketRawValue] ?? Int.max
                    let right = groupOrder[second.bucketRawValue] ?? Int.max
                    return left == right ? first.createdAt < second.createdAt : left < right
                }
                .prefix(itemCount)
                .map {
                    CalendarWidgetItem(
                        id: $0.id,
                        title: $0.text,
                        date: today,
                        startMinutes: nil,
                        colorRawValue: groupColors[$0.bucketRawValue] ?? nil,
                        prefixText: nil
                    )
                }
        }

        let visibleEntries = entries
            .filter { entry in
                if content == .today {
                    return AppCalendar.isSameDay(entry.date, today)
                }
                guard content == .todayAndTomorrow,
                      let endOfTomorrow = AppCalendar.calendar.date(byAdding: .day, value: 2, to: today) else {
                    return false
                }
                return entry.date >= today && entry.date < endOfTomorrow
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                let lhsMinutes = lhs.startMinutes ?? Int.max
                let rhsMinutes = rhs.startMinutes ?? Int.max
                if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
                return lhs.manualOrder < rhs.manualOrder
            }
            .prefix(itemCount)

        return visibleEntries
            .map { entry in
                let categoryID = entry.accentRawValue == "birthdayReminder"
                    ? RecurringTheme.birthday.rawValue
                    : entry.accentRawValue
                return CalendarWidgetItem(
                    id: entry.id,
                    title: entry.rawText,
                    date: entry.date,
                    startMinutes: entry.startMinutes,
                    colorRawValue: categoryColors[categoryID] ?? fallbackColor(for: categoryID),
                    prefixText: content == .today
                        ? nil
                        : prefix(for: entry.date, style: datePrefix, today: today)
                )
            }
    }

    private static func prefix(
        for date: Date,
        style: ActionButtonDatePrefixOption,
        today: Date
    ) -> String {
        switch style {
        case .date:
            return AppCalendar.localizedShortDayMonth(date)
        case .dayCount:
            return "\(max(0, AppCalendar.calendar.dateComponents([.day], from: today, to: date).day ?? 0))"
        }
    }

    private static func decodeCategoryColors(_ data: String) -> [String: String] {
        guard let encoded = data.data(using: .utf8),
              let categories = try? JSONDecoder().decode([CategoryAppearance].self, from: encoded) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.colorRawValue) })
    }

    private static func fallbackColor(for categoryID: String) -> String? {
        switch categoryID {
        case RecurringTheme.birthday.rawValue: "blue"
        case RecurringTheme.general.rawValue: "yellow"
        case RecurringTheme.personal.rawValue: "green"
        case "holidays": "orange"
        default: nil
        }
    }
}
