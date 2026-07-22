import AppIntents
import AVFoundation
import Combine
import Speech
import SwiftData
import SwiftUI

extension Notification.Name {
    static let quickTodoCaptureRequested = Notification.Name("quickTodo.captureRequested")
}

enum QuickCapturePreparation {
    @discardableResult
    static func prepareConfirmation(defaults: UserDefaults = .standard) -> String {
        let signature = confirmationSignature(defaults: defaults)
        if defaults.string(forKey: SettingsKeys.quickCaptureConfirmationSignature) == signature,
           let prepared = defaults.string(forKey: SettingsKeys.quickCaptureConfirmation),
           !prepared.isEmpty {
            return prepared
        }

        let destination = ActionButtonDefaultDestination(
            rawValue: defaults.string(forKey: SettingsKeys.actionButtonDefaultDestination) ?? ""
        ) ?? .topTodoCategory
        let destinationDescription: String
        if destination == .calendarToday {
            destinationDescription = AppCalendar.locale.localized("kalender vandaag")
        } else {
            let groups = TodoGroupStore.decode(
                defaults.string(forKey: SettingsKeys.todoGroups) ?? ""
            )
            let configuredGroupID = defaults.string(
                forKey: SettingsKeys.actionButtonTaskCategoryID
            ) ?? ""
            destinationDescription = groups.first(where: { $0.id == configuredGroupID })?.title
                ?? groups.first?.title
                ?? TodoGroupStore.defaults[0].title
        }

        let confirmation = AppCalendar.locale.localizedFormat("quick.addedTo", destinationDescription)
        defaults.set(confirmation, forKey: SettingsKeys.quickCaptureConfirmation)
        defaults.set(signature, forKey: SettingsKeys.quickCaptureConfirmationSignature)
        return confirmation
    }

    private static func confirmationSignature(defaults: UserDefaults) -> String {
        [
            defaults.string(forKey: SettingsKeys.actionButtonDefaultDestination) ?? "",
            defaults.string(forKey: SettingsKeys.actionButtonTaskCategoryID) ?? "",
            defaults.string(forKey: SettingsKeys.todoGroups) ?? "",
            AppCalendar.language.rawValue
        ].joined(separator: "\u{1F}")
    }
}

struct CaptureTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Nieuwe taak"
    static let description = IntentDescription(
        "Opent direct een invoerveld voor een nieuwe taak."
    )
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(
        title: "Tekst",
        requestValueDialog: "Wat wil je niet vergeten?"
    )
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let launchMode = ActionButtonLaunchMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.actionButtonLaunchMode) ?? ""
        ) ?? .quickField

        if launchMode == .fullApp {
            UserDefaults.standard.set(true, forKey: SettingsKeys.quickTodoCaptureRequested)
            if #available(iOS 26.0, *) {
                try await continueInForeground(alwaysConfirm: false)
            }
            NotificationCenter.default.post(name: .quickTodoCaptureRequested, object: nil)
            return .result()
        }

        let suppliedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedText = suppliedText.isEmpty
            ? try await $text.requestValue("Wat wil je niet vergeten?")
            : suppliedText
        let cleaned = requestedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result()
        }

        let configuredDestination = ActionButtonDefaultDestination(
            rawValue: UserDefaults.standard.string(
                forKey: SettingsKeys.actionButtonDefaultDestination
            ) ?? ""
        ) ?? .topTodoCategory
        QuickCapturePreparation.prepareConfirmation()
        try saveQuickCapture(
            cleaned,
            usesCalendar: configuredDestination == .calendarToday
        )
        return .result()
    }

    @MainActor
    private func saveQuickCapture(_ text: String, usesCalendar: Bool) throws {
        let defaults = UserDefaults.standard
        let context = try AppModelStore.requireContainer().mainContext

        if usesCalendar {
            context.insert(DayEntry(date: .now, rawText: text, source: .manual))
            try context.save()
        } else {
            let groups = TodoGroupStore.decode(
                defaults.string(forKey: SettingsKeys.todoGroups) ?? ""
            )
            let configuredGroupID = defaults.string(
                forKey: SettingsKeys.actionButtonTaskCategoryID
            ) ?? ""
            let destinationGroup = groups.first(where: { $0.id == configuredGroupID })
                ?? groups.first
                ?? TodoGroupStore.defaults[0]
            let todo = TodoItem(text: text)
            todo.bucketRawValue = destinationGroup.id
            context.insert(todo)
            try context.save()
        }
    }
}

