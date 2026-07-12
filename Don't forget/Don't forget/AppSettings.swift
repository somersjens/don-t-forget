import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    /// Primary brand blue: #3B86F7.
    static let brandHardBlue = Color(
        red: 59.0 / 255.0,
        green: 134.0 / 255.0,
        blue: 247.0 / 255.0
    )

    /// Light brand surface: #CFE0F7. Intended for light-mode selection fills.
    static let brandLightBlue = Color(
        red: 207.0 / 255.0,
        green: 224.0 / 255.0,
        blue: 247.0 / 255.0
    )

    /// Neutral brand surface used for calm, full-screen moments.
    static let brandLightGrey = Color(
        red: 243.0 / 255.0,
        green: 245.0 / 255.0,
        blue: 248.0 / 255.0
    )

    /// Branded light canvas used by the default color combination: #F0F6FE.
    static let brandCanvasBlue = Color(hex: 0xF0F6FE)

    static var appCanvasBackground: Color {
        guard DefaultColorCombination.isEnabled else {
#if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
#else
            return Color(.systemBackground)
#endif
        }
        return .brandCanvasBlue
    }

    static var appCardBackground: Color {
        guard DefaultColorCombination.isEnabled else {
#if os(macOS)
            return Color.black.opacity(0.045)
#else
            return Color(.secondarySystemBackground)
#endif
        }
        return .white
    }

    static var appCardOutline: Color {
        DefaultColorCombination.isEnabled
            ? Color(hex: 0x4F84EF).opacity(0.25)
            : .clear
    }
}

enum DefaultColorCombination {
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.defaultColorCombinationEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: SettingsKeys.defaultColorCombinationEnabled)
    }
}

struct TutorialCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var replayFrame = CGRect.zero

    let isCompleted: Bool
    let close: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(.leading, isCompleted ? 6 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(colorScheme == .light
                                ? Color.brandLightBlue.opacity(0.28)
                                : Color.brandHardBlue.opacity(0.12))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.brandHardBlue.opacity(0.38), lineWidth: 2)
            }
            .shadow(color: Color.brandHardBlue.opacity(0.10), radius: 12, y: 5)
            .coordinateSpace(name: "tutorialCompletionCard")
            .onPreferenceChange(TutorialReplayFramePreferenceKey.self) { replayFrame = $0 }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named("tutorialCompletionCard"))
                    .onEnded { value in
                        let tappedReplay = replayFrame != .zero
                            && replayFrame.insetBy(dx: -4, dy: -4).contains(value.location)
                        guard isCompleted, !tappedReplay else {
                            return
                        }
                        close()
                    }
            )
    }
}

private struct TutorialReplayFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func tutorialCardStyle(isCompleted: Bool, close: @escaping () -> Void) -> some View {
        modifier(TutorialCardStyle(isCompleted: isCompleted, close: close))
    }
}

struct TutorialCompletionBrandIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCelebrating = false

    var body: some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandHardBlue)
                .scaleEffect(isCelebrating ? 1 : 0.35)
                .opacity(isCelebrating ? 1 : 0)
                .offset(x: 23, y: -15)
                .zIndex(-1)

            Image("OnboardingLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 55, height: 55)
                .scaleEffect(isCelebrating ? 1 : 0.58)
                .rotationEffect(.degrees(reduceMotion ? 0 : (isCelebrating ? 0 : -12)))
        }
        // Match the vertical footprint of the 44-point leading sticky-header button.
        .frame(width: 48, height: 44)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.58)) {
                isCelebrating = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct TutorialCompletionContent: View {
    let message: String
    let replayTitle: String
    let backAccessibilityLabel: String
    let closeAccessibilityLabel: String
    let back: () -> Void
    let replay: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 13) {
                TutorialCompletionBrandIcon()
                    .zIndex(0)

                VStack(alignment: .leading, spacing: 8) {
                    messageLabel
                    replayButton
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, 14)

            closeButton
        }
    }

    private var messageLabel: some View {
        Text(message)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .zIndex(1)
    }

    private var replayButton: some View {
        HStack(spacing: 5) {
            Button(action: back) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backAccessibilityLabel)

            Button(replayTitle, action: replay)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialReplayFramePreferenceKey.self,
                    value: proxy.frame(in: .named("tutorialCompletionCard"))
                )
                }
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandHardBlue)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(closeAccessibilityLabel)
    }
}

