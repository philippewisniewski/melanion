import SwiftUI

struct ChatView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Chat")
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
