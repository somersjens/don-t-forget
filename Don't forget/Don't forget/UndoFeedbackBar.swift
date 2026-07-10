import SwiftUI

struct UndoFeedbackBar: View {
    let iconSystemName: String
    let iconColor: Color
    let message: String
    let undoTitle: String
    let action: () -> Void
    var preferredMessageLineLimit: Int = 1

    private let textFont = Font.system(size: 14, weight: .medium)
    private let buttonFont = Font.system(size: 14, weight: .semibold)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(
                messageLineLimit: preferredMessageLineLimit,
                messageNeedsIdealWidth: true,
                undoLineLimit: 1,
                undoNeedsIdealWidth: true,
                undoWrapsByWord: false
            )

            content(
                messageLineLimit: 1,
                messageNeedsIdealWidth: true,
                undoLineLimit: 2,
                undoNeedsIdealWidth: false,
                undoWrapsByWord: true
            )

            content(
                messageLineLimit: 2,
                messageNeedsIdealWidth: false,
                undoLineLimit: 2,
                undoNeedsIdealWidth: false,
                undoWrapsByWord: true
            )
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: action)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func content(
        messageLineLimit: Int,
        messageNeedsIdealWidth: Bool,
        undoLineLimit: Int,
        undoNeedsIdealWidth: Bool,
        undoWrapsByWord: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .foregroundStyle(iconColor)

            Text(message)
                .font(textFont)
                .lineLimit(messageLineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: messageNeedsIdealWidth, vertical: true)
                .layoutPriority(2)

            Spacer(minLength: 4)

            Button(action: action) {
                undoLabel(
                    lineLimit: undoLineLimit,
                    needsIdealWidth: undoNeedsIdealWidth,
                    wrapsByWord: undoWrapsByWord
                )
            }
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func undoLabel(
        lineLimit: Int,
        needsIdealWidth: Bool,
        wrapsByWord: Bool
    ) -> some View {
        if wrapsByWord, let splitTitle = splitUndoTitle {
            VStack(spacing: 0) {
                Text(splitTitle.firstLine)
                Text(splitTitle.secondLine)
            }
            .font(buttonFont)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
        } else {
            Text(undoTitle)
                .font(buttonFont)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: needsIdealWidth || wrapsByWord, vertical: true)
        }
    }

    private var splitUndoTitle: (firstLine: String, secondLine: String)? {
        let words = undoTitle.split(separator: " ")
        guard words.count > 1 else { return nil }

        let firstLine = String(words.dropLast().joined(separator: " "))
        let secondLine = String(words.last ?? "")
        return (firstLine, secondLine)
    }
}