struct QuickCaptureSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Snelle invoer"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: QuickCaptureSnippetView())
    }
}

private struct QuickCaptureSnippetView: View {
    @State private var text = ""
    @State private var destinationID: String
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @StateObject private var speechRecorder = QuickSpeechRecorder()

    private let groups: [TodoGroup]
    private let startsVoiceRecording: Bool

    private static let agendaDestinationID = "__quickCaptureAgenda"

    init() {
        let defaults = UserDefaults.standard
        let decodedGroups = TodoGroupStore.decode(
            defaults.string(forKey: SettingsKeys.todoGroups) ?? ""
        )
        groups = decodedGroups.isEmpty ? TodoGroupStore.defaults : decodedGroups
        let destination = ActionButtonDefaultDestination(
            rawValue: defaults.string(
                forKey: SettingsKeys.actionButtonDefaultDestination
            ) ?? ""
        ) ?? .topTodoCategory
        _destinationID = State(initialValue: destination == .calendarToday
            ? Self.agendaDestinationID
            : groups[0].id)
        startsVoiceRecording = defaults.bool(
            forKey: SettingsKeys.actionButtonStartsVoiceRecording
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Snel toevoegen", systemImage: "text.badge.plus")
                    .font(.headline)
                Spacer()
                if speechRecorder.isRecording {
                    Text("Luistert…")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 10) {
                TextField("Wat wil je niet vergeten?", text: $text)
                    .textFieldStyle(.roundedBorder)

                Button {
                    toggleVoiceRecording()
                } label: {
                    Image(systemName: speechRecorder.isRecording ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundStyle(speechRecorder.isRecording ? .red : .secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(groups) { group in
                        Button {
                            destinationID = group.id
                        } label: {
                            Label(group.title, systemImage: group.icon)
                        }
                    }

                    Divider()

                    Button {
                        destinationID = Self.agendaDestinationID
                        agendaDate = AppCalendar.startOfDay(.now)
                    } label: {
                        Label("Kalender", systemImage: "calendar")
                    }
                } label: {
                    snippetSelectionLabel(
                        title: selectedGroup?.title ?? AppCalendar.locale.localized("Kalender"),
                        systemImage: selectedGroup?.icon ?? "calendar"
                    )
                }

                if destinationID == Self.agendaDestinationID {
                    DatePicker(
                        "Datum",
                        selection: $agendaDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            }

            if let error = speechRecorder.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(intent: SaveQuickCaptureSnippetIntent(
                text: text,
                destinationID: destinationID,
                agendaDate: agendaDate
            )) {
                Label("Voeg toe", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .task {
            if startsVoiceRecording {
                startVoiceRecording()
            }
        }
        .onDisappear {
            speechRecorder.stop()
        }
    }

    private var selectedGroup: TodoGroup? {
        groups.first { $0.id == destinationID }
    }

    private func snippetSelectionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, AdaptiveLayout.scaled(11))
        .frame(minHeight: AdaptiveLayout.scaled(38))
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AdaptiveLayout.scaled(10)))
    }

    private func toggleVoiceRecording() {
        if speechRecorder.isRecording {
            speechRecorder.stop()
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        let existingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            await speechRecorder.start { transcript in
                text = existingText.isEmpty ? transcript : "\(existingText) \(transcript)"
            }
        }
    }
}

struct SaveQuickCaptureSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Sla snelle invoer op"
    static let isDiscoverable = false

    @Parameter(title: "Tekst") var text: String
    @Parameter(title: "Bestemming") var destinationID: String
    @Parameter(title: "Datum") var agendaDate: Date

    init() {}

    init(text: String, destinationID: String, agendaDate: Date) {
        self.text = text
        self.destinationID = destinationID
        self.agendaDate = agendaDate
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result(dialog: "Er is geen tekst ingevoerd.")
        }

        let context = try AppModelStore.requireContainer().mainContext
        if destinationID == "__quickCaptureAgenda" {
            context.insert(DayEntry(date: agendaDate, rawText: cleaned, source: .manual))
        } else {
            let groups = TodoGroupStore.decode(
                UserDefaults.standard.string(forKey: SettingsKeys.todoGroups) ?? ""
            )
            let todo = TodoItem(text: cleaned)
            todo.bucketRawValue = groups.contains(where: { $0.id == destinationID })
                ? destinationID
                : groups.first?.id ?? TodoGroupStore.defaults[0].id
            context.insert(todo)
        }
        try context.save()
        return .result(dialog: "Toegevoegd.")
    }
}

struct DontForgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTodoIntent(),
            phrases: [
                "Nieuwe taak in \(.applicationName)",
                "Voeg een taak toe met \(.applicationName)"
            ],
            shortTitle: "Nieuwe taak",
            systemImageName: "text.badge.plus"
        )
    }
}

