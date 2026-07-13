import SwiftUI
import UIKit
import WidgetKit

private let appGroupID = "group.Hakketjak.Don-t-forget"
private let snapshotKey = "calendarWidget.snapshot.v1"
private let widgetKind = "UpcomingCalendarWidget"

private struct WidgetCalendarItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let startMinutes: Int?
    let colorRawValue: String?
    let prefixText: String?
}

private struct WidgetCalendarSnapshot: Codable {
    let generatedAt: Date
    let localeIdentifier: String
    let items: [WidgetCalendarItem]
    let dateFormat: String?
    let lockScreenItems: [WidgetCalendarItem]?
    let lockScreenDatePrefix: String?
    let lockScreenWordTruncation: String?
    let todoItems: [WidgetCalendarItem]?
    let homeWidgetContent: String?
    let homeWidgetCalendarRange: String?
    let homeWidgetDatePrefix: String?
    let homeWidgetTextFlow: String?
    let homeWidgetShowsTitle: Bool?
    let homeWidgetBackground: String?
    let homeWidgetShowsOtherWhenEmpty: Bool?
    let homeWidgetTodoCategoryID: String?
}

private struct UpcomingCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCalendarSnapshot
}

private struct UpcomingCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingCalendarEntry {
        UpcomingCalendarEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingCalendarEntry) -> Void) {
        completion(UpcomingCalendarEntry(
            date: .now,
            snapshot: context.isPreview ? Self.placeholderSnapshot : loadSnapshot()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingCalendarEntry>) -> Void) {
        let now = Date.now
        let snapshot = loadSnapshot()
        let entry = UpcomingCalendarEntry(date: now, snapshot: snapshot)
        let calendar = Calendar.current
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func loadSnapshot() -> WidgetCalendarSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetCalendarSnapshot.self, from: data) else {
            return WidgetCalendarSnapshot(
                generatedAt: .now,
                localeIdentifier: Locale.current.identifier,
                items: [],
                dateFormat: nil,
                lockScreenItems: nil,
                lockScreenDatePrefix: nil,
                lockScreenWordTruncation: nil,
                todoItems: nil,
                homeWidgetContent: nil,
                homeWidgetCalendarRange: nil,
                homeWidgetDatePrefix: nil,
                homeWidgetTextFlow: nil,
                homeWidgetShowsTitle: nil,
                homeWidgetBackground: nil,
                homeWidgetShowsOtherWhenEmpty: nil,
                homeWidgetTodoCategoryID: nil
            )
        }
        return snapshot
    }

    private static var placeholderSnapshot: WidgetCalendarSnapshot {
        let calendar = Calendar.current
        return WidgetCalendarSnapshot(
            generatedAt: .now,
            localeIdentifier: "nl_NL",
            items: [
                WidgetCalendarItem(id: UUID(), title: "Teamoverleg", date: .now, startMinutes: 600, colorRawValue: "blue", prefixText: "0"),
                WidgetCalendarItem(id: UUID(), title: "Verjaardag Noor", date: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now, startMinutes: nil, colorRawValue: "pink", prefixText: "1"),
                WidgetCalendarItem(id: UUID(), title: "Tandarts", date: calendar.date(byAdding: .day, value: 2, to: .now) ?? .now, startMinutes: 870, colorRawValue: "orange", prefixText: "2"),
                WidgetCalendarItem(id: UUID(), title: "Keti Koti", date: calendar.date(byAdding: .day, value: 3, to: .now) ?? .now, startMinutes: nil, colorRawValue: "orange", prefixText: "3"),
                WidgetCalendarItem(id: UUID(), title: "Hardlopen", date: calendar.date(byAdding: .day, value: 4, to: .now) ?? .now, startMinutes: nil, colorRawValue: "green", prefixText: "4")
            ],
            dateFormat: "system",
            lockScreenItems: nil,
            lockScreenDatePrefix: nil,
            lockScreenWordTruncation: nil,
            todoItems: [
                WidgetCalendarItem(id: UUID(), title: "Boodschappenlijst afronden", date: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now, startMinutes: nil, colorRawValue: "green", prefixText: "2d"),
                WidgetCalendarItem(id: UUID(), title: "Treinkaartjes boeken", date: .now, startMinutes: nil, colorRawValue: "purple", prefixText: "0d")
            ],
            homeWidgetContent: "combined",
            homeWidgetCalendarRange: "today",
            homeWidgetDatePrefix: "date",
            homeWidgetTextFlow: "truncate",
            homeWidgetShowsTitle: true,
            homeWidgetBackground: "brandLightBlue",
            homeWidgetShowsOtherWhenEmpty: true,
            homeWidgetTodoCategoryID: ""
        )
    }
}

