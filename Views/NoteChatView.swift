import Combine
import SwiftUI

// MARK: - Keyboard observer (for input bar placement)

private final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification),
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let isShowing = notification.name == UIResponder.keyboardWillShowNotification
            withAnimation(.easeOut(duration: 0.25)) {
                self.height = isShowing ? frame.height : 0
            }
        }
        .store(in: &cancellables)
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

struct NoteChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var keyboard = KeyboardObserver()
    let noteTitle: String
    let context: String
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isWaiting = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Messages: full area with bottom space for input + keyboard
                messagesScroll
                    .padding(.bottom, inputBarHeight + keyboard.height)

                // Input bar: fixed just above the keyboard (we control position; no system avoidance)
                inputBar
                    .padding(.bottom, keyboard.height)
            }
            .ignoresSafeArea(.keyboard)
            .background(AppTheme.surfaceRaised)
            .preferredColorScheme(.light)
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("Ask about note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
                }
            }
        }
    }

    private let inputBarHeight: CGFloat = 72

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                    }
                    if isWaiting {
                        typingRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.spacingM)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, newCount in
                if newCount > 0 { scrollToEnd(proxy: proxy) }
            }
            .onChange(of: isWaiting) { _, waiting in
                // When answer arrives (isWaiting → false), scroll to show it
                if !waiting { scrollToEnd(proxy: proxy) }
            }
        }
    }

    private func scrollToEnd(proxy: ScrollViewProxy) {
        // Slight delay so new message is laid out; keeps answer visible (ChatGPT-style)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.25)) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.8))
            VStack(spacing: 8) {
                Text("Ask about this note")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Get answers from the summary, transcript, and written content.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if msg.isUser { Spacer(minLength: 48) }
            if !msg.isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            Text(msg.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(msg.isUser ? AppTheme.accent : AppTheme.surfaceBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(msg.isUser ? Color.clear : AppTheme.borderSubtle, lineWidth: 1)
                        )
                )
                .foregroundStyle(msg.isUser ? .white : AppTheme.textPrimary)
                .frame(maxWidth: 300, alignment: msg.isUser ? .trailing : .leading)
            if !msg.isUser { Spacer(minLength: 48) }
            if msg.isUser {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var typingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(AppTheme.textTertiary)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surfaceBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                    )
            )
            Spacer(minLength: 48)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.surfaceBase)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(AppTheme.borderSubtle, lineWidth: 1)
                            )
                    )
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .disabled(isWaiting)
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? AppTheme.accent : AppTheme.textTertiary)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, 12)
        }
        .frame(height: inputBarHeight)
        .background(AppTheme.surfaceRaised)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWaiting
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(ChatMessage(isUser: true, text: text))
        isWaiting = true
        // Dismiss keyboard so user can read the question; keep it dismissed when answer arrives
        inputFocused = false
        Task {
            let answer = await SummarizationService.shared.ask(question: text, context: context)
            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: answer))
                isWaiting = false
                // Keep keyboard closed so the answer stays visible (ChatGPT-style)
                inputFocused = false
            }
        }
    }
}
