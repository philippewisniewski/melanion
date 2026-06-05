import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 48) }

            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .overlay(alignment: .topTrailing) {
                    if message.role == .assistant {
                        copyButton
                    }
                }

            if message.role != .user { Spacer(minLength: 48) }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.content
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .padding(6)
                .background(Theme.surface.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(4)
        .transition(.opacity)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:      return Theme.userBubble
        case .assistant: return Theme.surface
        case .error:     return Color.red.opacity(0.15)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user, .assistant: return Theme.textPrimary
        case .error:            return .red
        }
    }
}
