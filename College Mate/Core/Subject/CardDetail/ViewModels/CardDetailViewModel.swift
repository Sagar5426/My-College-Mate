import SwiftUI
import SwiftData
import PDFKit
import QuickLook
import PhotosUI

// MARK: - Thread-Safe Cache Wrapper
final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    
    func object(forKey key: NSString) -> UIImage? {
        cache.object(forKey: key)
    }
    
    func setObject(_ obj: UIImage, forKey key: NSString) {
        cache.setObject(obj, forKey: key)
    }
}

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
    
    nonisolated private let thumbnailCache = ImageCache()
    private let layoutStyleKey: String
    
    let subject: Subject
    let modelContext: ModelContext
    
    // --- View State ---
    @Published var layoutStyle: LayoutStyle = .grid {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: layoutStyleKey)
        }
    }
    @Published var sortType: SortType = .date
    @Published var sortAscending: Bool = false
    
    // Controls sheet visibility
    @Published var isShowingNoteSheet = false
    
    // --- Folder-based State ---
    @Published var currentFolder: Folder? = nil
    @Published var folderPath: [Folder] = []
    @Published var currentFiles: [FileMetadata] = []
    @Published var originalSubfolders: [Folder] = []
    @Published var filteredFileMetadata: [FileMetadata] = []
    @Published var subfolders: [Folder] = []
    
    @Published var isShowingDeleteAlert = false
    @Published var isShowingEditView = false
    @Published var isShowingFileImporter = false
    @Published var isImportingFile = false
    @Published var isShowingPhotoPicker = false
    @Published var isShowingRenameView = false
    
    // --- Single Item Delete State ---
    @Published var itemToDelete: AnyHashable? = nil
    @Published var isShowingSingleDeleteAlert = false {
        didSet {
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
    
    private var searchTask: Task<Void, Never>?
    
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
    
    @Published var documentToPreview: PreviewableDocument? = nil
    @Published var selectedFilter: NoteFilter = .all
    
    @Published var renamingFileMetadata: FileMetadata? = nil {
        didSet {
            if renamingFileMetadata != nil && !isShowingRenameView {
                isShowingRenameView = true
            }
        }
    }
    
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
    
    @Published var isEditing = false
    @Published var selectedFileMetadata: Set<FileMetadata> = []
    @Published var selectedFolders: Set<Folder> = []
    @Published var isShowingMultiDeleteAlert = false
    
    var selectedItemCount: Int {
        selectedFileMetadata.count + selectedFolders.count
    }
    
    var isMoveButtonDisabled: Bool {
        return !selectedFolders.isEmpty || selectedFileMetadata.isEmpty
    }
    
    @Published var urlsToShare: [URL] = []
    @Published var isShowingMultiShareSheet = false
    
    // MARK: - Initializer
    
    init(subject: Subject, modelContext: ModelContext) {
        self.subject = subject
        self.modelContext = modelContext
        self.layoutStyleKey = "CardDetailView_LayoutStyle_\(subject.id.uuidString)"
        
        if let savedLayoutRawValue = UserDefaults.standard.string(forKey: layoutStyleKey),
           let savedLayout = LayoutStyle(rawValue: savedLayoutRawValue) {
            self.layoutStyle = savedLayout
        } else {
            self.layoutStyle = .grid
        }
        
        FileDataService.migrateExistingFiles(for: subject, modelContext: modelContext)
        loadFolderContent()
        
        if subject.rootFolders == nil { subject.rootFolders = [] }
        if subject.fileMetadata == nil { subject.fileMetadata = [] }
        // Initialize topics if nil
        if subject.topics == nil { subject.topics = [] }
    }
    
    // MARK: - Helper Methods
    
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
    
    private func suggestedEditableName(from fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let lower = base.lowercased()
        if lower.hasPrefix("image_") || lower.hasPrefix("image-") {
            let dropCount = lower.hasPrefix("image_") ? 6 : 6
            let uuidPart = String(lower.dropFirst(dropCount))
            let components = uuidPart.split(separator: "-")
            let expected = [8, 4, 4, 4, 12]
            if components.count == expected.count && zip(components, expected).allSatisfy({ $0.count == $1 }) {
                return ""
            }
        }
        return base
    }

    func selectSortOption(_ newSortType: SortType) {
        if sortType == newSortType {
            sortAscending.toggle()
        } else {
            sortType = newSortType
            sortAscending = false
        }
        loadFolderContent()
        performSearch()
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

        self.originalSubfolders = sortFolders(baseSubfolders)
        self.subfolders = self.originalSubfolders
        currentFiles = sortFiles(baseFiles)
        
        filterFileMetadata()
    }
    
    private func sortFolders(_ folders: [Folder]) -> [Folder] {
        return folders.sorted {
            let name1 = $0.name.lowercased()
            let name2 = $1.name.lowercased()
            return sortAscending ? name1 < name2 : name1 > name2
        }
    }
    
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
                filteredFileMetadata = filesToFilter.filter { $0.isFavorite }
                subfolders = foldersToFilter.filter { $0.isFavorite }
            }
        }
    }
    
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
        if folder.subfolders == nil { folder.subfolders = [] }
        if folder.files == nil { folder.files = [] }
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
        loadFolderContent()
    }
    
    func deleteFileMetadata(_ fileMetadata: FileMetadata) {
        guard let fileURL = fileMetadata.getFileURL() else {
            modelContext.delete(fileMetadata)
            try? modelContext.save()
            loadFolderContent()
            return
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Failed to delete physical file: \(error)")
                return
            }
        }
        
        modelContext.delete(fileMetadata)
        try? modelContext.save()
        loadFolderContent()
    }
    
    func renameFileMetadata(_ fileMetadata: FileMetadata, to newName: String) {
        guard let oldURL = fileMetadata.getFileURL() else { return }
        
        let fileExtension = (fileMetadata.fileName as NSString).pathExtension
        let newFileName = "\(newName).\(fileExtension)"
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFileName)
        
        if FileManager.default.fileExists(atPath: oldURL.path) {
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } catch {
                print("Failed to rename physical file: \(error)")
                return
            }
        }

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
    }
    
    // MARK: - Search Methods
    
    func toggleSearchBarVisibility() {
        isSearchBarVisible.toggle()
        if !isSearchBarVisible {
            clearSearch()
        }
    }
    
    func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            let query = searchText.lowercased()
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    searchResults.removeAll()
                    searchFolderResults.removeAll()
                    isSearching = false
                    filterFileMetadata()
                }
                return
            }
            
            let allFiles = self.subject.fileMetadata ?? []
            let rootFolders = self.subject.rootFolders ?? []
            
            struct SearchItem: Sendable {
                let id: PersistentIdentifier
                let name: String
            }
            
            let filesData = allFiles.map { SearchItem(id: $0.persistentModelID, name: $0.fileName) }
            
            var allFoldersData: [SearchItem] = []
            func collect(from folders: [Folder]) {
                for f in folders {
                    allFoldersData.append(SearchItem(id: f.persistentModelID, name: f.name))
                    collect(from: f.subfolders ?? [])
                }
            }
            collect(from: rootFolders)
            
            let (filteredFileIDs, filteredFolderIDs) = await Task.detached(priority: .userInitiated) {
                let fIDs = filesData.filter { $0.name.lowercased().contains(query) }.map { $0.id }
                let fdIDs = allFoldersData.filter { $0.name.lowercased().contains(query) }.map { $0.id }
                return (fIDs, fdIDs)
            }.value
            
            await MainActor.run {
                let filteredFiles = allFiles.filter { filteredFileIDs.contains($0.persistentModelID) }
                
                var allFoldersObjects: [Folder] = []
                func collectObjects(from folders: [Folder]) {
                    for f in folders {
                        allFoldersObjects.append(f)
                        collectObjects(from: f.subfolders ?? [])
                    }
                }
                collectObjects(from: rootFolders)
                let filteredFolders = allFoldersObjects.filter { filteredFolderIDs.contains($0.persistentModelID) }
                
                self.isSearching = true
                self.searchResults = self.sortFiles(filteredFiles)
                self.searchFolderResults = self.sortFolders(filteredFolders)
                self.filterFileMetadata()
            }
        }
    }
    
    func clearSearch() {
        searchText = ""
        searchResults.removeAll()
        searchFolderResults.removeAll()
        isSearching = false
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
            guard let sourceSubject = fileMetadata.subject else { continue }
            
            if let url = fileMetadata.getFileURL(),
               FileManager.default.fileExists(atPath: url.path)
            {
                _ = FileDataService.moveFile(fileMetadata, to: targetFolder, in: sourceSubject)
            } else {
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
        func addFoldersRecursively(from parentFolder: Folder?) {
            let foldersToAdd = (parentFolder?.subfolders ?? subject.rootFolders) ?? []
            for folder in foldersToAdd.sorted(by: { $0.name < $1.name }) {
                folders.append(folder)
            }
        }
        addFoldersRecursively(from: nil)
        availableFolders = folders
    }
    
    // Add @escaping here
        func deleteSubject(onDismiss: @escaping () -> Void) {
            let subjectToDelete = subject
            
            Task {
                // Cancel notifications using the subject object
                await NotificationManager.shared.cancelNotifications(for: subjectToDelete)
                
                // Perform deletion on the main actor after cleanup
                await MainActor.run {
                    FileDataService.deleteSubjectFolder(for: subjectToDelete)
                    modelContext.delete(subjectToDelete)
                    onDismiss()
                }
            }
        }
    
    func renameFile() {
        guard !newFileName.isEmpty else { return }

        if let metadata = renamingFileMetadata {
             renameFileMetadata(metadata, to: newFileName)
        }
        
        renamingFileURL = nil
        renamingFileMetadata = nil
        isShowingRenameView = false
    }
    
    // MARK: - File Import Handlers

    func handleFileImport(result: Result<[URL], Error>) {
        isImportingFile = true
        
        let destinationDir: URL
        if let currentFolder = currentFolder {
            destinationDir = FileDataService.getFolderURL(for: currentFolder, in: subject)
        } else {
            destinationDir = FileDataService.subjectFolder(for: subject)
        }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let sourceURLs = try result.get()
                
                let importedFiles = await withTaskGroup(of: (String, Int64)?.self) { group in
                    for sourceURL in sourceURLs {
                        group.addTask {
                            guard sourceURL.startAccessingSecurityScopedResource() else { return nil }
                            defer { sourceURL.stopAccessingSecurityScopedResource() }
                            
                            do {
                                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                                
                                let fileName = sourceURL.lastPathComponent
                                let destinationURL = destinationDir.appendingPathComponent(fileName)
                                
                                if FileManager.default.fileExists(atPath: destinationURL.path) {
                                    try FileManager.default.removeItem(at: destinationURL)
                                }
                                
                                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                                let size = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                return (fileName, Int64(size))
                            } catch {
                                print("Error importing file: \(error)")
                                return nil
                            }
                        }
                    }
                    
                    var results: [(String, Int64)] = []
                    for await result in group {
                        if let res = result { results.append(res) }
                    }
                    return results
                }
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    for (fileName, fileSize) in importedFiles {
                        let fileExtension = (fileName as NSString).pathExtension
                        let fileType = FileType.from(fileExtension: fileExtension)
                        
                        let relativePath: String
                        if let folder = self.currentFolder {
                            relativePath = "\(folder.fullPath)/\(fileName)"
                        } else {
                            relativePath = fileName
                        }
                        
                        let metadata = FileMetadata(
                            fileName: fileName,
                            fileType: fileType,
                            relativePath: relativePath,
                            fileSize: fileSize,
                            folder: self.currentFolder,
                            subject: self.subject
                        )
                        self.modelContext.insert(metadata)
                    }
                    
                    self.isImportingFile = false
                    self.loadFolderContent()
                }
                
            } catch {
                await MainActor.run { [weak self] in
                    print("Failed to import files: \(error.localizedDescription)")
                    self?.isImportingFile = false
                }
            }
        }
    }
    
    private func handlePhotoPickerSelection() {
        guard !selectedPhotoItems.isEmpty else { return }
        let items = selectedPhotoItems
        self.selectedPhotoItems = []
        self.isImportingFile = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            let readyFiles: [(Data, String)] = await withTaskGroup(of: (Data, String)?.self) { group in
                for item in items {
                    group.addTask {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let fileName = "image_\(UUID().uuidString).jpg"
                            return (data, fileName)
                        }
                        return nil
                    }
                }
                
                var results: [(Data, String)] = []
                for await result in group {
                    if let validResult = result {
                        results.append(validResult)
                    }
                }
                return results
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                for (data, fileName) in readyFiles {
                    _ = FileDataService.saveFile(
                        data: data,
                        fileName: fileName,
                        to: self.currentFolder,
                        in: self.subject,
                        modelContext: self.modelContext
                    )
                }
                
                self.isImportingFile = false
                if self.isEditing { self.toggleEditMode() }
                self.loadFolderContent()
            }
        }
    }
    
    func handleImageSelected(_ image: UIImage?) {
        guard let image = image else { return }
        imageToCrop = image
        isShowingCropper = true
    }
    
    func handleCroppedImage(_ image: UIImage?) {
        guard let image = image else { return }
        
        let destinationDir: URL
        if let currentFolder = currentFolder {
            destinationDir = FileDataService.getFolderURL(for: currentFolder, in: subject)
        } else {
            destinationDir = FileDataService.subjectFolder(for: subject)
        }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
            let fileName = "image_\(UUID().uuidString).jpg"
            let fileURL = destinationDir.appendingPathComponent(fileName)
            
            do {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                try imageData.write(to: fileURL)
            } catch {
                print("Failed to save cropped image: \(error)")
                return
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                let relativePath: String
                if let folder = self.currentFolder {
                    relativePath = "\(folder.fullPath)/\(fileName)"
                } else {
                    relativePath = fileName
                }
                
                let metadata = FileMetadata(
                    fileName: fileName,
                    fileType: .image,
                    relativePath: relativePath,
                    fileSize: Int64(imageData.count),
                    folder: self.currentFolder,
                    subject: self.subject
                )
                self.modelContext.insert(metadata)
                
                if self.isEditing { self.toggleEditMode() }
                self.loadFolderContent()
            }
        }
    }

    // MARK: - Thumbnail Generation
    
    nonisolated func generatePDFThumbnail(from url: URL) async -> UIImage? {
        let cacheKey = url.absoluteString as NSString

        if let cachedImage = thumbnailCache.object(forKey: cacheKey) {
            return cachedImage
        }

        return await Task.detached(priority: .userInitiated) { [thumbnailCache] in
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: 0) else {
                return nil
            }

            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)

            let thumbnail = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                let cgContext = ctx.cgContext
                cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: cgContext)
            }

            thumbnailCache.setObject(thumbnail, forKey: cacheKey)
            return thumbnail
        }.value
    }
    
    func generateDocxThumbnail(from url: URL, scale: CGFloat, completion: @escaping (UIImage?) -> Void) {
        let size = CGSize(width: 80, height: 100)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            guard let generatedImage = representation?.uiImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let renderer = UIGraphicsImageRenderer(size: generatedImage.size)
            let finalImage = renderer.image { ctx in                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: generatedImage.size))
                generatedImage.draw(in: CGRect(origin: .zero, size: generatedImage.size))
            }
            
            DispatchQueue.main.async { completion(finalImage) }
        }
    }
    
    // MARK: - Sharing Methods
    
    func shareSelectedFiles() {
        var urlsToShare = selectedFileMetadata
            .compactMap { $0.getFileURL() }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        
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
        
        guard !urls.isEmpty else { return }
        
        self.urlsToShare = urls
        self.isShowingMultiShareSheet = true
    }
    
    // MARK: - Multi-Select / Editing Methods
    
    var allVisibleItemsSelected: Bool {
        let visibleFileIDs = Set(filteredFileMetadata.map { $0.id })
        let visibleFolderIDs = Set(subfolders.map { $0.id })
        if visibleFileIDs.isEmpty && visibleFolderIDs.isEmpty { return false }
        
        let selectedFileIDs = Set(selectedFileMetadata.map { $0.id })
        let selectedFolderIDs = Set(selectedFolders.map { $0.id })
        
        let filesCovered = selectedFileIDs.isSuperset(of: visibleFileIDs)
        let foldersCovered = selectedFolderIDs.isSuperset(of: visibleFolderIDs)
        return filesCovered && foldersCovered
    }
    
    func toggleSelectAllItems() {
        if allVisibleItemsSelected {
            selectedFileMetadata.subtract(filteredFileMetadata)
            selectedFolders.subtract(subfolders)
        } else {
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
            deleteFileMetadata(metadata)
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
    
    // MARK: - iCloud Download Method
    
    func startDownload(for fileMetadata: FileMetadata) {
        guard let fileURL = fileMetadata.getFileURL() else {
            print("Error: Cannot get file URL to start download.")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if resourceValues.ubiquitousItemDownloadingStatus == .current {
                    self.documentToPreview = PreviewableDocument(url: fileURL)
                    return
                }
            }
        } catch {}
        
        self.fileToDownload = fileMetadata
        self.isDownloading = true
        
        Task(priority: .userInitiated) {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                let success = await pollForFile(at: fileURL)
                
                await MainActor.run {
                    self.isDownloading = false
                    self.fileToDownload = nil
                    if success {
                        if (try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .current {
                            self.documentToPreview = PreviewableDocument(url: fileURL)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.fileToDownload = nil
                }
            }
        }
    }
    
    private func pollForFile(at url: URL, timeout: TimeInterval = 30.0) async -> Bool {
        let startTime = Date()
        var fileIsCurrent = false

        while !fileIsCurrent && Date().timeIntervalSince(startTime) < timeout {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                
                switch resourceValues.ubiquitousItemDownloadingStatus {
                case .current:
                    fileIsCurrent = true
                case .notDownloaded, .downloaded:
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                case nil:
                    break
                default:
                    break
                }
            } catch {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    return false
                }
            }
            
            if !fileIsCurrent {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return fileIsCurrent
    }
}
