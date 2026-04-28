import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
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

                if message.role != .user { Spacer(minLength: 48) }
            }

            // Card rendered below assistant bubble when data is available
            if message.role == .assistant,
               let format = message.responseFormat,
               let rows = message.cardRows,
               !rows.isEmpty {
                CardView(format: format, rows: rows)
            }
        }
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
        case .user:      return Theme.textPrimary
        case .assistant: return Theme.textPrimary
        case .error:     return .red
        }
    }
}