enum SettingsKeys {
    static let weekStart = "settings.weekStart"
    static let weekdayLabelLength = "settings.weekdayLabelLength"
    static let weekNumberRule = "settings.weekNumberRule"
    static let dateFormat = "settings.dateFormat"
    static let language = "settings.language"
    static let calendarSyncEnabled = "settings.calendarSyncEnabled"
    static let calendarLastSyncDate = "settings.calendarLastSyncDate"
    static let weatherInAgendaEnabled = "settings.weatherInAgendaEnabled"
    static let weatherLocationName = "settings.weatherLocationName"
    static let weatherLatitude = "settings.weatherLatitude"
    static let weatherLongitude = "settings.weatherLongitude"
    static let weatherLastError = "settings.weatherLastError"
    static let weatherLastErrorDetails = "settings.weatherLastErrorDetails"
    static let weatherReloadToken = "settings.weatherReloadToken"
    static let recurringLastSyncSignature = "settings.recurringLastSyncSignature"
    static let recurringHorizon = "settings.recurringHorizon"
    static let recurringExtendedThrough = "settings.recurringExtendedThrough"
    static let recurringBirthdayColor = "settings.recurringBirthdayColor"
    static let recurringGeneralColor = "settings.recurringGeneralColor"
    static let recurringPersonalColor = "settings.recurringPersonalColor"
    static let recurringCategories = "settings.recurringCategories"
    static let recurringShowNextDate = "settings.recurringShowNextDate"
    static let recurringCompactRows = "settings.recurringCompactRows"
    static let recurringCompactCategoryIDs = "settings.recurringCompactCategoryIDs"
    static let recurringSoonestFirst = "settings.recurringSoonestFirst"
    static let recurringShowHolidays = "settings.recurringShowHolidays"
    static let recurringHolidayCountry = "settings.recurringHolidayCountry"
    static let recurringOnlyLocalHolidays = "settings.recurringOnlyLocalHolidays"
    static let recurringBirthdayCategoryDeleted = "settings.recurringBirthdayCategoryDeleted"
    static let todoGroups = "settings.todoGroups"
    static let historyShowsDeletedItems = "settings.historyShowsDeletedItems"
    static let historyRetention = "settings.historyRetention"
    static let iCloudSyncEnabled = "settings.iCloudSyncEnabled"
    static let defaultColorCombinationEnabled = "settings.defaultColorCombinationEnabled"
    static let endOfDayReminderEnabled = "settings.endOfDayReminderEnabled"
    static let endOfDayReminderMinutes = "settings.endOfDayReminderMinutes"
    static let actionButtonContent = "settings.actionButtonContent"
    static let actionButtonDatePrefix = "settings.actionButtonDatePrefix"
    static let actionButtonItemCount = "settings.actionButtonItemCount"
    static let lockScreenWordTruncation = "settings.lockScreenWordTruncation"
    static let homeWidgetContent = "settings.homeWidgetContent"
    static let homeWidgetCalendarRange = "settings.homeWidgetCalendarRange"
    static let homeWidgetDatePrefix = "settings.homeWidgetDatePrefix"
    static let homeWidgetTextFlow = "settings.homeWidgetTextFlow"
    static let homeWidgetShowsTitle = "settings.homeWidgetShowsTitle"
    static let homeWidgetBackground = "settings.homeWidgetBackground"
    static let homeWidgetShowsOtherWhenEmpty = "settings.homeWidgetShowsOtherWhenEmpty"
    static let homeWidgetTodoCategoryID = "settings.homeWidgetTodoCategoryID"
    static let actionButtonDefaultDestination = "settings.actionButtonDefaultDestination"
    static let actionButtonTaskCategoryID = "settings.actionButtonTaskCategoryID"
    static let actionButtonStartsVoiceRecording = "settings.actionButtonStartsVoiceRecording"
    static let actionButtonLaunchMode = "settings.actionButtonLaunchMode"
    static let quickCaptureConfirmation = "quickTodo.preparedConfirmation"
    static let quickCaptureConfirmationSignature = "quickTodo.preparedConfirmationSignature"
    static let quickTodoCaptureRequested = "quickTodo.captureRequested"
    static let hasCompletedWelcome = "settings.hasCompletedWelcome"
    static let hasPresentedAgendaHelp = "onboarding.agenda.hasPresented"
    static let hasOpenedAgendaHelp = "onboarding.agenda.hasOpened"
    static let agendaTutorialStep = "onboarding.agenda.tutorialStep"
    static let hasCompletedAgendaTutorial = "onboarding.agenda.hasCompletedTutorial"
    static let hasSeededAgendaExamples = "onboarding.agenda.hasSeededExamples"
    static let hasUsedMacAgendaInput = "onboarding.macAgenda.hasUsedInput"
    static let agendaSportsExampleID = "onboarding.agenda.sportsExampleID"
    static let agendaDinnerExampleID = "onboarding.agenda.dinnerExampleID"
    static let hasOpenedTodoHelp = "onboarding.todo.hasOpened"
    static let todoTutorialStep = "onboarding.todo.tutorialStep"
    static let hasCompletedTodoTutorial = "onboarding.todo.hasCompletedTutorial"
    static let hasOpenedRecurringHelp = "onboarding.recurring.hasOpened"
    static let isRecurringHelpExpanded = "onboarding.recurring.isExpanded"
    static let recurringTutorialStep = "onboarding.recurring.tutorialStep"
    static let hasCompletedRecurringTutorial = "onboarding.recurring.hasCompletedTutorial"
    static let recurringTutorialCategoryID = "onboarding.recurring.categoryID"
    static let hasOpenedHistoryHelp = "onboarding.history.hasOpened"
    static let historyTutorialStep = "onboarding.history.tutorialStep"
    static let hasCompletedHistoryTutorial = "onboarding.history.hasCompletedTutorial"
    static let historyTutorialExampleID = "onboarding.history.exampleID"
}

