import SwiftUI
import SwiftData
import PDFKit
import QuickLook // Import for thumbnail generation
import PhotosUI

// The @MainActor attribute ensures that all UI updates happen on the main thread.
@MainActor
class CardDetailViewModel: ObservableObject {
    
    // MARK: - Enums
    enum SortType: String {
        case date = "Date Added"
        case name = "Alphabetical"
    }

    enum LayoutStyle: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    // MARK: - Properties
    
    private let layoutStyleKey: String
    
    func beginRenaming(with metadata: FileMetadata) {
        guard let url = metadata.getFileURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            if metadata.fileType == .image {
                self.renamingFileMetadata = metadata
                self.newFileName = self.suggestedEditableName(from: metadata.fileName)
                self.isShowingRenameView = true
            } else {
                print("Error: Cannot rename file that is not downloaded.")
                return
            }
            return
        }
        
        self.renamingFileMetadata = metadata
        self.newFileName = self.suggestedEditableName(from: metadata.fileName)
        self.isShowingRenameView = true
    }
    
    // Returns an empty string for auto-generated image names like "image_<UUID>", otherwise returns the base name without extension.
    private func suggestedEditableName(from fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let lower = base.lowercased()
        // Accept both image_ and image- prefixes
        if lower.hasPrefix("image_") || lower.hasPrefix("image-") {
            let dropCount = lower.hasPrefix("image_") ? 6 : 6 // length of "image_" or "image-"
            let uuidPart = String(lower.dropFirst(dropCount))
            let components = uuidPart.split(separator: "-")
            let expected = [8, 4, 4, 4, 12]
            if components.count == expected.count && zip(components, expected).allSatisfy({ $0.count == $1 }) {
                return ""
            }
        }
        return base
    }
    
    let subject: Subject
    private let modelContext: ModelContext
    
    // --- View State ---
    @Published var layoutStyle: LayoutStyle = .grid {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: layoutStyleKey)
        }
    }
    @Published var sortType: SortType = .date
    @Published var sortAscending: Bool = false // false for newest first/A-Z
    
    // ADDED: State for the note sheet
    @Published var isShowingNoteSheet = false
    @Published var subjectNote: String = ""
    
    // --- Folder-based State ---
    @Published var currentFolder: Folder? = nil
    @Published var folderPath: [Folder] = [] // Breadcrumb navigation
    @Published var currentFiles: [FileMetadata] = []
    @Published var originalSubfolders: [Folder] = [] // Store the unfiltered subfolders
    @Published var filteredFileMetadata: [FileMetadata] = []
    @Published var subfolders: [Folder] = []
    
    @Published var isShowingDeleteAlert = false
    @Published var isShowingEditView = false
    @Published var isShowingFileImporter = false
    @Published var isImportingFile = false
    @Published var isShowingPhotoPicker = false
    // Dedicated flag for rename/caption UI
    @Published var isShowingRenameView = false
    
    // --- Single Item Delete State ---
    @Published var itemToDelete: AnyHashable? = nil
    @Published var isShowingSingleDeleteAlert = false {
        didSet {
            // When the alert is dismissed (either by confirm or cancel),
            // reset the itemToDelete.
            if !isShowingSingleDeleteAlert {
                itemToDelete = nil
            }
        }
    }
    
    // --- Search State ---
    @Published var isSearchBarVisible = false
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var searchResults: [FileMetadata] = []
    @Published var searchFolderResults: [Folder] = []
    
    // --- Folder Management State ---
    @Published var isShowingCreateFolderAlert = false
    @Published var newFolderName: String = ""
    @Published var isShowingFolderPicker = false
    @Published var availableFolders: [Folder] = []
    
    // --- Camera and Cropping State ---
    @Published var isShowingCamera = false
    @Published var isShowingCropper = false
    @Published var imageToCrop: UIImage?
    
    // --- Photos Picker State ---
    @Published var selectedPhotoItems: [PhotosPickerItem] = [] {
        didSet {
            handlePhotoPickerSelection()
        }
    }
    
    // --- Universal Preview State ---
    @Published var documentToPreview: PreviewableDocument? = nil
    
    @Published var selectedFilter: NoteFilter = .all
    
    // --- Renaming State ---
    @Published var renamingFileMetadata: FileMetadata? = nil {
        didSet {
            if renamingFileMetadata != nil {
                // This logic is now handled by beginRenaming()
                // We keep the isShowingRenameView = true
                // in case it's set programmatically
                if !isShowingRenameView {
                    isShowingRenameView = true
                }
            }
        }
    }
    
    // --- ADDED: iCloud Download State ---
    @Published var isDownloading: Bool = false
    @Published var fileToDownload: FileMetadata? = nil
    
    @Published var renamingFileURL: URL? = nil {
        didSet {
            guard renamingFileMetadata == nil else { return }
            if let url = renamingFileURL {
                let base = url.deletingPathExtension().lastPathComponent
                newFileName = suggestedEditableName(from: base)
                isShowingRenameView = true
            }
        }
    }
    @Published var newFileName: String = ""
    
    // --- Selection State for Multi-Select ---
    @Published var isEditing = false
    @Published var selectedFileMetadata: Set<FileMetadata> = []
    @Published var selectedFolders: Set<Folder> = []
    @Published var isShowingMultiDeleteAlert = false
    
    // ADDED: Computed property to get total selected item count
    var selectedItemCount: Int {
        selectedFileMetadata.count + selectedFolders.count
    }
    
    // Computed property to disable the move button
    var isMoveButtonDisabled: Bool {
        // Disable if any folder is selected OR if no files are selected.
        return !selectedFolders.isEmpty || selectedFileMetadata.isEmpty
    }
    
    // --- Multi-Sharing State ---
    @Published var urlsToShare: [URL] = []
    @Published var isShowingMultiShareSheet = false
    
    
    // MARK: - Initializer
    
    init(subject: Subject, modelContext: ModelContext) {
        self.subject = subject
        self.modelContext = modelContext
        self.layoutStyleKey = "CardDetailView_LayoutStyle_\(subject.id.uuidString)"
        
        // Load saved layout style
        if let savedLayoutRawValue = UserDefaults.standard.string(forKey: layoutStyleKey),
           let savedLayout = LayoutStyle(rawValue: savedLayoutRawValue) {
            self.layoutStyle = savedLayout
        } else {
            self.layoutStyle = .grid // Default
        }
        
        FileDataService.migrateExistingFiles(for: subject, modelContext: modelContext)
        loadFolderContent()
        
        // ADDED: Load the saved note
        self.subjectNote = subject.ImportantTopicsNote
        
        // Ensure optional arrays are initialized
        if subject.rootFolders == nil {
            subject.rootFolders = []
        }
        if subject.fileMetadata == nil {
            subject.fileMetadata = []
        }
    }
    
    // MARK: - Sorting Method
    func selectSortOption(_ newSortType: SortType) {
        if sortType == newSortType {
            sortAscending.toggle()
        } else {
            sortType = newSortType
            sortAscending = false // Default to descending for date, ascending for name
        }
        loadFolderContent()
        performSearch() // Re-apply search with new sort
    }

    // ADDED: Function to save the note
    // MARK: - Subject Note
    
    func saveSubjectNote() {
        subject.ImportantTopicsNote = subjectNote
        do {
            try modelContext.save()
        } catch {
            print("Failed to save subject note: \(error)")
        }
    }

    // MARK: - Folder-based Methods
    
    func loadFolderContent() {
        let baseSubfolders: [Folder]
        let baseFiles: [FileMetadata]

        if let currentFolder = currentFolder {
            baseSubfolders = currentFolder.subfolders ?? []
            baseFiles = currentFolder.files ?? []
        } else {
            baseSubfolders = subject.rootFolders ?? []
            baseFiles = (subject.fileMetadata ?? []).filter { $0.folder == nil }
        }

        // Apply sorting and store original list of folders
        self.originalSubfolders = sortFolders(baseSubfolders)
        self.subfolders = self.originalSubfolders
        currentFiles = sortFiles(baseFiles)
        
        filterFileMetadata()
    }
    
    // Helper to sort folders
    private func sortFolders(_ folders: [Folder]) -> [Folder] {
        return folders.sorted {
            let name1 = $0.name.lowercased()
            let name2 = $1.name.lowercased()
            return sortAscending ? name1 < name2 : name1 > name2
        }
    }
    
    // Helper to sort files
    private func sortFiles(_ files: [FileMetadata]) -> [FileMetadata] {
        return files.sorted {
            switch sortType {
            case .date:
                let date1 = $0.createdDate
                let date2 = $1.createdDate
                return sortAscending ? date1 < date2 : date1 > date2
            case .name:
                let name1 = $0.fileName.lowercased()
                let name2 = $1.fileName.lowercased()
                return sortAscending ? name1 < name2 : name1 > name2
            }
        }
    }
    
    func filterFileMetadata() {
        let showSearchAtRoot = isSearching && currentFolder == nil
        let filesToFilter = showSearchAtRoot ? searchResults : currentFiles
        
        // Always start with the original, unfiltered list of folders
        let foldersToFilter: [Folder] = showSearchAtRoot ? searchFolderResults : self.originalSubfolders

        switch selectedFilter {
        case .all:
            filteredFileMetadata = filesToFilter
            subfolders = foldersToFilter
        case .images:
            filteredFileMetadata = filesToFilter.filter { $0.fileType == .image }
            subfolders = showSearchAtRoot ? [] : foldersToFilter.filter { folder in
                !(folder.files ?? []).filter { $0.fileType == .image }.isEmpty
            }
        case .pdfs:
            filteredFileMetadata = filesToFilter.filter { $0.fileType == .pdf }
            subfolders = showSearchAtRoot ? [] : foldersToFilter.filter { folder in
                !(folder.files ?? []).filter { $0.fileType == .pdf }.isEmpty
            }
        case .docs:
            filteredFileMetadata = filesToFilter.filter { $0.fileType == .docx }
            subfolders = showSearchAtRoot ? [] : foldersToFilter.filter { folder in
                !(folder.files ?? []).filter { $0.fileType == .docx }.isEmpty
            }
        case .favorites:
            if currentFolder == nil && !isSearching {
                filteredFileMetadata = sortFiles((subject.fileMetadata ?? []).filter { $0.isFavorite })
                let allFolders = allFoldersRecursively(from: (subject.rootFolders ?? []))
                subfolders = sortFolders(allFolders.filter { $0.isFavorite })
            } else {
                // When in a folder, just filter the current content
                filteredFileMetadata = filesToFilter.filter { $0.isFavorite }
                subfolders = foldersToFilter.filter { $0.isFavorite }
            }
        }
    }
    
    // Recursively collect all folders starting from a list of folders
    private func allFoldersRecursively(from folders: [Folder]) -> [Folder] {
        var result: [Folder] = []
        for folder in folders {
            result.append(folder)
            let subfolders = folder.subfolders ?? []
            if !subfolders.isEmpty {
                result.append(contentsOf: allFoldersRecursively(from: subfolders))
            }
        }
        return result
    }
    
    // MARK: - Navigation Methods
    
    func navigateToFolder(_ folder: Folder) {
        if folder.subfolders == nil {
            folder.subfolders = []
        }
        if folder.files == nil {
            folder.files = []
        }
        folderPath.append(folder)
        currentFolder = folder
        loadFolderContent()
    }
    
    func navigateToRoot() {
        folderPath.removeAll()
        currentFolder = nil
        loadFolderContent()
    }
    
    func navigateToFolder(at index: Int) {
        guard index < folderPath.count else { return }
        folderPath = Array(folderPath.prefix(index + 1))
        currentFolder = folderPath.last
        loadFolderContent()
    }
    
    // MARK: - Folder Management
    
    func createFolder(named name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let folder = Folder(name: name, parentFolder: currentFolder, subject: subject)
        folder.files = []
        folder.subfolders = []
        
        modelContext.insert(folder)
        _ = FileDataService.createFolder(named: name, in: currentFolder, for: subject)
        
        try? modelContext.save()
        loadFolderContent()
    }
    
    func deleteFolder(_ folder: Folder) {
        _ = FileDataService.deleteFolder(folder, in: subject)
        modelContext.delete(folder)
        try? modelContext.save()
        loadFolderContent()
    }

    func toggleFavorite(for folder: Folder) {
        folder.isFavorite.toggle()
        try? modelContext.save()
        loadFolderContent()
    }
    
    // MARK: - File Management
    
    func toggleFavorite(for fileMetadata: FileMetadata) {
        fileMetadata.isFavorite.toggle()
        try? modelContext.save()
        loadFolderContent() // Refresh to show favorite status change
    }
    
    // --- UPDATED: Delete function ---
    func deleteFileMetadata(_ fileMetadata: FileMetadata) {
        guard let fileURL = fileMetadata.getFileURL() else {
            // Failsafe: if we can't get a URL, just delete the metadata
            modelContext.delete(fileMetadata)
            try? modelContext.save()
            loadFolderContent()
            return
        }

        // Check if the file exists locally
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Failed to delete physical file: \(error)")
                return
            }
        } else {
            print("File not found locally. Deleting metadata for: \(fileMetadata.fileName)")
        }
        
        // Delete the metadata object from SwiftData
        modelContext.delete(fileMetadata)
        try? modelContext.save()
        loadFolderContent()
    }
    
    // --- UPDATED: Rename function ---
    func renameFileMetadata(_ fileMetadata: FileMetadata, to newName: String) {
        guard let oldURL = fileMetadata.getFileURL() else { return }
        
        let fileExtension = (fileMetadata.fileName as NSString).pathExtension
        let newFileName = "\(newName).\(fileExtension)"
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFileName)
        
        // Check if the file exists locally
        if FileManager.default.fileExists(atPath: oldURL.path) {
            // File exists, rename it
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } catch {
                print("Failed to rename physical file: \(error)")
                return
            }
        } else {
            print("File not found locally. Updating metadata name for: \(fileMetadata.fileName)")
        }

        // Update metadata
        fileMetadata.fileName = newFileName
        let folderPath = fileMetadata.folder?.fullPath ?? ""
        fileMetadata.relativePath = folderPath.isEmpty ? newFileName : "\(folderPath)/\(newFileName)"
        
        try? modelContext.save()
        loadFolderContent()
    }
    
    // MARK: - Single Item Delete Methods
    
    func promptForDelete(item: AnyHashable) {
        itemToDelete = item
        isShowingSingleDeleteAlert = true
    }

    func confirmDeleteItem() {
        if let folder = itemToDelete as? Folder {
            deleteFolder(folder)
        } else if let fileMetadata = itemToDelete as? FileMetadata {
            deleteFileMetadata(fileMetadata)
        }
        // itemToDelete is reset by the isShowingSingleDeleteAlert.didSet
    }
    
    // MARK: - Search Methods
    
    func toggleSearchBarVisibility() {
        isSearchBarVisible.toggle()
        if !isSearchBarVisible {
            clearSearch()
        }
    }
    
    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults.removeAll()
            searchFolderResults.removeAll()
            isSearching = false
            filterFileMetadata()
            return
        }
        
        isSearching = true
        let query = searchText.lowercased()
        
        let filesToSearch = self.subject.fileMetadata ?? []
        let results = filesToSearch.filter { $0.fileName.lowercased().contains(query) }
        searchResults = sortFiles(results)

        let allFolders = allFoldersRecursively(from: subject.rootFolders ?? [])
        searchFolderResults = sortFolders(allFolders.filter { $0.name.lowercased().contains(query) })
        
        filterFileMetadata()
    }
    
    func clearSearch() {
        searchText = ""
        searchResults.removeAll()
        searchFolderResults.removeAll()
        isSearching = false
        // When clearing search, restore the view to its non-searching state
        loadFolderContent()
    }
    
    // MARK: - Folder Picker & Move Methods
    
    func showFolderPicker(for fileMetadata: FileMetadata) {
        selectedFileMetadata.removeAll()
        selectedFileMetadata.insert(fileMetadata)
        showFolderPickerForSelection()
    }

    func showFolderPickerForSelection() {
        loadAvailableFolders()
        isShowingFolderPicker = true
    }

    func moveSelectedFiles(to targetFolder: Folder?) {
        for fileMetadata in selectedFileMetadata {
            // We need to know the source subject to move correctly
            guard let sourceSubject = fileMetadata.subject else { continue }
            
            if let url = fileMetadata.getFileURL(),
               FileManager.default.fileExists(atPath: url.path)
            {
                _ = FileDataService.moveFile(fileMetadata, to: targetFolder, in: sourceSubject)
            } else {
                // File doesn't exist, just update its metadata parent
                fileMetadata.folder = targetFolder
                let folderPath = targetFolder?.fullPath ?? ""
                fileMetadata.relativePath = folderPath.isEmpty ? fileMetadata.fileName : "\(folderPath)/\(fileMetadata.fileName)"
            }
        }
        
        Task {
            try? modelContext.save()
            await MainActor.run {
                selectedFileMetadata.removeAll()
                isEditing = false
                loadFolderContent()
            }
        }
    }
    
    private func loadAvailableFolders() {
        var folders: [Folder] = []
        // This recursive function fetches all subfolders
        func addFoldersRecursively(from parentFolder: Folder?) {
            let foldersToAdd = (parentFolder?.subfolders ?? subject.rootFolders) ?? []
            for folder in foldersToAdd.sorted(by: { $0.name < $1.name }) {
                folders.append(folder)
            }
        }
        addFoldersRecursively(from: nil)
        availableFolders = folders
    }
    
    func deleteSubject(onDismiss: () -> Void) {
        let subjectID = subject.id.uuidString
        Task {
            await NotificationManager.shared.cancelNotifications(for: subjectID)
        }
        FileDataService.deleteSubjectFolder(for: subject)
        modelContext.delete(subject)
        onDismiss()
    }
    
    func renameFile() {
        guard !newFileName.isEmpty else { return }

        if let metadata = renamingFileMetadata {
             renameFileMetadata(metadata, to: newFileName)
        }
        
        // Reset the renaming state
        renamingFileURL = nil
        renamingFileMetadata = nil
        isShowingRenameView = false
    }
    
    // MARK: - File Import Handlers

    func handleFileImport(result: Result<[URL], Error>) {
        isImportingFile = true
        Task {
            defer { Task { @MainActor in isImportingFile = false } }
            do {
                let sourceURLs = try result.get()
                for sourceURL in sourceURLs {
                    _ = sourceURL.startAccessingSecurityScopedResource()
                    let data = try await Task.detached {
                        defer { sourceURL.stopAccessingSecurityScopedResource() }
                        return try Data(contentsOf: sourceURL)
                    }.value
                    _ = FileDataService.saveFile(data: data, fileName: sourceURL.lastPathComponent, to: self.currentFolder, in: self.subject, modelContext: self.modelContext)
                }
                loadFolderContent()
            } catch {
                print("Failed to import files: \(error.localizedDescription)")
            }
        }
    }
    
    private func handlePhotoPickerSelection() {
        guard !selectedPhotoItems.isEmpty else { return }
        isImportingFile = true
        let items = selectedPhotoItems
        self.selectedPhotoItems = [] // Clear selection immediately
        
        Task {
            defer { Task { @MainActor in
                isImportingFile = false
                if self.isEditing { self.toggleEditMode() } // Exit edit mode after adding
                self.loadFolderContent()
            }}
            
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let fileName = "image_\(UUID().uuidString).jpg"
                    _ = FileDataService.saveFile(
                        data: data,
                        fileName: fileName,
                        to: self.currentFolder,
                        in: self.subject,
                        modelContext: self.modelContext
                    )
                }
            }
        }
    }
    
    // MARK: - Single Image Handlers (Camera)
    
    func handleImageSelected(_ image: UIImage?) {
        guard let image = image else { return }
        imageToCrop = image
        isShowingCropper = true
    }
    
    func handleCroppedImage(_ image: UIImage?) {
        guard let image = image, let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        let fileName = "image_\(UUID().uuidString).jpg"
        
        if let _ = FileDataService.saveFile(data: imageData, fileName: fileName, to: currentFolder, in: subject, modelContext: modelContext) {
            if self.isEditing { self.toggleEditMode() }
            loadFolderContent()
        }
    }

    // MARK: - Thumbnail Generation
    
    func generatePDFThumbnail(from url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            let cgContext = ctx.cgContext
            cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: cgContext)
        }
    }
    
    func generateDocxThumbnail(from url: URL, scale: CGFloat, completion: @escaping (UIImage?) -> Void) {
        let size = CGSize(width: 80, height: 100)
        // Use the passed scale instead of UIScreen.main.scale
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            guard let generatedImage = representation?.uiImage else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let renderer = UIGraphicsImageRenderer(size: generatedImage.size)
            let finalImage = renderer.image { ctx in                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: generatedImage.size))
                generatedImage.draw(in: CGRect(origin: .zero, size: generatedImage.size))
            }
            
            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
    
    // MARK: - Sharing Methods
    
    func shareSelectedFiles() {
        var urlsToShare = selectedFileMetadata
            .compactMap { $0.getFileURL() }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        
        // Add files from selected folders
        for folder in selectedFolders {
            func recursivelyCollectFiles(from folder: Folder) {
                let files = (folder.files ?? [])
                    .compactMap { $0.getFileURL() }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                
                urlsToShare.append(contentsOf: files)
                
                for subfolder in (folder.subfolders ?? []) {
                    recursivelyCollectFiles(from: subfolder)
                }
            }
            recursivelyCollectFiles(from: folder)
        }
        
        guard !urlsToShare.isEmpty else { return }
        
        self.urlsToShare = urlsToShare
        self.isShowingMultiShareSheet = true
    }
    
    func shareFolder(_ folder: Folder) {
        var urls: [URL] = []
        
        func recursivelyCollectFiles(from folder: Folder) {
            let files = (folder.files ?? [])
                .compactMap { $0.getFileURL() }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            
            urls.append(contentsOf: files)
            
            for subfolder in (folder.subfolders ?? []) {
                recursivelyCollectFiles(from: subfolder)
            }
        }
        
        recursivelyCollectFiles(from: folder)
        
        guard !urls.isEmpty else {
            // Optionally show an alert that the folder is empty
            return
        }
        
        self.urlsToShare = urls
        self.isShowingMultiShareSheet = true
    }
    
    // MARK: - Multi-Select / Editing Methods
    
    // Computed property to check if all *visible* items (files and folders) are selected
    var allVisibleItemsSelected: Bool {
        // Build sets of visible IDs
        let visibleFileIDs = Set(filteredFileMetadata.map { $0.id })
        let visibleFolderIDs = Set(subfolders.map { $0.id })
        // If there are no visible items at all, return false
        if visibleFileIDs.isEmpty && visibleFolderIDs.isEmpty { return false }
        // Selected sets
        let selectedFileIDs = Set(selectedFileMetadata.map { $0.id })
        let selectedFolderIDs = Set(selectedFolders.map { $0.id })
        // Check both are fully covered
        let filesCovered = selectedFileIDs.isSuperset(of: visibleFileIDs)
        let foldersCovered = selectedFolderIDs.isSuperset(of: visibleFolderIDs)
        return filesCovered && foldersCovered
    }
    
    func toggleSelectAllItems() {
        if allVisibleItemsSelected {
            // Deselect all visible
            selectedFileMetadata.subtract(filteredFileMetadata)
            selectedFolders.subtract(subfolders)
        } else {
            // Select all visible
            selectedFileMetadata.formUnion(filteredFileMetadata)
            selectedFolders.formUnion(subfolders)
        }
    }
    
    func toggleEditMode() {
        isEditing.toggle()
        if !isEditing {
            selectedFileMetadata.removeAll()
            selectedFolders.removeAll()
        }
    }

    func deleteSelectedItems() {
        let metadataToDelete = selectedFileMetadata
        for metadata in metadataToDelete {
            deleteFileMetadata(metadata) // Use the updated delete function
        }
        
        let foldersToDelete = selectedFolders
        for folder in foldersToDelete {
            deleteFolder(folder)
        }
        
        DispatchQueue.main.async {
            self.selectedFileMetadata.removeAll()
            self.selectedFolders.removeAll()
            self.isEditing = false
            self.loadFolderContent()
        }
    }
    
    func toggleSelectionForMetadata(_ metadata: FileMetadata) {
        if selectedFileMetadata.contains(metadata) {
            selectedFileMetadata.remove(metadata)
        } else {
            selectedFileMetadata.insert(metadata)
        }
    }
    
    func toggleSelectionForFolder(_ folder: Folder) {
        if selectedFolders.contains(folder) {
            selectedFolders.remove(folder)
        } else {
            selectedFolders.insert(folder)
        }
    }
    
    // MARK: - iCloud Download Method (REWRITTEN)
    
    func startDownload(for fileMetadata: FileMetadata) {
        guard let fileURL = fileMetadata.getFileURL() else {
            print("Error: Cannot get file URL to start download.")
            return
        }
        
        // --- NEW PRE-FLIGHT CHECK ---
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if resourceValues.ubiquitousItemDownloadingStatus == .current {
                    print("File already exists and is .current, opening.")
                    self.documentToPreview = PreviewableDocument(url: fileURL)
                    return
                }
            }
        } catch {
             print("Pre-flight check failed: \(error.localizedDescription). Proceeding with download attempt.")
        }
        // --- END NEW CHECK ---
        
        // File doesn't exist or is not .current, start download
        self.fileToDownload = fileMetadata
        self.isDownloading = true
        
        Task(priority: .userInitiated) {
            do {
                // This is the call that tells iCloud Drive to start downloading
                try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                
                // Now we poll...
                let success = await pollForFile(at: fileURL)
                
                // Once done, update UI on the main thread
                await MainActor.run {
                    self.isDownloading = false
                    self.fileToDownload = nil
                    if success {
                        print("Download complete, opening file.")
                        // Re-check status one last time to be sure
                        if (try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .current {
                            self.documentToPreview = PreviewableDocument(url: fileURL)
                        } else {
                            print("Error: Polling succeeded but file is not .current on final check.")
                        }
                    } else {
                        print("Error: File download timed out.")
                        // Optionally: show an error to the user
                    }
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.fileToDownload = nil
                    print("Error starting download: \(error.localizedDescription)")
                    // Optionally: show an error to the user
                }
            }
        }
    }
    
    // --- POLLING FUNCTION (REWRITTEN) ---
    private func pollForFile(at url: URL, timeout: TimeInterval = 30.0) async -> Bool {
        let startTime = Date()
        var fileIsCurrent = false

        while !fileIsCurrent && Date().timeIntervalSince(startTime) < timeout {
            do {
                // Try to get the resource values for the file
                let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                
                switch resourceValues.ubiquitousItemDownloadingStatus {
                case .current:
                    print("Polling: File is .current")
                    fileIsCurrent = true // Success! Exit loop.
                
                case .notDownloaded, .downloaded:
                    print("Polling: File is .notDownloaded or .downloaded. Requesting download again.")
                    // File is not local. Request the download (again).
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                case nil:
                    // status is nil, which means it's in the process of downloading.
                    print("Polling: File is actively downloading (status is nil), continuing to wait...")
                    // Do nothing, just let the loop continue and sleep
                
                default:
                    print("Polling: Unknown download status.")
                    // Unknown status, let's wait.
                }
            } catch {
                // This error (e.g., "file not found") can happen if the placeholder isn't even synced.
                // We should request the download to create the placeholder.
                print("Polling: Error getting resource values (\(error.localizedDescription)). Requesting download.")
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    print("Polling: Failed to re-request download. Aborting poll.")
                    return false // Abort
                }
            }
            
            // If not yet current, sleep before next check
            if !fileIsCurrent {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second
            }
        }
        
        return fileIsCurrent
    }
}
