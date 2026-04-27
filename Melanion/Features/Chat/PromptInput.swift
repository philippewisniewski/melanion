import SwiftUI

struct PromptInput: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask anything about your runs…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onSubmit { if !isLoading { onSend() } }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accent : Theme.textSecondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(
            Theme.background
                .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        )
        .safeAreaPadding(.bottom)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}