enum WeekdayLabelLengthOption: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    static func resolved(storedValue: Int, locale: Locale) -> Int {
        if (1...3).contains(storedValue) { return storedValue }
        return 1
    }

    func title(for locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let mondayThroughWednesday = Array((formatter.weekdaySymbols ?? []).dropFirst().prefix(3))
        return mondayThroughWednesday
            .map { String($0.prefix(rawValue)).localizedCapitalized }
            .joined(separator: ",")
    }
}

enum HistoryRetentionOption: String, CaseIterable, Identifiable {
    case never
    case oneWeek
    case oneMonth
    case oneYear

    static let `default`: Self = .never

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .never: locale.localized("Nooit")
        case .oneWeek: locale.localized("Na 1 week")
        case .oneMonth: locale.localized("Na 1 maand")
        case .oneYear: locale.localized("Na 1 jaar")
        }
    }

    func cutoffDate(from date: Date, calendar: Calendar = AppCalendar.calendar) -> Date? {
        switch self {
        case .never: nil
        case .oneWeek: calendar.date(byAdding: .weekOfYear, value: -1, to: date)
        case .oneMonth: calendar.date(byAdding: .month, value: -1, to: date)
        case .oneYear: calendar.date(byAdding: .year, value: -1, to: date)
        }
    }
}

