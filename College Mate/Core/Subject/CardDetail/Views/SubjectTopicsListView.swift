import SwiftUI
import SwiftData

// MARK: - Background-safe Link Detector
enum LinkDetectorHelper {
    static let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    static func detectURL(in text: String) -> URL? {
        guard let detector else { return nil }
        
        // 1. Try standard detection
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = detector.firstMatch(in: text, options: [], range: range), let url = match.url {
            return url
        }
        
        // 2. Fallback: If it looks like a domain (has dot, no spaces) but missing http/https
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.contains(" ") && trimmed.contains(".") {
            let fixedText = "https://" + trimmed
            let fixedRange = NSRange(fixedText.startIndex..<fixedText.endIndex, in: fixedText)
            if let match = detector.firstMatch(in: fixedText, options: [], range: fixedRange), let url = match.url {
                return url
            }
        }
        
        return nil
    }
}

struct SubjectTopicsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var subject: Subject

    @FocusState private var focusedItemId: UUID?
    @State private var isKeyboardVisible = false

    private var sortedTopics: [TopicItem] {
        (subject.topics ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appBackground
                    .ignoresSafeArea()

                if !sortedTopics.isEmpty {
                    List {
                        ForEach(sortedTopics) { item in
                            TopicRowView(
                                item: item,
                                focusedItemId: $focusedItemId,
                                onDelete: deleteItem
                            )
                            .listRowBackground(
                                Color(.secondarySystemGroupedBackground).opacity(0.7)
                            )
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    emptyState
                }

                if isKeyboardVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                focusedItemId = nil
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Important Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addNewItem() } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        focusedItemId = nil
                        cleanupEmptyItems()
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: observeKeyboard)
            .onDisappear {
                removeKeyboardObservers()
                cleanupEmptyItems()
                saveChanges()
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.8))

            Text("No Topics Added")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("You can add drive links or important topics for exam.")
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // MARK: - Updated Button UI
            Button { addNewItem() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                    Text("Add First Topic")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial) // Matches keyboard button glass effect
                .clipShape(Capsule())
                .shadow(radius: 4) // Matches keyboard button shadow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard
    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in isKeyboardVisible = true }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in isKeyboardVisible = false }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Logic
    private func addNewItem() {
        let item = TopicItem(text: "")
        subject.topics = (subject.topics ?? []) + [item]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedItemId = item.id
        }
    }

    private func deleteItem(_ item: TopicItem) {
        if let index = subject.topics?.firstIndex(of: item) {
            subject.topics?.remove(at: index)
            modelContext.delete(item)
            saveChanges()
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            deleteItem(sortedTopics[index])
        }
    }

    private func cleanupEmptyItems() {
        subject.topics?.removeAll {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func saveChanges() {
        Task { @MainActor in
            try? modelContext.save()
        }
    }
}

// MARK: - Topic Row
struct TopicRowView: View {
    @Bindable var item: TopicItem
    var focusedItemId: FocusState<UUID?>.Binding
    var onDelete: (TopicItem) -> Void

    @State private var detectedURL: URL?
    @State private var debounceTask: Task<Void, Never>?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { toggleCompletion() } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .gray)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Enter topic or link...", text: $item.text, axis: .vertical)
                    .focused(focusedItemId, equals: item.id)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .onSubmit {
                        focusedItemId.wrappedValue = nil
                    }
                    .onChange(of: item.text) {
                        performDebouncedSearch(delay: true)
                    }

                // MARK: - Link UI
                if let url = detectedURL, !item.isCompleted {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari.fill")
                                .font(.subheadline)
                            
                            Text(url.absoluteString)
                                .font(.footnote)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.blue)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
        .swipeActions {
            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .onAppear {
            if !item.text.isEmpty {
                performDebouncedSearch(delay: false)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func toggleCompletion() {
        withAnimation(.snappy) {
            item.isCompleted.toggle()
        }

        Task { @MainActor in
            try? modelContext.save()
        }
    }
    
    private func performDebouncedSearch(delay: Bool) {
        debounceTask?.cancel()
        let text = item.text

        guard !text.isEmpty else {
            detectedURL = nil
            return
        }

        debounceTask = Task {
            if Task.isCancelled { return }
            
            if delay {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            
            if Task.isCancelled { return }

            let url = await Task.detached(priority: .utility) {
                LinkDetectorHelper.detectURL(in: text)
            }.value

            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        detectedURL = url
                    }
                }
            }
        }
    }
}
