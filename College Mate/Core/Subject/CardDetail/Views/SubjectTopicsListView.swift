import SwiftUI
import SwiftData

struct SubjectTopicsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var subject: Subject
    
    // MARK: - State
    @State private var isShowingAddAlert = false
    @State private var newItemText = ""
    
    // Editing State
    @State private var isShowingEditAlert = false
    @State private var editingItem: TopicItem?
    @State private var editItemText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let topics = subject.topics, !topics.isEmpty {
                    // MARK: - List View
                    List {
                        ForEach(topics.sorted(by: { $0.createdAt < $1.createdAt })) { item in
                            HStack(alignment: .top, spacing: 12) {
                                // Checkbox
                                Button(action: {
                                    toggleCompletion(for: item)
                                }) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? .green : .gray)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                                
                                // Text or Link
                                VStack(alignment: .leading) {
                                    if let url = detectURL(in: item.text), !item.isCompleted {
                                        Link(item.text, destination: url)
                                            .font(.body)
                                            .foregroundStyle(.blue)
                                            .multilineTextAlignment(.leading)
                                            .underline()
                                    } else {
                                        Text(item.text)
                                            .font(.body)
                                            .strikethrough(item.isCompleted)
                                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Context Menu for Edit/Delete/Copy
                                .contentShape(Rectangle()) // Ensures the empty space next to text is tappable for context menu
                                .contextMenu {
                                    Button {
                                        startEditing(item)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        UIPasteboard.general.string = item.text
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    
                                    Button(role: .destructive) {
                                        deleteItem(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteItems)
                    }
                } else {
                    // MARK: - Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 60))
                            .foregroundStyle(.gray.opacity(0.5))
                        
                        Text("No Topics Added")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("You can add drive links or important topics for exam.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            isShowingAddAlert = true
                        }) {
                            Text("Add First Topic")
                                .fontWeight(.medium)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Important Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isShowingAddAlert = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // Add Item Alert
            .alert("Add Topic", isPresented: $isShowingAddAlert) {
                TextField("Enter topic or paste link", text: $newItemText)
                Button("Add") {
                    addNewItem()
                }
                Button("Cancel", role: .cancel) {
                    newItemText = ""
                }
            }
            // Edit Item Alert
            .alert("Edit Topic", isPresented: $isShowingEditAlert) {
                TextField("Edit text", text: $editItemText)
                Button("Save") {
                    saveEditedItem()
                }
                Button("Cancel", role: .cancel) {
                    editingItem = nil
                    editItemText = ""
                }
            }
        }
    }
    
    // MARK: - Logic
    
    private func addNewItem() {
        guard !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let newItem = TopicItem(text: newItemText)
        subject.topics?.append(newItem)
        newItemText = ""
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func startEditing(_ item: TopicItem) {
        editingItem = item
        editItemText = item.text
        isShowingEditAlert = true
    }
    
    private func saveEditedItem() {
        guard let item = editingItem else { return }
        if !editItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.text = editItemText
            // Trigger UI update if needed, though SwiftData usually handles it
            try? modelContext.save()
        }
        editingItem = nil
        editItemText = ""
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func toggleCompletion(for item: TopicItem) {
        withAnimation(.snappy) {
            item.isCompleted.toggle()
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func deleteItem(_ item: TopicItem) {
        if let index = subject.topics?.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                subject.topics?.remove(at: index)
                modelContext.delete(item)
            }
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        guard let topics = subject.topics else { return }
        let sortedTopics = topics.sorted(by: { $0.createdAt < $1.createdAt })
        
        withAnimation {
            for index in offsets {
                let itemToDelete = sortedTopics[index]
                if let originalIndex = subject.topics?.firstIndex(of: itemToDelete) {
                    subject.topics?.remove(at: originalIndex)
                    modelContext.delete(itemToDelete)
                }
            }
        }
    }
    
    /// Helper to detect if the string is a valid URL to make it clickable
    private func detectURL(in text: String) -> URL? {
        // Basic check to see if it looks like a web URL
        // We require http or https to be safe, or just a valid URL structure
        if let url = URL(string: text),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()) {
            return url
        }
        return nil
    }
}