private struct UpcomingCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: UpcomingCalendarEntry

    private var layoutDirection: LayoutDirection {
        let locale = Locale(identifier: entry.snapshot.localeIdentifier)
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    private var visibleItems: [WidgetCalendarItem] {
        if family == .accessoryRectangular, let configuredItems = entry.snapshot.lockScreenItems {
            return configuredItems
        }
        return Array(entry.snapshot.items.prefix(5))
    }

    private var homeCalendarItems: [WidgetCalendarItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        switch entry.snapshot.homeWidgetCalendarRange ?? "upcoming" {
        case "today":
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return entry.snapshot.items.filter { $0.date < tomorrow }
        case "todayAndTomorrow":
            let end = calendar.date(byAdding: .day, value: 2, to: today) ?? today
            return entry.snapshot.items.filter { $0.date < end }
        default:
            return entry.snapshot.items
        }
    }

    private var homeTodoItems: [WidgetCalendarItem] {
        entry.snapshot.todoItems ?? []
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessoryContent
            } else {
                homeScreenContent
                    .foregroundStyle(homePrimaryTextColor)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                Color(.secondarySystemBackground)
            } else if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255),
                        Color(red: 10 / 255, green: 11 / 255, blue: 14 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if entry.snapshot.homeWidgetBackground == "white" {
                Color.white
            } else {
                Color(red: 207 / 255, green: 224 / 255, blue: 247 / 255)
            }
        }
        .environment(\.locale, Locale(identifier: entry.snapshot.localeIdentifier))
        .environment(\.layoutDirection, layoutDirection)
    }

    private var homeScreenContent: some View {
        Group {
            if family == .systemLarge {
                largeHomeScreenContent
            } else {
                regularHomeScreenContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    @ViewBuilder
    private var regularHomeScreenContent: some View {
        switch entry.snapshot.homeWidgetContent ?? "combined" {
            case "todo":
                if shouldShowOtherContent, homeTodoItems.isEmpty, !homeCalendarItems.isEmpty {
                    Link(destination: URL(string: "dontforget://calendar")!) {
                        homeColumn(
                            title: String(localized: "Geen open taken ✓"),
                            items: homeCalendarItems,
                            kind: .calendar,
                            maximum: homeRowCapacity
                        )
                    }
                } else {
                    Link(destination: URL(string: "dontforget://todo")!) {
                        homeColumn(
                            title: String(localized: "Taken"),
                            items: homeTodoItems,
                            kind: .todo,
                            maximum: homeRowCapacity
                        )
                    }
                }
            case "calendar":
                if shouldShowOtherContent, homeCalendarItems.isEmpty, !homeTodoItems.isEmpty {
                    Link(destination: URL(string: "dontforget://todo")!) {
                        homeColumn(
                            title: String(localized: "Lege agenda ✓"),
                            items: homeTodoItems,
                            kind: .todo,
                            maximum: homeRowCapacity
                        )
                    }
                } else {
                    Link(destination: URL(string: "dontforget://calendar")!) {
                        calendarHomeColumn(maximum: homeRowCapacity)
                    }
                }
            default:
                combinedHomeContent
        }
    }

    private var largeHomeScreenContent: some View {
        GeometryReader { proxy in
            if showsHomeTitle {
                VStack(alignment: .leading, spacing: 9) {
                    largeDateHeader
                        .frame(height: proxy.size.height * 0.12, alignment: .center)

                    Rectangle()
                        .fill(.secondary.opacity(0.16))
                        .frame(height: 1)

                    largeConfiguredContent
                }
            } else {
                largeConfiguredContent
            }
        }
    }

    private var largeDateHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(largeDateMainTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text(largeWeekTitle.uppercased(with: widgetLocale))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(brandBlue.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(brandBlue.opacity(0.10), lineWidth: 0.5)
                    }
            }

            Text(largeDateTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
            .foregroundStyle(brandBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityLabel(largeDateTitle)
    }

    @ViewBuilder
    private var largeConfiguredContent: some View {
        switch entry.snapshot.homeWidgetContent ?? "combined" {
        case "todo":
            largeColumn(
                title: String(localized: "Taken"),
                items: homeTodoItems,
                kind: .todo,
                maximum: largeSingleColumnCapacity
            )
        case "calendar":
            largeColumn(
                title: String(localized: "Kalender"),
                items: homeCalendarItems,
                kind: .calendar,
                maximum: largeSingleColumnCapacity
            )
        default:
            HStack(spacing: 10) {
                largeColumn(
                    title: String(localized: "Kalender"),
                    items: homeCalendarItems,
                    kind: .calendar,
                    maximum: largeCombinedColumnCapacity
                )
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 1)

                largeColumn(
                    title: String(localized: "Taken"),
                    items: homeTodoItems,
                    kind: .todo,
                    maximum: largeCombinedColumnCapacity
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func largeColumn(
        title: String,
        items: [WidgetCalendarItem],
        kind: HomeItemKind,
        maximum: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: wrapsHomeText ? 5 : 7) {
            if showsHomeTitle {
                HStack(alignment: .center, spacing: 6) {
                    Link(destination: sectionURL(for: kind)) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Link(destination: quickAddURL(for: kind)) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(kind == .calendar
                        ? "Toevoegen aan kalender"
                        : "Taak toevoegen")
                }
                .foregroundStyle(brandBlue)
            }

            Link(destination: sectionURL(for: kind)) {
                VStack(alignment: .leading, spacing: wrapsHomeText ? 4 : 6) {
                    if items.isEmpty {
                        Text(emptyText(for: kind))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        let displayedItems = Array(items.prefix(maximum))
                        ForEach(displayedItems) { item in
                            homeItemRow(item, kind: kind, displayedItems: displayedItems)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionURL(for kind: HomeItemKind) -> URL {
        URL(string: kind == .calendar ? "dontforget://calendar" : "dontforget://todo")!
    }

    private func quickAddURL(for kind: HomeItemKind) -> URL {
        var components = URLComponents()
        components.scheme = "dontforget"
        components.host = "quick-add"
        var queryItems = [URLQueryItem(
            name: "destination",
            value: kind == .calendar ? "calendar" : "todo"
        )]
        if kind == .todo,
           let categoryID = entry.snapshot.homeWidgetTodoCategoryID,
           !categoryID.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: categoryID))
        }
        components.queryItems = queryItems
        return components.url!
    }

    private var largeSingleColumnCapacity: Int {
        wrapsHomeText ? 7 : 11
    }

    private var largeCombinedColumnCapacity: Int {
        wrapsHomeText ? 6 : 10
    }

    private var largeDateTitle: String {
        "\(largeDateMainTitle), \(largeWeekTitle)"
    }

    private var largeDateMainTitle: String {
        let formatter = DateFormatter()
        formatter.locale = widgetLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let dateText = formatter.string(from: entry.date)
        return dateText.prefix(1).uppercased(with: widgetLocale) + String(dateText.dropFirst())
    }

    private var largeWeekTitle: String {
        var calendar = Calendar.current
        calendar.locale = widgetLocale
        let week = calendar.component(.weekOfYear, from: entry.date)
        return "week \(week)"
    }

    private var widgetLocale: Locale {
        Locale(identifier: entry.snapshot.localeIdentifier)
    }

    private var brandBlue: Color {
        Color(red: 59 / 255, green: 134 / 255, blue: 247 / 255)
    }

    private var homePrimaryTextColor: Color {
        if colorScheme == .dark,
           entry.snapshot.homeWidgetBackground == "brandLightBlue" {
            return Color(red: 185 / 255, green: 216 / 255, blue: 255 / 255)
        }
        return .primary
    }

    private var shouldShowOtherContent: Bool {
        entry.snapshot.homeWidgetShowsOtherWhenEmpty ?? true
    }

    @ViewBuilder
    private var combinedHomeContent: some View {
        if shouldShowOtherContent, homeCalendarItems.isEmpty, !homeTodoItems.isEmpty {
            Link(destination: URL(string: "dontforget://todo")!) {
                homeColumn(
                    title: String(localized: "Lege agenda ✓"),
                    items: homeTodoItems,
                    kind: .todo,
                    maximum: homeRowCapacity
                )
            }
        } else if shouldShowOtherContent, homeTodoItems.isEmpty, !homeCalendarItems.isEmpty {
            Link(destination: URL(string: "dontforget://calendar")!) {
                homeColumn(
                    title: String(localized: "Geen open taken ✓"),
                    items: homeCalendarItems,
                    kind: .calendar,
                    maximum: homeRowCapacity
                )
            }
        } else if family == .systemMedium || family == .systemLarge {
            HStack(spacing: 10) {
                Link(destination: URL(string: "dontforget://calendar")!) {
                    calendarHomeColumn(maximum: combinedRowCapacity)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 1)

                Link(destination: URL(string: "dontforget://todo")!) {
                    homeColumn(
                        title: String(localized: "Taken"),
                        items: homeTodoItems,
                        kind: .todo,
                        maximum: combinedRowCapacity
                    )
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Link(destination: URL(string: "dontforget://calendar")!) {
                    calendarHomeColumn(maximum: wrapsHomeText ? 1 : 2)
                }
                Divider().opacity(0.5)
                Link(destination: URL(string: "dontforget://todo")!) {
                    homeColumn(
                        title: String(localized: "Taken"),
                        items: homeTodoItems,
                        kind: .todo,
                        maximum: wrapsHomeText ? 1 : 2
                    )
                }
            }
        }
    }

    private var homeRowCapacity: Int {
        if wrapsHomeText {
            return family == .systemLarge ? (showsHomeTitle ? 9 : 10) : (showsHomeTitle ? 3 : 4)
        }
        return family == .systemLarge ? (showsHomeTitle ? 15 : 16) : (showsHomeTitle ? 5 : 6)
    }

    private var combinedRowCapacity: Int {
        if wrapsHomeText {
            return family == .systemLarge ? (showsHomeTitle ? 9 : 10) : (showsHomeTitle ? 3 : 4)
        }
        return family == .systemLarge ? (showsHomeTitle ? 15 : 16) : (showsHomeTitle ? 5 : 6)
    }

    private var showsHomeTitle: Bool {
        entry.snapshot.homeWidgetShowsTitle ?? true
    }

    private var wrapsHomeText: Bool {
        entry.snapshot.homeWidgetTextFlow == "wrap"
    }

    private enum HomeItemKind {
        case calendar, todo
    }

    @ViewBuilder
    private func calendarHomeColumn(maximum: Int) -> some View {
        homeColumn(
            title: String(localized: "Kalender"),
            items: homeCalendarItems,
            kind: .calendar,
            maximum: maximum
        )
    }

    private func homeColumn(
        title: String,
        items: [WidgetCalendarItem],
        kind: HomeItemKind,
        maximum: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: wrapsHomeText ? 4 : 6) {
            if showsHomeTitle {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 59 / 255, green: 134 / 255, blue: 247 / 255))
                    .lineLimit(1)
            }

            if items.isEmpty {
                Text(emptyText(for: kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                let displayedItems = Array(items.prefix(maximum))
                ForEach(displayedItems) { item in
                    homeItemRow(item, kind: kind, displayedItems: displayedItems)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func homeItemRow(
        _ item: WidgetCalendarItem,
        kind: HomeItemKind,
        displayedItems: [WidgetCalendarItem]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            homePrefixView(for: item, kind: kind, displayedItems: displayedItems)

            Text(item.title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(wrapsHomeText ? 2 : 1)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func homePrefixView(
        for item: WidgetCalendarItem,
        kind: HomeItemKind,
        displayedItems: [WidgetCalendarItem]
    ) -> some View {
        switch kind {
        case .todo:
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: entry.date)
            let createdDay = calendar.startOfDay(for: item.date)
            let age = max(0, calendar.dateComponents([.day], from: createdDay, to: today).day ?? 0)
            Text("\(age)d")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color(item.colorRawValue))
                .fixedSize(horizontal: true, vertical: false)
                .widgetAccentable()
        case .calendar:
            if (entry.snapshot.homeWidgetDatePrefix ?? "date") == "date" {
                ShortDatePrefixText(
                    date: item.date,
                    visibleDates: displayedItems.map(\.date),
                    format: resolvedDateFormat
                )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color(item.colorRawValue))
                    .fixedSize(horizontal: true, vertical: false)
                    .widgetAccentable()
            } else {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: entry.date)
                let itemDay = calendar.startOfDay(for: item.date)
                RelativeDayPrefixText(
                    value: calendar.dateComponents([.day], from: today, to: itemDay).day ?? 0,
                    visibleValues: displayedItems.map {
                        calendar.dateComponents(
                            [.day],
                            from: today,
                            to: calendar.startOfDay(for: $0.date)
                        ).day ?? 0
                    }
                )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color(item.colorRawValue))
                    .fixedSize(horizontal: true, vertical: false)
                    .widgetAccentable()
            }
        }
    }

    private func emptyText(for kind: HomeItemKind) -> String {
        switch kind {
        case .calendar: String(localized: "Lege agenda ✓")
        case .todo: String(localized: "Geen open taken")
        }
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: accessoryRowSpacing) {
            ForEach(visibleItems) { item in
                itemRow(item, accessory: true)
            }
            if visibleItems.isEmpty {
                Text("widget.noUpcomingItems")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 0)
    }

    private func itemRow(_ item: WidgetCalendarItem, accessory: Bool) -> some View {
        HStack(alignment: accessory ? .center : .firstTextBaseline, spacing: accessory ? 2 : 4) {
            if usesDisplayedDatePrefix(for: item, accessory: accessory) {
                ShortDatePrefixText(
                    date: item.date,
                    visibleDates: visibleItems.map(\.date),
                    format: resolvedDateFormat
                )
                    .font(.system(
                        size: accessory ? accessoryPrefixFontSize : 10,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundStyle(color(item.colorRawValue))
                    .fixedSize(horizontal: true, vertical: false)
                    .widgetAccentable()
            } else if let prefix = displayedTextPrefix(for: item, accessory: accessory) {
                RelativeDayPrefixText(
                    value: Int(prefix) ?? 0,
                    visibleValues: visibleItems.compactMap {
                        displayedTextPrefix(for: $0, accessory: accessory).flatMap(Int.init)
                    }
                )
                    .font(.system(
                        size: accessory ? accessoryPrefixFontSize : 10,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundStyle(color(item.colorRawValue))
                    .fixedSize(horizontal: true, vertical: false)
                    .widgetAccentable()
            }

            if accessory {
                WordAwareTruncatedText(
                    item.title,
                    fontSize: accessoryFontSize,
                    truncationMark: accessoryTruncationMark
                )
            } else {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !accessory {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryFontSize: CGFloat {
        switch visibleItems.count {
        case 0...2: 14
        case 3: 13
        case 4: 11.5
        default: 9.5
        }
    }

    private var accessoryPrefixFontSize: CGFloat {
        max(8.5, accessoryFontSize - 1)
    }

    private var accessoryRowSpacing: CGFloat {
        switch visibleItems.count {
        case 0...3: 2
        case 4: 1
        default: 0
        }
    }

    private var accessoryTruncationMark: String? {
        switch entry.snapshot.lockScreenWordTruncation {
        case "hyphen": "-"
        case "none": nil
        default: "…"
        }
    }

    private func usesDisplayedDatePrefix(for item: WidgetCalendarItem, accessory: Bool) -> Bool {
        if accessory, entry.snapshot.lockScreenItems != nil {
            return entry.snapshot.lockScreenDatePrefix == "date"
        }
        return true
    }

    private var resolvedDateFormat: WidgetDateFormatOption {
        WidgetDateFormatOption.resolved(
            from: entry.snapshot.dateFormat,
            localeIdentifier: entry.snapshot.localeIdentifier
        )
    }

    private func displayedTextPrefix(for item: WidgetCalendarItem, accessory: Bool) -> String? {
        if accessory, entry.snapshot.lockScreenItems != nil {
            return item.prefixText
        }
        return nil
    }

    private func color(_ rawValue: String?) -> Color {
        switch rawValue {
        case "blue": Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
        case "mint": Color(red: 0 / 255, green: 169 / 255, blue: 206 / 255)
        case "teal": Color(red: 0 / 255, green: 184 / 255, blue: 169 / 255)
        case "green": Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
        case "yellow": Color(red: 247 / 255, green: 198 / 255, blue: 0 / 255)
        case "orange": Color(red: 255 / 255, green: 138 / 255, blue: 28 / 255)
        case "red": Color(red: 255 / 255, green: 59 / 255, blue: 48 / 255)
        case "pink": Color(red: 255 / 255, green: 47 / 255, blue: 163 / 255)
        case "purple": Color(red: 175 / 255, green: 82 / 255, blue: 222 / 255)
        case "indigo": Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
        case "brown": Color(red: 168 / 255, green: 115 / 255, blue: 79 / 255)
        case "gray": Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
        default: .secondary
        }
    }
}

private struct RelativeDayPrefixText: View {
    let value: Int
    let visibleValues: [Int]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(reservedValues, id: \.self) { reservedValue in
                Text(reservedValue)
                    .opacity(0)
            }
            Text("\(value)")
        }
        .accessibilityLabel(Text("\(value)"))
    }

    private var reservedValues: [String] {
        let values = visibleValues.isEmpty ? [value] : visibleValues
        return Array(Set(values.map(String.init)))
    }
}

@main
struct UpcomingCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: UpcomingCalendarProvider()) { entry in
            UpcomingCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.gallery.name")
        .description("widget.gallery.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct ShortDatePrefixText: View {
    let date: Date
    let visibleDates: [Date]
    let format: WidgetDateFormatOption

    var body: some View {
        ZStack(alignment: .leading) {
            Text(reservedText)
                .opacity(0)
            visibleText
        }
        .accessibilityLabel(Text(visibleTextValue))
    }

    private var visibleText: some View {
        HStack(spacing: 0) {
            ForEach(Array(visibleParts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .value(let value, let reserveDigit):
                    if reserveDigit {
                        Text("1").opacity(0)
                    }
                    Text("\(value)")
                case .separator(let separator):
                    Text(separator)
                }
            }
        }
    }

    private var visibleTextValue: String {
        parts(reservingDigits: false).map(\.text).joined()
    }

    private var reservedText: String {
        parts(reservingDigits: true).map(\.text).joined()
    }

    private var visibleParts: [DatePrefixPart] {
        parts(reservingDigits: true)
    }

    private func parts(reservingDigits: Bool) -> [DatePrefixPart] {
        let dateOrder = format.dateOrder
        let first = value(for: dateOrder.first)
        let second = value(for: dateOrder.second)
        return [
            .value(first.value, reserveDigit: reservingDigits && first.reservesDigit),
            .separator(format.separator),
            .value(second.value, reserveDigit: reservingDigits && second.reservesDigit)
        ]
    }

    private func value(for component: DatePrefixComponent) -> (value: Int, reservesDigit: Bool) {
        switch component {
        case .day:
            let day = components(for: date).day
            return (day, visibleDateComponents.contains { $0.day >= 10 } && day < 10)
        case .month:
            let month = components(for: date).month
            return (month, visibleDateComponents.contains { $0.month >= 10 } && month < 10)
        }
    }

    private var visibleDateComponents: [(day: Int, month: Int)] {
        let dateComponents = visibleDates.map { components(for: $0) }
        return dateComponents.isEmpty ? [components(for: date)] : dateComponents
    }

    private func components(for date: Date) -> (day: Int, month: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.day, .month], from: date)
        return (components.day ?? 0, components.month ?? 0)
    }

    private enum DatePrefixPart {
        case value(Int, reserveDigit: Bool)
        case separator(String)

        var text: String {
            switch self {
            case .value(let value, let reserveDigit):
                return "\(reserveDigit ? "1" : "")\(value)"
            case .separator(let separator):
                return separator
            }
        }
    }
}

private enum DatePrefixComponent {
    case day
    case month
}

private enum WidgetDateFormatOption: String {
    case daySlashMonth = "dd/mm"
    case dayHyphenMonth = "dd-mm"
    case dayDotMonth = "dd.mm"
    case monthSlashDay = "mm/dd"
    case monthHyphenDay = "mm-dd"
    case monthDotDay = "mm.dd"

    var separator: String {
        switch self {
        case .daySlashMonth, .monthSlashDay: "/"
        case .dayHyphenMonth, .monthHyphenDay: "-"
        case .dayDotMonth, .monthDotDay: "."
        }
    }

    var dateOrder: (first: DatePrefixComponent, second: DatePrefixComponent) {
        switch self {
        case .daySlashMonth, .dayHyphenMonth, .dayDotMonth:
            return (.day, .month)
        case .monthSlashDay, .monthHyphenDay, .monthDotDay:
            return (.month, .day)
        }
    }

    static func resolved(from storedValue: String?, localeIdentifier: String) -> WidgetDateFormatOption {
        if let storedValue,
           storedValue != "system",
           let option = WidgetDateFormatOption(rawValue: storedValue) {
            return option
        }
        return localeDefault(for: Locale(identifier: localeIdentifier))
    }

    private static func localeDefault(for locale: Locale) -> WidgetDateFormatOption {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let pattern = formatter.dateFormat ?? "dd/MM"
        let dayIndex = pattern.firstIndex(of: "d") ?? pattern.startIndex
        let monthIndex = pattern.firstIndex(of: "M") ?? pattern.endIndex
        let separator = pattern.first { !$0.isLetter && !$0.isWhitespace } ?? "/"

        switch (dayIndex < monthIndex, separator) {
        case (true, "/"): return .daySlashMonth
        case (true, "-"): return .dayHyphenMonth
        case (true, "."): return .dayDotMonth
        case (false, "/"): return .monthSlashDay
        case (false, "-"): return .monthHyphenDay
        case (false, "."): return .monthDotDay
        default:
            return dayIndex < monthIndex ? .daySlashMonth : .monthSlashDay
        }
    }
}

private struct WordAwareTruncatedText: View {
    let text: String
    let fontSize: CGFloat
    let truncationMark: String?

    init(_ text: String, fontSize: CGFloat, truncationMark: String?) {
        self.text = text
        self.fontSize = fontSize
        self.truncationMark = truncationMark
    }

    var body: some View {
        GeometryReader { geometry in
            Text(textFitting(width: geometry.size.width))
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.97)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: ceil(uiFont.lineHeight))
        .layoutPriority(1)
    }

    private var uiFont: UIFont {
        .systemFont(ofSize: fontSize, weight: .medium)
    }

    private func textFitting(width: CGFloat) -> String {
        let visibleText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveWidth = width / 0.97
        guard measuredWidth(of: visibleText) > effectiveWidth else { return visibleText }

        let allCharacters = Array(visibleText)
        var fittingCharacters = allCharacters
        while !fittingCharacters.isEmpty,
              measuredWidth(of: String(fittingCharacters)) > effectiveWidth {
            fittingCharacters.removeLast()
        }

        let fittingText = String(fittingCharacters).trimmingCharacters(in: .whitespaces)
        guard let lastVisibleCharacter = fittingCharacters.last,
              fittingCharacters.count < allCharacters.count else {
            return fittingText
        }

        let nextHiddenCharacter = allCharacters[fittingCharacters.count]
        guard isWordCharacter(lastVisibleCharacter),
              isWordCharacter(nextHiddenCharacter) else {
            return fittingText
        }

        guard let truncationMark else { return fittingText }
        fittingCharacters = Array(fittingText)
        fittingCharacters.removeLast()
        while !fittingCharacters.isEmpty {
            let candidate = String(fittingCharacters) + truncationMark
            if measuredWidth(of: candidate) <= effectiveWidth {
                return candidate
            }
            fittingCharacters.removeLast()
        }
        return fittingText
    }

    private func measuredWidth(of value: String) -> CGFloat {
        (value as NSString).size(withAttributes: [.font: uiFont]).width
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }
    }
}