enum RecurringHorizonOption: String, CaseIterable, Identifiable {
    case threeMonths
    case halfYear
    case nineMonths
    case oneYear
    case oneAndHalfYears
    case twoYears

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .threeMonths: 3
        case .halfYear: 6
        case .nineMonths: 9
        case .oneYear: 12
        case .oneAndHalfYears: 18
        case .twoYears: 24
        }
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .threeMonths: locale.localized("3 maanden")
        case .halfYear: locale.localized("6 maanden")
        case .nineMonths: locale.localized("9 maanden")
        case .oneYear: locale.localized("1 jaar")
        case .oneAndHalfYears: locale.localized("1,5 jaar")
        case .twoYears: locale.localized("2 jaar")
        }
    }
}

enum ActionButtonContentOption: String, CaseIterable, Identifiable {
    case today
    case todayAndTomorrow
    case todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Alleen vandaag"
        case .todayAndTomorrow: "Vandaag & morgen"
        case .todo: "Bovenste taken"
        }
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .today: locale.localized("Alleen vandaag")
        case .todayAndTomorrow: locale.localized("Vandaag & morgen")
        case .todo: locale.localized("Bovenste taken")
        }
    }
}

enum ActionButtonDatePrefixOption: String, CaseIterable, Identifiable {
    case date
    case dayCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: "Datum (dd/mm)"
        case .dayCount: "0 = vandaag, 1 = morgen"
        }
    }

    var selectionTitle: String {
        switch self {
        case .date: "Datum"
        case .dayCount: "Dagen tellen"
        }
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .date: locale.localized("Datum (dd/mm)")
        case .dayCount: locale.localized("0 = vandaag, 1 = morgen")
        }
    }

    func selectionTitle(for locale: Locale) -> String {
        switch self {
        case .date: locale.localized("Datum")
        case .dayCount: locale.localized("Dagen tellen")
        }
    }
}

enum LockScreenWordTruncationOption: String, CaseIterable, Identifiable {
    case ellipsis
    case hyphen
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ellipsis: "Met …"
        case .hyphen: "Met -"
        case .none: "Niet"
        }
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .ellipsis: locale.localized("Met …")
        case .hyphen: locale.localized("Met -")
        case .none: locale.localized("Niet")
        }
    }
}

enum HomeWidgetContentOption: String, CaseIterable, Identifiable {
    case combined
    case calendar
    case todo

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .calendar: locale.localized("Kalender")
        case .todo: locale.localized("Taken")
        case .combined: locale.localized("Kalender + taken")
        }
    }
}

enum HomeWidgetCalendarRangeOption: String, CaseIterable, Identifiable {
    case today
    case todayAndTomorrow
    case upcoming

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .today: locale.localized("Vandaag")
        case .todayAndTomorrow: locale.localized("Vandaag + morgen")
        case .upcoming: locale.localized("Alles wat past")
        }
    }
}

enum HomeWidgetBackgroundOption: String, CaseIterable, Identifiable {
    case brandLightBlue
    case white

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .brandLightBlue: locale.localized("Lichtblauw")
        case .white: locale.localized("Wit")
        }
    }
}

enum HomeWidgetTextFlowOption: String, CaseIterable, Identifiable {
    case truncate
    case wrap

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .truncate: locale.localized("Afsnijden als het te lang is")
        case .wrap: locale.localized("Doorlopen op nieuwe regel")
        }
    }
}

enum ActionButtonDefaultDestination: String, CaseIterable, Identifiable {
    case topTodoCategory
    case calendarToday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topTodoCategory: "Bovenste categorie in Taken"
        case .calendarToday: "Kalender vandaag"
        }
    }
}

enum ActionButtonLaunchMode: String, CaseIterable, Identifiable {
    case quickField
    case fullApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickField: "Alleen snel invoerveld"
        case .fullApp: "Hele app openen"
        }
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .quickField: locale.localized("Alleen snel invoerveld")
        case .fullApp: locale.localized("Hele app openen")
        }
    }
}

