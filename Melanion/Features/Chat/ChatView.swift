import SwiftUI

struct ChatView: View {
    @Environment(LanguageModelService.self) private var languageModelService
    @State private var viewModel = ChatViewModel()
    @State private var welcomeData: WelcomeData?
    @State private var hasLoadedWelcome = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Text("Melanion")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.surface)

                // Message list + input using safeAreaInset
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.messages.isEmpty {
                                if let welcome = welcomeData {
                                    WelcomeCard(data: welcome)
                                        .padding(.top, 24)
                                        .id("welcome")
                                } else if hasLoadedWelcome {
                                    WelcomeCardEmpty()
                                        .padding(.top, 24)
                                        .id("welcome-empty")
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
                                VStack(alignment: .leading, spacing: 6) {
                                    if !viewModel.statusLabel.isEmpty {
                                        Text(viewModel.statusLabel)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                            .padding(.horizontal, 16)
                                    }
                                    LoadingDots()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                }
                                .id("loading")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
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
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    PromptInput(text: $viewModel.inputText, isLoading: viewModel.isLoading) {
                        Task { await viewModel.send(using: languageModelService) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            welcomeData = await viewModel.fetchWelcome()
            hasLoadedWelcome = true
            languageModelService.prewarm()
        }
    }
}
