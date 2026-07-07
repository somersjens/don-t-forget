import SwiftUI

/// Keeps edits local while the keyboard is active and publishes the finished
/// value only after editing has ended.
struct DeferredCommitTextField: View {
    let title: LocalizedStringKey
    let value: String
    let commit: (String) -> Void

    @State private var draft: String
    @State private var isKeyboardVisible = false
    @FocusState private var isFocused: Bool

    init(
        _ title: LocalizedStringKey,
        value: String,
        commit: @escaping (String) -> Void
    ) {
        self.title = title
        self.value = value
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(title, text: $draft)
            .focused($isFocused)
            .onSubmit {
                AppKeyboard.dismiss()
            }
            .onChange(of: value) { _, newValue in
                guard !isFocused else { return }
                draft = newValue
            }
            .onChange(of: isFocused) { wasFocused, focused in
                guard wasFocused, !focused, !isKeyboardVisible else { return }
                commitDraftIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidHideNotification
            )) { _ in
                isKeyboardVisible = false
                commitDraftIfNeeded()
            }
            .onDisappear {
                commitDraftIfNeeded()
            }
    }

    private func commitDraftIfNeeded() {
        guard draft != value else { return }
        commit(draft)
    }
}