enum WeekStartOption: String, CaseIterable, Identifiable {
    case monday
    case sunday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monday: "Maandag"
        case .sunday: "Zondag"
        }
    }

    func title(for locale: Locale) -> String {
        locale.localized(title)
    }

    var calendarWeekday: Int {
        self == .monday ? 2 : 1
    }
}

enum WeekNumberRule: String, CaseIterable, Identifiable {
    case iso8601
    case januaryFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iso8601: "ISO 8601"
        case .januaryFirst: "1 januari in week 1"
        }
    }


    func title(for locale: Locale) -> String {
        locale.localized(title)
    }
}

enum DateFormatOption: String, CaseIterable, Identifiable {
    case system
    case daySlashMonth = "dd/mm"
    case dayHyphenMonth = "dd-mm"
    case dayDotMonth = "dd.mm"
    case monthSlashDay = "mm/dd"
    case monthHyphenDay = "mm-dd"
    case monthDotDay = "mm.dd"

    var id: String { rawValue }

    var dateFormat: String? {
        switch self {
        case .system: nil
        case .daySlashMonth: "dd/MM"
        case .dayHyphenMonth: "dd-MM"
        case .dayDotMonth: "dd.MM"
        case .monthSlashDay: "MM/dd"
        case .monthHyphenDay: "MM-dd"
        case .monthDotDay: "MM.dd"
        }
    }

    func title(for locale: Locale, localeDefault: DateFormatOption) -> String {
        if self == .system {
            return locale.localizedFormat("Standaard (%@)", localeDefault.displayTitle)
        }
        return displayTitle
    }

    var displayTitle: String {
        switch self {
        case .system: ""
        case .daySlashMonth: "dd/mm"
        case .dayHyphenMonth: "dd-mm"
        case .dayDotMonth: "dd.mm"
        case .monthSlashDay: "mm/dd"
        case .monthHyphenDay: "mm-dd"
        case .monthDotDay: "mm.dd"
        }
    }

    static func resolved(from storedValue: String?) -> DateFormatOption {
        guard let storedValue,
              let option = DateFormatOption(rawValue: storedValue) else {
            return .system
        }
        return option
    }

    static func localeDefault(for locale: Locale) -> DateFormatOption {
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

struct AppLanguage: RawRepresentable, Hashable, Identifiable, CaseIterable {
    let rawValue: String

    static let system = AppLanguage(rawValue: "system")!
    static let dutch = AppLanguage(rawValue: "nl")!
    static let english = AppLanguage(rawValue: "en")!

    var id: String { rawValue }

    static var allCases: [AppLanguage] {
        let localizedLanguages = Bundle.main.localizations
            .filter { $0 != "Base" }
            .compactMap(AppLanguage.init(rawValue:))
            .sorted { lhs, rhs in
                lhs.title(for: .current).localizedStandardCompare(rhs.title(for: .current)) == .orderedAscending
            }
        return [system] + localizedLanguages.filter { $0 != system }
    }

    nonisolated init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        switch normalized.lowercased() {
        case "dutch", "nederlands", "nl-nl", "nl_nl": self.rawValue = "nl"
        case "english", "engels", "en-us", "en_us": self.rawValue = "en"
        default: self.rawValue = normalized
        }
    }

    func title(for displayLocale: Locale) -> String {
        guard self != .system else { return displayLocale.localized("language.system") }
        let code = locale.language.languageCode?.identifier ?? rawValue
        return displayLocale.localizedString(forLanguageCode: code)
            ?? Locale.current.localizedString(forLanguageCode: code)
            ?? rawValue
    }

    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    static func resolved(from storedValue: String?) -> AppLanguage {
        let normalized = storedValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalized, let exact = AppLanguage(rawValue: normalized) {
            return exact
        }
        return .system
    }

    static func effective(from storedValue: String?, holidayCountryCode _: String?) -> AppLanguage {
        resolved(from: storedValue)
    }
}

enum AppSection {
    case agenda
    case recurring
    case todo
    case history

