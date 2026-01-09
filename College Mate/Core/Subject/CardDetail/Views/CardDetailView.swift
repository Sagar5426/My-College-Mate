import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook

// MARK: - CardDetailView
struct CardDetailView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var viewModel: CardDetailViewModel
    @FocusState private var isSearchFocused: Bool
    
    @State private var isShowingRenameFolderAlert: Bool = false
    @State private var folderBeingRenamed: Folder? = nil
    @State private var newFolderNameForRename: String = ""
    
    // ADDED: Namespace for matched geometry animation
    @Namespace private var animationNamespace
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var tileSize: CGFloat { isPad ? 120 : 80 }
    private var gridSpacing: CGFloat { isPad ? 16 : 12 }
    private var gridColumns: [GridItem] {
        if isPad {
            return [GridItem(.adaptive(minimum: tileSize), spacing: gridSpacing)]
        } else {
            return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
        }
    }
    
    init(subject: Subject, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: CardDetailViewModel(subject: subject, modelContext: modelContext))
    }
    
    // The main body now calls the helper that applies all the modifiers.
    var body: some View {
        viewWithAllModifiers
    }
    
    // Helper computed var for the single delete alert title
    private var singleDeleteAlertTitle: String {
        if let folder = viewModel.itemToDelete as? Folder {
            return "Delete \"\(folder.name)\"?"
        } else if let fileMetadata = viewModel.itemToDelete as? FileMetadata {
            let name = (fileMetadata.fileName as NSString).deletingPathExtension
            return "Delete \"\(name)\"?"
        }
        return "Delete Item?"
    }
    
    // This helper view breaks up the complex expression for the compiler.
    @ViewBuilder
    private var viewWithAllModifiers: some View {
        viewBodyContent
            .alert(viewModel.renamingFileMetadata?.fileType == .image ? "Add Caption" : "Rename File", isPresented: $viewModel.isShowingRenameView) {
                if viewModel.renamingFileMetadata?.fileType == .image {
                    TextField("e.g. Important Formulas", text: $viewModel.newFileName)
                } else {
                    TextField("New Name", text: $viewModel.newFileName)
                }
                Button("Cancel", role: .cancel) {
                    playHaptic(style: .light)
                    viewModel.renamingFileMetadata = nil
                }
                Button("Save") {
                    playHaptic(style: .medium)
                    viewModel.renameFile()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    print("App became active, reloading folder content.")
                    viewModel.loadFolderContent() // Reload when app becomes active
                }
            }
            .navigationTitle(viewModel.subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mainToolbar }
            .alert("Delete this Subject", isPresented: $viewModel.isShowingDeleteAlert) {
                deleteAlertContent
            } message: {
                Text("Deleting this subject will remove all associated data. Are you sure?")
            }
            // ADDED: Alert for deleting a single item
            .alert(singleDeleteAlertTitle, isPresented: $viewModel.isShowingSingleDeleteAlert) {
                Button("Delete", role: .destructive) {
                    playHaptic(style: .heavy)
                    playDeleteSound()
                    viewModel.confirmDeleteItem()
                }
                Button("Cancel", role: .cancel) {
                    playHaptic(style: .light)
                }
            } message: {
                Text("This action cannot be undone.")
            }
             // Use selectedItemCount from ViewModel
            .alert("Delete \(viewModel.selectedItemCount) items?", isPresented: $viewModel.isShowingMultiDeleteAlert) {
                Button("Delete", role: .destructive) {
                    playHaptic(style: .heavy)
                    playDeleteSound()
                    viewModel.deleteSelectedItems()
                }
                Button("Cancel", role: .cancel) {
                    playHaptic(style: .light)
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Create New Folder", isPresented: $viewModel.isShowingCreateFolderAlert) {
                TextField("Folder Name", text: $viewModel.newFolderName)
                Button("Create") {
                    playHaptic(style: .medium)
                    viewModel.createFolder(named: viewModel.newFolderName)
                    viewModel.newFolderName = ""
                }
                Button("Cancel", role: .cancel) {
                    playHaptic(style: .light)
                    viewModel.newFolderName = ""
                }
            } message: {
                Text("Enter a name for the new folder")
            }
            .alert("Rename Folder", isPresented: $isShowingRenameFolderAlert) {
                TextField("Folder Name", text: $newFolderNameForRename)
                Button("Save") {
                    playHaptic(style: .medium)
                    if let folder = folderBeingRenamed {
                        folder.name = newFolderNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                        do {
                            try modelContext.save()
                        } catch {
                            print("Error while renaming the file")
                        }
                    }
                    folderBeingRenamed = nil
                    newFolderNameForRename = ""
                }
                Button("Cancel", role: .cancel) {
                    playHaptic(style: .light)
                    folderBeingRenamed = nil
                    newFolderNameForRename = ""
                }
            }
            .fileImporter(
                isPresented: $viewModel.isShowingFileImporter,
                allowedContentTypes: [
                    UTType.pdf,
                    UTType(filenameExtension: "docx")!
                ],
                allowsMultipleSelection: true,
                onCompletion: viewModel.handleFileImport
            )
            .fullScreenCover(item: $viewModel.documentToPreview) { document in
                PreviewWithShareView(
                    document: document,
                    onDismiss: { viewModel.documentToPreview = nil }
                )
            }
            .sheet(isPresented: $viewModel.isShowingMultiShareSheet) {
                ShareSheetView(activityItems: viewModel.urlsToShare)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingCamera) {
                ImagePicker(sourceType: .camera, onImageSelected: viewModel.handleImageSelected)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingCropper) {
                if let imageToCrop = viewModel.imageToCrop {
                    ImageCropService(image: imageToCrop, onCrop: viewModel.handleCroppedImage, isPresented: $viewModel.isShowingCropper)
                }
            }
            .fullScreenCover(isPresented: $viewModel.isShowingEditView) {
                EditSubjectView(subject: viewModel.subject, isShowingEditSubjectView: $viewModel.isShowingEditView)
            }
            .photosPicker(
                isPresented: $viewModel.isShowingPhotoPicker,
                selection: $viewModel.selectedPhotoItems,
                matching: .images
            )
            .onChange(of: viewModel.selectedFilter) {
                playHaptic(style: .light)
                viewModel.filterFileMetadata()
            }
            .sheet(isPresented: $viewModel.isShowingFolderPicker) {
                FolderPickerView(
                    subjectName: viewModel.subject.name,
                    folders: viewModel.availableFolders,
                    onFolderSelected: { folder in
                        playHaptic(style: .medium)
                        viewModel.moveSelectedFiles(to: folder)
                        viewModel.isShowingFolderPicker = false
                    },
                    onCancel: {
                        playHaptic(style: .light)
                        viewModel.isShowingFolderPicker = false
                    }
                )
            }
            // ADDED: Sheet modifier for the new note view
            .sheet(isPresented: $viewModel.isShowingNoteSheet, onDismiss: {
                viewModel.saveSubjectNote() // Save when sheet is dismissed
            }) {
                SubjectNoteSheetView(noteText: $viewModel.subjectNote)
            }
            .overlay {
                if viewModel.isDownloading {
                    downloadingOverlay
                }
            }
    }
    
    // MARK: - Subviews
    
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        if viewModel.isEditing {
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Cancel") {
                    playHaptic(style: .light)
                    // CHANGED: Use standard animation when exiting edit mode (no spring)
                    withAnimation(.easeInOut(duration: 0.6)) {
                        viewModel.toggleEditMode()
                    }
                }
            }
        } else {
            // Keep the non-editing mode toolbar items
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        playHaptic(style: .light)
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.toggleSearchBarVisibility()
                        }
                        isSearchFocused.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    Menu {
                        Button {
                            playHaptic(style: .light)
                            viewModel.isShowingEditView.toggle()
                        } label: {
                            Label("Edit Subject", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            triggerHapticFeedback() // Keeps existing error haptic
                            viewModel.isShowingDeleteAlert = true
                        } label: {
                            Label("Delete Subject", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .onTapGesture {
                        playHaptic(style: .light)
                    }
                }
            }
        }
    }
    
    private var viewBodyContent: some View {
        VStack(spacing: 0) {
            if viewModel.isSearchBarVisible {
                searchBarView
            }
            filterView
            breadcrumbView
            Divider()
            contentView
        }
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if viewModel.isEditing {
                editingBottomBar
            } else {
                addButton
            }
        }
        // CHANGED: Removed explicit animation modifier from here to allow individual animations for enter/exit
    }
    
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search in \(viewModel.subject.name)...", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .onSubmit { viewModel.performSearch() }
                .onChange(of: viewModel.searchText) { viewModel.performSearch() }
            
            if !viewModel.searchText.isEmpty {
                Button(action: {
                    playHaptic(style: .light)
                    viewModel.clearSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .zIndex(1) // Ensures search bar animates over other content
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var filterView: some View {
            VStack(alignment: .leading, spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    // MARK: - Filter Menu
                    Menu {
                        Picker("Filter", selection: $viewModel.selectedFilter) {
                            ForEach(NoteFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }

                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.body)
                            
                            // FIX APPLIED HERE:
                            // Use a ZStack with a hidden "Favorites" text (the longest option)
                            // to reserve fixed space and prevent layout jitter when selection changes.
                            ZStack(alignment: .leading) {
                                Text(NoteFilter.favorites.rawValue)
                                    .font(.subheadline)
                                    .hidden() // Invisible, strictly for layout sizing
                                
                                Text(viewModel.selectedFilter.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .onTapGesture {
                        playHaptic(style: .light)
                    }
                    
                    Spacer()
                    
                    // Note Button
                    Button {
                        playHaptic(style: .light)
                        viewModel.isShowingNoteSheet = true
                    } label: {
                        Image(systemName: "list.clipboard")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(minWidth: 22, alignment: .center)
                    }
                    
                    // MARK: - Sort & Layout Menu
                    Menu {
                        // Only show Select Items if not already editing
                        if !viewModel.isEditing && (!viewModel.filteredFileMetadata.isEmpty || !viewModel.subfolders.isEmpty) {
                             Button {
                                 playHaptic(style: .light)
                                 withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                     viewModel.toggleEditMode()
                                 }
                             } label: {
                                 Label("Select Items", systemImage: "checkmark.circle")
                             }
                             Divider()
                        }
                        
                        // Sorting Options
                        Button(action: {
                            playHaptic(style: .light)
                            viewModel.selectSortOption(.date)
                        }) {
                              HStack {
                                  Text(CardDetailViewModel.SortType.date.rawValue)
                                  Spacer()
                                  if viewModel.sortType == .date {
                                      Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                                  }
                              }
                        }
                       Button(action: {
                           playHaptic(style: .light)
                           viewModel.selectSortOption(.name)
                       }) {
                           HStack {
                               Text(CardDetailViewModel.SortType.name.rawValue)
                               Spacer()
                               if viewModel.sortType == .name {
                                   Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                               }
                           }
                       }
                       
                        Divider()

                        // Layout Picker
                        Picker("Layout", selection: $viewModel.layoutStyle) {
                            Label("Grid", systemImage: "square.grid.2x2")
                                .font(.body)
                                .tag(CardDetailViewModel.LayoutStyle.grid)
                            Label("List", systemImage: "list.bullet")
                                .font(.body)
                                .tag(CardDetailViewModel.LayoutStyle.list)
                        }
                        .pickerStyle(.inline)
                        .onChange(of: viewModel.layoutStyle) {
                            playHaptic(style: .light)
                        }
                        
                    } label: {
                        Image(systemName: viewModel.layoutStyle.rawValue == "Grid" ? "square.grid.2x2" : "list.bullet")
                            .font(.body)
                            // FIX APPLIED HERE:
                            // Changed minWidth to a fixed width (24) to prevent jitter if icons differ slightly in width.
                            .frame(width: 24, alignment: .center)
                    }
                    .onTapGesture {
                        playHaptic(style: .light)
                    }

                }
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }

    
    private var breadcrumbView: some View {
        Group {
            if !viewModel.folderPath.isEmpty || viewModel.isSearching {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if viewModel.isSearching {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Search Results for \"\(viewModel.searchText)\"")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        } else {
                            Button(action: {
                                playNavigationHaptic()
                                viewModel.navigateToRoot()
                            }) {
                                HStack {
                                    Image(systemName: "house.fill")
                                    Text(viewModel.subject.name)
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.folderPath.isEmpty ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(viewModel.folderPath.isEmpty ? .white : .primary)
                                .clipShape(Capsule())
                            }
                            
                            ForEach(Array(viewModel.folderPath.enumerated()), id: \.element.id) { index, folder in
                                HStack {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    
                                    Button(action: {
                                        playNavigationHaptic()
                                        viewModel.navigateToFolder(at: index)
                                    }) {
                                        Text(folder.name)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(index == viewModel.folderPath.count - 1 ? Color.blue : Color.gray.opacity(0.3))
                                            .foregroundColor(index == viewModel.folderPath.count - 1 ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        ZStack {
            if viewModel.filteredFileMetadata.isEmpty && viewModel.subfolders.isEmpty {
                noNotesView
            } else {
                if viewModel.layoutStyle == .grid {
                    enhancedGrid
                } else {
                    enhancedList
                }
            }
            
            if viewModel.isImportingFile {
                importingOverlay
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
    
    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("Importing...").progressViewStyle(.circular).scaleEffect(1.5)
                .tint(.white)
        }
    }
    
    // --- ADDED: Downloading Overlay ---
    private var downloadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
                
                Text("Downloading file...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let file = viewModel.fileToDownload {
                    Text((file.fileName as NSString).deletingPathExtension)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
    
    private var noNotesView: some View {
        ScrollView {
            VStack {
                // FIXED: Replaced UIScreen.main.bounds.height / 6 with a fixed spacer height
                // to avoid "main was deprecated in iOS 16.0" warning.
                Spacer(minLength: 150)
                
                if viewModel.isSearching {
                    Text("No results found for \"\(viewModel.searchText)\"")
                        .font(.headline)
                        .foregroundColor(.secondary)
                } else {
                    switch viewModel.selectedFilter {
                    case .all:
                        NoNotesView(
                            imageName: "doc.text.magnifyingglass",
                            title: "No Files Added",
                            message: "Click on the add button to start adding files."
                        )
                    case .images:
                        NoNotesView(
                            imageName: "photo.on.rectangle.angled",
                            title: "No Images",
                            message: "Click on the add button to start adding images from your photos or camera."
                        )
                    case .pdfs:
                        NoNotesView(
                            imageName: "doc.richtext",
                            title: "No PDFs",
                            message: "Click on the add button to import PDF documents."
                        )
                    case .docs:
                        NoNotesView(
                            imageName: "doc.text",
                            title: "No Documents",
                            message: "Click on the add button to import Word documents."
                        )
                    case .favorites:
                        NoNotesView(
                            imageName: "heart.slash",
                            title: "No Favorites",
                            message: "You haven't added any files or folders to your favorites yet."
                        )
                    }
                }
                Spacer()
            }
        }
    }
    
    private var enhancedGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(viewModel.subfolders, id: \.id) { folder in
                    folderView(for: folder)
                        .onTapGesture {
                            if viewModel.isEditing {
                                playNavigationHaptic()
                                viewModel.toggleSelectionForFolder(folder)
                            } else {
                                playNavigationHaptic()
                                viewModel.navigateToFolder(folder)
                            }
                        }
                }
                
                ForEach(viewModel.filteredFileMetadata, id: \.id) { fileMetadata in
                    fileMetadataView(for: fileMetadata)
                        .onTapGesture {
                            handleTapForMetadata(fileMetadata)
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical)
            .padding(.horizontal)
            Spacer(minLength: 100)
        }
    }

    private var enhancedList: some View {
        List {
            ForEach(viewModel.subfolders, id: \.id) { folder in
                folderRow(for: folder)
            }
            
            ForEach(viewModel.filteredFileMetadata, id: \.id) { fileMetadata in
                fileRow(for: fileMetadata)
            }
            // Custom spacer to prevent overlap with the bottom bar/button
            Color.clear
                .frame(height: 100)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private func folderRow(for folder: Folder) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(folder.name)
                    .font(.headline)
                Text("\((folder.files ?? []).count) files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // NOTE: Order swapped to make selection indicator appear at trailing edge.
            // When editing, the favorite icon moves to the left of the selection indicator.
            if folder.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
            }

            if viewModel.isEditing {
                listSelectionIcon(isSelected: viewModel.selectedFolders.contains(folder))
                    .padding(.leading, 8) // Ensure separation from heart or content
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isEditing {
                playNavigationHaptic()
                viewModel.toggleSelectionForFolder(folder)
            } else {
                playNavigationHaptic()
                viewModel.navigateToFolder(folder)
            }
        }
        .contextMenu {
            if !viewModel.isEditing {
                folderContextMenu(for: folder)
            }
        }
    }
    
    private func fileRow(for fileMetadata: FileMetadata) -> some View {
        HStack {
            listThumbnail(for: fileMetadata)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading) {
                if fileMetadata.fileType == .image && isPlaceholderImageName(fileMetadata.fileName) {
                    Text("Image")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text((fileMetadata.fileName as NSString).deletingPathExtension)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(fileMetadata.createdDate, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // NOTE: Order swapped to make selection indicator appear at trailing edge.
            // When editing, the favorite icon moves to the left of the selection indicator.
            if fileMetadata.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
            }
            
            if viewModel.isEditing {
                listSelectionIcon(isSelected: viewModel.selectedFileMetadata.contains(fileMetadata))
                    .padding(.leading, 8) // Ensure separation from heart or content
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTapForMetadata(fileMetadata)
        }
        .contextMenu {
            if !viewModel.isEditing {
                fileMetadataContextMenu(for: fileMetadata)
            }
        }
    }

    @ViewBuilder
    private func listThumbnail(for fileMetadata: FileMetadata) -> some View {
        ZStack(alignment: .bottomTrailing) {
            // Updated to use AsyncThumbnailView for list as well, PASSING VIEWMODEL
            AsyncThumbnailView(fileMetadata: fileMetadata, size: 44, viewModel: viewModel)
        }
    }
    
    // Helper function for selection icon in list view
    private func listSelectionIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(isSelected ? Color.blue : Color.gray)
            .background(
                Circle()
                    .fill(Color.white)
                    .padding(1)
            )
            .transition(.opacity)
    }

    private func folderView(for folder: Folder) -> some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: tileSize, height: tileSize * 0.75)
                
                FilesFolderIcon(size: tileSize)
                
                if folder.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(3)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(4)
                }
            }
            // CHANGED: Applied selectionOverlay directly to the icon container for center alignment on thumbnail
            .selectionOverlay(isSelected: viewModel.selectedFolders.contains(folder), isEditing: viewModel.isEditing)
            
            Text(folder.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: tileSize + 20)
            
            Text("\((folder.files ?? []).count) files")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .contextMenu {
            if !viewModel.isEditing {
                folderContextMenu(for: folder)
            }
        }
    }
    
    private func fileMetadataView(for fileMetadata: FileMetadata) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                // REPLACED: Use AsyncThumbnailView for all file types to prevent blocking main thread, PASSING VIEWMODEL
                AsyncThumbnailView(fileMetadata: fileMetadata, size: tileSize, viewModel: viewModel)
                
                // Favorite indicator
                if fileMetadata.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(3)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(4)
                }
            }
            .frame(width: tileSize, height: tileSize)
            // CHANGED: Applied selectionOverlay directly to the thumbnail container for center alignment on thumbnail
            .selectionOverlay(
                isSelected: viewModel.selectedFileMetadata.contains(fileMetadata),
                isEditing: viewModel.isEditing
            )
            
            // Show file name ONLY if it's not an image with a placeholder name.
            if fileMetadata.fileType != .image || !isPlaceholderImageName(fileMetadata.fileName) {
                 Text((fileMetadata.fileName as NSString).deletingPathExtension)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            // Show formatted date for all files
            Text(fileMetadata.createdDate.formattedAsString(format: "dd/MM/yy"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contextMenu {
            if !viewModel.isEditing {
                fileMetadataContextMenu(for: fileMetadata)
            }
        }
    }
    
    // --- Tap Handler ---
    private func handleTapForMetadata(_ fileMetadata: FileMetadata) {
        if viewModel.isEditing {
            playNavigationHaptic()
            viewModel.toggleSelectionForMetadata(fileMetadata)
            return
        }
        
        // File is not local, start download
        if let fileURL = fileMetadata.getFileURL(),
           !FileManager.default.fileExists(atPath: fileURL.path) {
            playNavigationHaptic()
            viewModel.startDownload(for: fileMetadata)
        } else if let fileURL = fileMetadata.getFileURL() {
            // File is local, open it
            playNavigationHaptic()
            viewModel.documentToPreview = PreviewableDocument(url: fileURL)
        }
    }
    
    @ViewBuilder
    private func folderContextMenu(for folder: Folder) -> some View {
        Button {
            playHaptic(style: .light)
            viewModel.shareFolder(folder)
        } label: {
            Label("Share Folder", systemImage: "square.and.arrow.up")
        }
        
        Button {
            playHaptic(style: .light)
            viewModel.toggleFavorite(for: folder)
        } label: {
            Label(folder.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: folder.isFavorite ? "heart.slash" : "heart")
        }

        Button {
            playHaptic(style: .light)
            folderBeingRenamed = folder
            newFolderNameForRename = folder.name
            isShowingRenameFolderAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        
        Button(role: .destructive) {
            playHaptic(style: .light)
            viewModel.promptForDelete(item: folder)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private func fileMetadataContextMenu(for fileMetadata: FileMetadata) -> some View {
        
        Button {
            playHaptic(style: .light)
            viewModel.toggleFavorite(for: fileMetadata)
        } label: {
            Label(fileMetadata.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: fileMetadata.isFavorite ? "heart.slash" : "heart")
        }
        
        Button {
            playHaptic(style: .light)
            viewModel.beginRenaming(with: fileMetadata)
        } label: {
            if fileMetadata.fileType == .image {
                Label("Add Caption", systemImage: "pencil")
            } else {
                Label("Rename", systemImage: "pencil")
            }
        }
        
        // ADDED: Delete button for files
        Button(role: .destructive) {
            playHaptic(style: .light)
            viewModel.promptForDelete(item: fileMetadata)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private var addButton: some View {
        Menu {
            // Only allow creating folders at the root level for now
            if viewModel.currentFolder == nil {
                 Button("New Folder", systemImage: "folder.badge.plus") {
                     playHaptic(style: .light)
                     viewModel.isShowingCreateFolderAlert = true
                 }
            }
            Button("Camera", systemImage: "camera.fill") {
                playHaptic(style: .light)
                viewModel.isShowingCamera = true
            }
            Button("Images from Photos", systemImage: "photo.on.rectangle.angled") {
                playHaptic(style: .light)
                viewModel.isShowingPhotoPicker = true
            }
            Button("Document from Files", systemImage: "doc.fill") {
                playHaptic(style: .light)
                viewModel.isShowingFileImporter = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 60, height: 60)
                .background(
                    ZStack {
                        // Base frosted glass
                        Circle().fill(.ultraThinMaterial)
                        
                        // Subtle tint to give the glass a hue
                        Circle().fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.blue.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        
                        // Inner highlight (specular)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1.2
                            )
                            .blur(radius: 0.5)
                            .blendMode(.plusLighter)
                        
                        // Inner shadow ring to add depth
                        Circle()
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            .blur(radius: 1.2)
                            .opacity(0.6)
                    }
                    // CHANGED: ADDED matchedGeometryEffect for transformation
                    .matchedGeometryEffect(id: "background", in: animationNamespace)
                )
                .overlay(
                    // Glass rim
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                .shadow(color: Color.blue.opacity(0.18), radius: 16, x: 0, y: 6)
                .contentShape(Circle())
                .padding(14)
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isEditing)
                .accessibilityLabel("Add")
                .onTapGesture {
                    playHaptic(style: .medium)
                }
        }
        .padding()
        // CHANGED: REMOVED .transition(.scale.combined(with: .opacity))
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
    }
    
    // MARK: - Bottom Bar (with option of select all, delete , share and move)
    private var editingBottomBar: some View {
        HStack(alignment: .center) { // Align items vertically center
            // Select All / Deselect All
            Button(viewModel.allVisibleItemsSelected ? "Deselect All" : "Select All") {
                playNavigationHaptic()
                viewModel.toggleSelectAllItems()
            }
            .font(.subheadline.weight(.medium))
            .padding(.leading)
            .disabled(viewModel.filteredFileMetadata.isEmpty && viewModel.subfolders.isEmpty)
            .foregroundColor((viewModel.filteredFileMetadata.isEmpty && viewModel.subfolders.isEmpty) ? .gray : .blue)

            Spacer()

            // Share Button
            Button {
                playNavigationHaptic()
                viewModel.shareSelectedFiles()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(viewModel.selectedItemCount == 0)

            Spacer()

            // Move Button
            Button {
                playNavigationHaptic()
                viewModel.showFolderPickerForSelection()
            } label: {
                Image(systemName: "folder")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(viewModel.isMoveButtonDisabled)

            Spacer()

            // Delete Button
            Button {
                playNavigationHaptic()
                viewModel.isShowingMultiDeleteAlert = true
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(viewModel.selectedItemCount > 0 ? .red : .gray)
                    
                    // Show count only if > 0, make it smaller
                    if viewModel.selectedItemCount > 0 {
                        Text("\(viewModel.selectedItemCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.top, 1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 44, height: 44) // Make touch target larger
            }
            .padding(.trailing)
            .disabled(viewModel.selectedItemCount == 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        // CHANGED: Refactored background to use matchedGeometryEffect and Removed transition
        .background(
            Capsule()
                .fill(.thinMaterial)
                .matchedGeometryEffect(id: "background", in: animationNamespace)
        )
        // .clipShape(Capsule()) // Removed as background is already a capsule shape
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedItemCount)
    }
    
    private var deleteAlertContent: some View {
        Button("Delete", role: .destructive) {
            playDeleteSound()
            // Updated to handle escaping closure with Task.detached or similar is not needed
            // because deleteSubject handles the async work internally but accepts a closure.
            viewModel.deleteSubject {
                dismiss()
            }
        }
    }
    
    // MARK: - Feedback Helpers
    
    private func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
    
    private func playDeleteSound() {
        SoundService.shared.playDeleteSound()
    }

    private func playTapSoundAndVibrate() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        AudioServicesPlaySystemSound(1306)
    }
    
    private func playNavigationHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // Helper function for haptics
    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// ADDED: New view for the note sheet
// MARK: - Subject Note Sheet
struct SubjectNoteSheetView: View {
    @Binding var noteText: String
    @Environment(\.dismiss) private var dismiss
    
    private let placeholder = "Write important topics for exam or paste Drive Links"
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                // TextEditor
                TextEditor(text: $noteText)
                    .padding(4)
                    .frame(minHeight: 200, maxHeight: .infinity)
                
                // Placeholder
                if noteText.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color(UIColor.placeholderText))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .padding()
            .navigationTitle("Important Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        playHaptic(style: .medium)
                        dismiss()
                    }
                }
            }
        }
    }
    
    // Helper function for haptics
    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - PreviewWithShareView
struct PreviewWithShareView: View {
    let document: PreviewableDocument
    let onDismiss: () -> Void
    
    @State private var isShowingShareSheet = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                DocumentPreviewView(url: document.url)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button(action: {
                                playHaptic(style: .light)
                                isShowingShareSheet = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.white)
                            }
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Spacer()
                        }
                    }

                Button(action: {
                    playHaptic(style: .light)
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .bold()
                        .padding(12)
                        .background {
                            Circle()
                                .glassEffect()
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        // This modifier prevents the sheet from being dismissed by swiping down
        .interactiveDismissDisabled()
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheetView(activityItems: [document.url])
        }
    }
    
    // Helper function for haptics
    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}


// MARK: - DocxThumbnailView
struct DocxThumbnailView: View {
    let fileURL: URL
    @ObservedObject var viewModel: CardDetailViewModel
    let size: CGFloat
    @Environment(\.displayScale) var displayScale
    
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                    .frame(width: size, height: size)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            viewModel.generateDocxThumbnail(from: fileURL, scale: displayScale) { image in
                self.thumbnail = image
            }
        }
    }
}

// MARK: - Files-style Folder Icon
struct FilesFolderIcon: View {
    var size: CGFloat

    var body: some View {
        // Size the icon slightly smaller than the tile
        let iconSize = size * 0.62
        ZStack {
            // Base filled folder with a blue gradient, similar to Files app
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.74, green: 0.86, blue: 1.0), // light blue top
                            Color(red: 0.20, green: 0.56, blue: 1.0)  // deeper blue bottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)

            // Subtle top highlight to give a modern glossy feel
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.8)
        }
        .accessibilityHidden(true)
    }
}


// MARK: - SelectionOverlay
struct SelectionOverlay: ViewModifier {
    let isSelected: Bool
    let isEditing: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isSelected ? Color.blue : Color.gray)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .padding(1)
                        )
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

extension View {
    func selectionOverlay(isSelected: Bool, isEditing: Bool) -> some View {
        self.modifier(SelectionOverlay(isSelected: isSelected, isEditing: isEditing))
    }
}

// MARK: - DocumentPreviewView & ShareSheet
struct DocumentPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: DocumentPreviewView

        init(parent: DocumentPreviewView) {
            self.parent = parent
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as QLPreviewItem
        }
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


// MARK: - ImagePicker
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImageSelected: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageSelected(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImageSelected(nil)
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - FolderPickerView
struct FolderPickerView: View {
    let subjectName: String
    let folders: [Folder]
    let onFolderSelected: (Folder?) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    playHaptic(style: .light)
                    onFolderSelected(nil) // `nil` represents the root
                }) {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.blue)
                        Text(subjectName) // Show Subject name for root
                        Spacer()
                    }
                }
                
                ForEach(folders, id: \.id) { folder in
                    Button(action: {
                        playHaptic(style: .light)
                        onFolderSelected(folder)
                    }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(folder.name)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        playHaptic(style: .light)
                        onCancel()
                    }
                }
            }
        }
    }
    
    // Helper function for haptics
    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}


// MARK: - Helper function for placeholder image names

private func isPlaceholderImageName(_ fileName: String) -> Bool {
    let lower = fileName.lowercased()
    let base = (lower as NSString).deletingPathExtension

    // 1) Explicit default name
    if base == "default" { return true }

    // 2) App-generated pattern: image_<uuid>-like (strict regex)
    // Accepts common UUID-ish segments (8+ hex/dash characters)
    if base.range(of: #"^image_[0-9a-f-]{8,}$"#, options: [.regularExpression]) != nil {
        return true
    }

    // 3) Classic camera names only when the whole string matches a known pattern
    //    Examples: IMG_1234, IMG-20231009, img12345
    if base.range(of: #"^(?i:img)[_-]?\d{3,}$"#, options: [.regularExpression]) != nil {
        return true
    }

    return false
}
