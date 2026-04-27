import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var welcomeData: WelcomeData?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Text("Melanion")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.surface)

                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.messages.isEmpty {
                                if let welcome = welcomeData {
                                    WelcomeCard(data: welcome)
                                        .padding(.top, 24)
                                        .id("welcome")
                                } else {
                                    ProgressView()
                                        .tint(Theme.accent)
                                        .padding(.top, 48)
                                }
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                LoadingDots()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .id("loading")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                        .padding(.top, 16)
                    }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation {
                            if let lastId = viewModel.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoading) {
                        if viewModel.isLoading {
                            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                        }
                    }
                }
            }

            // Input pinned to bottom
            PromptInput(text: $viewModel.inputText, isLoading: viewModel.isLoading) {
                Task { await viewModel.send() }
            }
        }
        .task {
            welcomeData = await viewModel.fetchWelcome()
        }
    }
}