    func title(for locale: Locale) -> String {
        let key = switch self {
        case .agenda: "section.calendar"
        case .recurring: "section.recurring"
        case .todo: "section.todo"
        case .history: "section.finished"
        }
        return locale.localized(key)
    }
}

enum RecurringThemeColorOption: String, CaseIterable, Identifiable {
    case blue
    case cyan = "mint"
    case teal
    case green
    case yellow
    case orange
    case red
    case pink
    case purple
    case indigo
    case brown
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "Blauw"
        case .cyan: "Cyaan"
        case .teal: "Teal"
        case .green: "Groen"
        case .yellow: "Geel"
        case .orange: "Oranje"
        case .red: "Rood"
        case .pink: "Roze"
        case .purple: "Paars"
        case .indigo: "Indigo"
        case .brown: "Bruin"
        case .gray: "Grijs"
        }
    }

    func title(for locale: Locale) -> String {
        locale.localized(title)
    }

    var color: Color {
        let hex: UInt32 = switch self {
        case .blue: 0x0A84FF
        case .cyan: 0x00A9CE
        case .teal: 0x00B8A9
        case .green: 0x34C759
        case .yellow: 0xF7C600
        case .orange: 0xFF8A1C
        case .red: 0xFF3B30
        case .pink: 0xFF2FA3
        case .purple: 0xAF52DE
        case .indigo: 0x5856D6
        case .brown: 0xA8734F
        case .gray: 0x8E8E93
        }
        return Color(hex: hex)
    }

    var backgroundColor: Color {
        if self == .blue, DefaultColorCombination.isEnabled {
            return .brandCanvasBlue
        }
        let lightHex: UInt32 = switch self {
        case .blue: 0xD6EAFF
        case .cyan: 0xD8F7FC
        case .teal: 0xD7F7F3
        case .green: 0xDCF8E6
        case .yellow: 0xFFF4C7
        case .orange: 0xFFE7CF
        case .red: 0xFFE1DF
        case .pink: 0xFFE0F1
        case .purple: 0xF0DDF8
        case .indigo: 0xE6E5FA
        case .brown: 0xF0E2D8
        case .gray: 0xEAEAEE
        }
        let darkHex: UInt32 = switch self {
        case .blue: 0x162B40
        case .cyan: 0x12323A
        case .teal: 0x12352F
        case .green: 0x183523
        case .yellow: 0x3A3214
        case .orange: 0x3C2817
        case .red: 0x582020
        case .pink: 0x401B31
        case .purple: 0x321F3D
        case .indigo: 0x25243E
        case .brown: 0x34271F
        case .gray: 0x2C2C30
        }

#if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? darkHex : lightHex
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
#else
        return Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex))
        })
#endif
    }
}

extension Locale {
    var appDisplayName: String {
        localized("app.name")
    }

    func localized(_ key: String) -> String {
        localizedCatalogKey(key, defaultValue: key)
    }

    func localizedCatalogKey(
        _ key: String,
        defaultValue: String,
        bundle: Bundle = .main,
        table: String? = nil
    ) -> String {
        // A localized value may legitimately equal its key (many legacy keys are
        // Dutch source sentences). Use a distinct fallback to detect a missing
        // catalog entry instead of comparing the result with the key.
        let missingValue = "__MISSING_LOCALIZATION__\(key)__"
        let languageCode = language.languageCode?.identifier
        let candidates = [identifier, languageCode].compactMap { $0 }
        for candidate in candidates {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                let value = localizedBundle.localizedString(
                    forKey: key,
                    value: missingValue,
                    table: table
                )
                if value != missingValue { return value }
            }
        }
        if let path = bundle.path(forResource: "en", ofType: "lproj"),
           let englishBundle = Bundle(path: path) {
            let value = englishBundle.localizedString(
                forKey: key,
                value: missingValue,
                table: table
            )
            if value != missingValue { return value }
        }
        return defaultValue
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: self, arguments: arguments)
    }
}
