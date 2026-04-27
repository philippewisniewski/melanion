import SwiftUI

struct LoadingDots: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textSecondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { phase = 1 }
    }
}