struct QuickTodoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let groups: [TodoGroup]
    let focusesKeyboardImmediately: Bool
    let onDismiss: (() -> Void)?

    @State private var text = ""
    @State private var destinationID: String
    @State private var agendaDate = AppCalendar.startOfDay(.now)
    @State private var isShowingDatePicker = false
    @StateObject private var speechRecorder = QuickSpeechRecorder()
    @FocusState private var isTextFieldFocused: Bool

    @AppStorage(SettingsKeys.actionButtonStartsVoiceRecording)
    private var startsVoiceRecording = false

    init(
        groups: [TodoGroup],
        initialDestinationID: String? = nil,
        focusesKeyboardImmediately: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        let normalizedGroups = groups.isEmpty ? TodoGroupStore.defaults : groups
        self.groups = normalizedGroups
        self.focusesKeyboardImmediately = focusesKeyboardImmediately
        self.onDismiss = onDismiss
        let destination = ActionButtonDefaultDestination(
            rawValue: UserDefaults.standard.string(
                forKey: SettingsKeys.actionButtonDefaultDestination
            ) ?? ""
        ) ?? .topTodoCategory
        let configuredGroupID = UserDefaults.standard.string(
            forKey: SettingsKeys.actionButtonTaskCategoryID
        ) ?? ""
        let defaultGroupID = normalizedGroups.first(where: { $0.id == configuredGroupID })?.id
            ?? normalizedGroups[0].id
        let requestedDestinationID: String?
        if initialDestinationID == Self.agendaDestinationID {
            requestedDestinationID = Self.agendaDestinationID
        } else if let initialDestinationID,
                  normalizedGroups.contains(where: { $0.id == initialDestinationID }) {
            requestedDestinationID = initialDestinationID
        } else {
            requestedDestinationID = nil
        }
        _destinationID = State(initialValue: requestedDestinationID
            ?? (destination == .calendarToday ? Self.agendaDestinationID : defaultGroupID))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    TextField("Wat wil je niet vergeten?", text: $text)
                        .font(.system(size: AdaptiveLayout.scaled(18)))
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(save)

                    Button {
                        if speechRecorder.isRecording {
                            speechRecorder.stop()
                        } else {
                            startVoiceRecording()
                        }
                    } label: {
                        Image(systemName: speechRecorder.isRecording ? "waveform.circle.fill" : "mic.circle")
                            .font(.system(size: AdaptiveLayout.scaled(23), weight: .medium))
                            .foregroundStyle(speechRecorder.isRecording ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speechRecorder.isRecording ? "Spraakopname stoppen" : "Spraakopname starten")
                }
                .padding(AdaptiveLayout.scaled(14))
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AdaptiveLayout.scaled(14)))

                if let error = speechRecorder.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Menu {
                        ForEach(groups) { group in
                            Button {
                                destinationID = group.id
                            } label: {
                                Label(group.title, systemImage: group.icon)
                            }
                        }
                    } label: {
                        selectionButtonLabel(
                            title: selectedGroup?.title ?? groups[0].title,
                            systemImage: selectedGroup?.icon ?? groups[0].icon,
                            isSelected: destinationID != Self.agendaDestinationID
                        )
                    }
                    .menuOrder(.fixed)
                    .accessibilityLabel("Categorie in Taken kiezen")

                    Button {
                        isTextFieldFocused = false
                        AppKeyboard.dismiss()

                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            isShowingDatePicker = true
                        }
                    } label: {
                        selectionButtonLabel(
                            title: destinationID == Self.agendaDestinationID
                                ? agendaDate.formatted(date: .abbreviated, time: .omitted)
                                : "Datum",
                            systemImage: "calendar",
                            isSelected: destinationID == Self.agendaDestinationID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Datum in agenda kiezen")
                    .popover(isPresented: $isShowingDatePicker) {
                        DatePicker(
                            "Kies een datum",
                            selection: agendaDateSelection,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(width: AdaptiveLayout.scaled(320))
                        .padding(AdaptiveLayout.scaled(8))
                        .iPadComfortableControls()
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AdaptiveLayout.scaled(18))
            .navigationTitle("Snel toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Voeg toe", action: save)
                        .disabled(cleanText.isEmpty)
                }
            }
            .onAppear {
                if focusesKeyboardImmediately {
                    focusTextField()
                } else if startsVoiceRecording {
                    startVoiceRecording()
                } else {
                    focusTextField()
                }
            }
            .onDisappear {
                speechRecorder.stop()
            }
        }
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
    }

    static let agendaDestinationID = "__quickCaptureAgenda"

    private var cleanText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedGroup: TodoGroup? {
        groups.first { $0.id == destinationID }
    }

    private var agendaDateSelection: Binding<Date> {
        Binding(
            get: { agendaDate },
            set: { newDate in
                agendaDate = AppCalendar.startOfDay(newDate)
                destinationID = Self.agendaDestinationID
                isShowingDatePicker = false
            }
        )
    }

    private func selectionButtonLabel(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: AdaptiveLayout.scaled(10), weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: AdaptiveLayout.scaled(14), weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, AdaptiveLayout.scaled(12))
        .frame(maxWidth: .infinity, minHeight: AdaptiveLayout.scaled(44))
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AdaptiveLayout.scaled(12))
        )
    }

    private func save() {
        guard !cleanText.isEmpty else { return }

        if destinationID == Self.agendaDestinationID {
            modelContext.insert(DayEntry(
                date: agendaDate,
                rawText: cleanText,
                source: .manual
            ))
        } else {
            let todo = TodoItem(text: cleanText)
            todo.bucketRawValue = destinationID
            modelContext.insert(todo)
        }

        _ = PersistenceSafety.save(modelContext)
        close()
    }

    private func close() {
        speechRecorder.stop()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func startVoiceRecording() {
        isTextFieldFocused = false
        AppKeyboard.dismiss()
        let existingText = cleanText
        let stopWord = AppCalendar.locale.localized("speech.stopWord")
        Task { @MainActor in
            await speechRecorder.start(
                stopWord: stopWord,
                update: { transcript in
                    text = existingText.isEmpty ? transcript : "\(existingText) \(transcript)"
                },
                stoppedByWord: {
                    Task { @MainActor in
                        await Task.yield()
                        save()
                    }
                }
            )
        }
    }

    private func focusTextField() {
        Task { @MainActor in
            // The capture view is shown with a transition. Waiting one turn ensures
            // the text field is in the view hierarchy before asking for focus.
            await Task.yield()
            isTextFieldFocused = true
        }
    }
}

@MainActor
private final class QuickSpeechRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start(
        stopWord: String? = nil,
        update: @escaping (String) -> Void,
        stoppedByWord: @escaping () -> Void = {}
    ) async {
        guard !isRecording else { return }
        errorMessage = nil

        guard await requestSpeechPermission() else {
            errorMessage = AppCalendar.locale.localized("speech.error.permission")
            return
        }
        guard await requestMicrophonePermission() else {
            errorMessage = AppCalendar.locale.localized("speech.error.microphone")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            errorMessage = AppCalendar.locale.localized("speech.error.unavailable")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        let words = transcript.split(separator: " ").map(String.init)
                        let reachedStopWord = stopWord.map { expected in
                            words.last.map(self.normalize) == self.normalize(expected)
                        } ?? false
                        let visibleWords = reachedStopWord ? words.dropLast() : words[...]
                        update(visibleWords.joined(separator: " "))
                        if reachedStopWord {
                            self.stop()
                            stoppedByWord()
                            return
                        }
                    }
                    if error != nil {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
            errorMessage = AppCalendar.locale.localized("speech.error.startFailed")
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
