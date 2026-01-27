import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers
import UIKit

struct ShareView: View {
    // --- MODIFICATION 1: Accept an array of attachments ---
    let attachments: [NSItemProvider]
    let onComplete: () -> Void

    @State private var subjects: [Subject] = []
    @State private var selectedSubject: Subject?
    @State private var selectedFolder: Folder?
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // --- ADDED: State for multi-file progress ---
    @State private var saveProgress: String = ""

    private var modelContainer: ModelContainer?

    // --- MODIFICATION 2: Update init to accept the array ---
    init(attachments: [NSItemProvider], onComplete: @escaping () -> Void) {
        self.attachments = attachments
        self.onComplete = onComplete

        do {
            self.modelContainer = try SharedModelContainer.make()
            if let url = (self.modelContainer?.configurations.first?.url) {
                print("[ShareExt] Store URL:", url.path)
            }
        } catch {
            self.modelContainer = nil
            self.errorMessage = "Could not load database. Please open the main app once and ensure App Group entitlements are set for the extension."
            print("[ShareExt] Failed to create ModelContainer:", error)
        }
    }

    var body: some View {
        VStack {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                Button("Close") { onComplete() }
                    .padding(.top, 8)
            } else {
                NavigationView {
                    Form {
                        Section(header: Text("Select Destination")) {
                            if subjects.isEmpty {
                                Text("No subjects found. Open the main app to create a subject first.")
                                    .foregroundColor(.secondary)
                            }
                            Picker("Subject", selection: $selectedSubject) {
                                Text("Select a Subject").tag(nil as Subject?)
                                ForEach(subjects) { subject in
                                    Text(subject.name).tag(subject as Subject?)
                                }
                            }

                            if let subject = selectedSubject {
                                Picker("Folder", selection: $selectedFolder) {
                                    Text("Root of \(subject.name)").tag(nil as Folder?)

                                    ForEach((subject.rootFolders ?? []).sorted(by: { $0.name < $1.name })) { folder in
                                                                
                                        Text(folder.name).tag(folder as Folder?)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Save to College Mate")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: onComplete)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if modelContainer == nil {
                                    errorMessage = "Database unavailable in extension. Check App Group setup."
                                    return
                                }
                                // --- MODIFICATION 3: Call the new multi-save function ---
                                startSavingFiles()
                            }
                            .disabled(selectedSubject == nil || isSaving)
                        }
                    }
                }
            }

            if isSaving {
                // --- ADDED: Show progress for multi-file save ---
                VStack {
                    ProgressView()
                    Text(saveProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }

            if errorMessage == nil && subjects.isEmpty && modelContainer != nil {
                Text("Loading subjects…")
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if modelContainer == nil {
                print("[ShareExt] ModelContainer is nil on appear.")
            } else {
                loadSubjects()
            }
        }
    }

    private func loadSubjects() {
        guard let context = modelContainer?.mainContext else {
            print("[ShareExt] ModelContainer is nil in loadSubjects()")
            errorMessage = "Could not access database in extension. Verify App Group entitlements."
            return
        }
        let descriptor = FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)])
        do {
            subjects = try context.fetch(descriptor)
            print("[ShareExt] Fetched \(subjects.count) subjects")
        } catch {
            errorMessage = "Could not fetch subjects. Open the app once to set up data."
            print("[ShareExt] Failed to fetch subjects:", error)
        }
    }

    // --- MODIFICATION 4: New function to manage multiple saves ---
    private func startSavingFiles() {
        print("[ShareExt] Save tapped for \(attachments.count) items")
        guard let subject = selectedSubject,
              let context = modelContainer?.mainContext else {
            print("[ShareExt] Save aborted: Subject or context is nil.")
            errorMessage = "Cannot save: Subject or database context missing."
            return
        }

        isSaving = true
        errorMessage = nil
        
        let totalFiles = attachments.count
        let filesSaved = 0
        
        DispatchQueue.main.async {
            self.saveProgress = "Saving \(filesSaved) / \(totalFiles)..."
        }

        // We use a DispatchGroup to wait for all async save operations to finish
        let saveGroup = DispatchGroup()
        
        for (index, attachment) in attachments.enumerated() {
            saveGroup.enter() // Enter the group for each attachment
            
            DispatchQueue.main.async {
                self.saveProgress = "Saving \(index + 1) / \(totalFiles)..."
            }
            
            // Pass the group down the chain
            process(
                attachment: attachment,
                subject: subject,
                folder: selectedFolder,
                context: context,
                group: saveGroup
            )
        }
        
        // This block will run only after ALL `saveGroup.leave()` calls are done
        saveGroup.notify(queue: .main) {
            print("[ShareExt] All save operations finished.")
            self.isSaving = false
            if self.errorMessage == nil {
                // Only close if no *critical* error occurred
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.onComplete()
            }
        }
    }

    // --- MODIFICATION 5: Renamed `saveFile` to `process` and added `group` ---
    private func process(attachment: NSItemProvider, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        // --- Path A: Prioritize known NON-IMAGE file types first ---
        let fileTypeToLoad: UTType?
        
        if attachment.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            fileTypeToLoad = UTType.pdf
        } else if let docxType = UTType(filenameExtension: "docx"), attachment.hasItemConformingToTypeIdentifier(docxType.identifier) {
            fileTypeToLoad = docxType
        } else {
            fileTypeToLoad = nil
        }

        if let fileType = fileTypeToLoad {
            print("[ShareExt] Path A: Detected file type: \(fileType.identifier). Loading as file...")
            attachment.loadFileRepresentation(forTypeIdentifier: fileType.identifier) { [self] (url, error) in
                if let url = url {
                    handleFileURL(url, subject: subject, folder: folder, context: context, group: group)
                } else {
                    let fileError = error ?? NSError(domain: "ShareError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load file for type \(fileType.identifier)."])
                    handleSaveError(fileError, group: group)
                }
            }
            return // We are done for this attachment.
        }

        // --- Path B: It's not a known file. Check if it's an image. ---
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            print("[ShareExt] Path B: Detected image. Starting multi-step image load...")
            loadImageData(attachment: attachment, subject: subject, folder: folder, context: context, group: group)
            return
        }
        
        // --- Path C: It's not a known file or an image. ---
        print("[ShareExt] Path C: Not a file or image. Using best data representation fallback...")
        self.loadBestDataRepresentation(
             attachment: attachment,
             preferring: [UTType.data], // Prefer any data
             subject: subject,
             folder: folder,
             context: context,
             group: group
         )
    }
    
    // --- MODIFICATION 6: Pass `group` all the way down the chain ---
    
    private func loadImageData(attachment: NSItemProvider, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        // Step 1: Try to load as a UIImage object. (Best for Photos app)
        if attachment.canLoadObject(ofClass: UIImage.self) {
            attachment.loadObject(ofClass: UIImage.self) { [self] (item, error) in
                if let image = item as? UIImage {
                    print("[ShareExt] ImageLoad Step 1: Success. Loaded UIImage object.")
                    guard let dataToSave = image.jpegData(compressionQuality: 0.85) else {
                        let convertError = NSError(domain: "ShareError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert UIImage to JPEG data."])
                        handleSaveError(convertError, group: group)
                        return
                    }
                    let fileNameToSave = "image_\(UUID().uuidString).jpg"
                    performSave(data: dataToSave, fileName: fileNameToSave, subject: subject, folder: folder, context: context, group: group)
                } else {
                    print("[ShareExt] ImageLoad Step 1: Failed to load UIImage object (Error: \(error?.localizedDescription ?? "Unknown")). Proceeding to Step 2...")
                    self.loadImageAsFile(attachment: attachment, subject: subject, folder: folder, context: context, group: group)
                }
            }
        } else {
            print("[ShareExt] ImageLoad Step 1: Cannot load as UIImage object. Proceeding to Step 2...")
            self.loadImageAsFile(attachment: attachment, subject: subject, folder: folder, context: context, group: group)
        }
    }
    
    private func loadImageAsFile(attachment: NSItemProvider, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        // Step 2: Try to load as a JPEG file. (Best for JPEG files)
        if attachment.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
            print("[ShareExt] ImageLoad Step 2: Trying to load as JPEG file...")
            attachment.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { [self] (url, error) in
                if let url = url {
                    print("[ShareExt] ImageLoad Step 2: Success. Loaded JPEG file URL.")
                    handleFileURL(url, subject: subject, folder: folder, context: context, group: group)
                } else {
                    print("[ShareExt] ImageLoad Step 2: Failed to load JPEG file (Error: \(error?.localizedDescription ?? "Unknown")). Proceeding to Step 3...")
                    self.loadImageAsPngFile(attachment: attachment, subject: subject, folder: folder, context: context, group: group)
                }
            }
        } else {
            print("[ShareExt] ImageLoad Step 2: Not a JPEG. Proceeding to Step 3...")
            self.loadImageAsPngFile(attachment: attachment, subject: subject, folder: folder, context: context, group: group)
        }
    }
    
    private func loadImageAsPngFile(attachment: NSItemProvider, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        // Step 3: Try to load as a PNG file. (Best for PNG files)
        if attachment.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            print("[ShareExt] ImageLoad Step 3: Trying to load as PNG file...")
            attachment.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { [self] (url, error) in
                if let url = url {
                    print("[ShareExt] ImageLoad Step 3: Success. Loaded PNG file URL.")
                    handleFileURL(url, subject: subject, folder: folder, context: context, group: group)
                } else {
                    print("[ShareExt] ImageLoad Step 3: Failed to load PNG file (Error: \(error?.localizedDescription ?? "Unknown")). Proceeding to Step 4...")
                    self.loadBestDataRepresentation(attachment: attachment, preferring: [UTType.image], subject: subject, folder: folder, context: context, group: group)
                }
            }
        } else {
            print("[ShareExt] ImageLoad Step 3: Not a PNG. Proceeding to Step 4...")
            self.loadBestDataRepresentation(attachment: attachment, preferring: [UTType.image], subject: subject, folder: folder, context: context, group: group)
        }
    }

    private func handleFileURL(_ url: URL, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let dataToSave = try Data(contentsOf: url)
            let fileNameToSave = url.lastPathComponent
            print("[ShareExt] handleFileURL: Successfully read \(dataToSave.count) bytes from \(fileNameToSave).")
            performSave(data: dataToSave, fileName: fileNameToSave, subject: subject, folder: folder, context: context, group: group)
        } catch {
            print("[ShareExt] handleFileURL: Error reading data from URL: \(error)")
            handleSaveError(error, group: group)
        }
    }
    
    
    private func performSave(data: Data, fileName: String, subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        // Dispatch all database work to the main thread
        DispatchQueue.main.async {
            
            defer {
                print("[ShareExt] Leaving group for file \(fileName).")
                group.leave()
            }
            
            if data.count < 100, let dataString = String(data: data, encoding: .utf8) {
                let trimmedString = dataString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                print("[ShareExt] ERROR: Detected proxy data. Decoded as string: '\(trimmedString)'. Aborting save for this file.")
                return
            }
            
            print("[ShareExt] Data ready (\(data.count) bytes, name: \(fileName)). Calling FileDataService.saveFile...")

            do {
                let subjectID = subject.persistentModelID
                guard let subjectInContext = context.model(for: subjectID) as? Subject else {
                    throw NSError(domain: "ShareError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Could not find selected subject in context."])
                }

                var folderInContext: Folder? = nil
                if let selectedFolder = folder {
                    let folderID = selectedFolder.persistentModelID
                    folderInContext = context.model(for: folderID) as? Folder
                    if folderInContext == nil {
                        print("[ShareExt] Warning: Could not find selected folder '\(selectedFolder.name)' in context, saving to root.")
                    }
                }
                
                _ = FileDataService.saveFile(
                    data: data,
                    fileName: fileName,
                    to: folderInContext,
                    in: subjectInContext,
                    modelContext: context
                )
                print("[ShareExt] File data prepared, attempting to save context...")

                if context.hasChanges {
                    try context.save()
                    print("[ShareExt] Context saved successfully for \(fileName).")
                } else {
                    print("[ShareExt] No changes detected in context for \(fileName), skipping save.")
                }
                
            } catch {
                print("[ShareExt] performSave: Error during FileDataService.saveFile or context.save for \(fileName): \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadBestDataRepresentation(attachment: NSItemProvider, preferring preferredTypes: [UTType], subject: Subject, folder: Folder?, context: ModelContext, group: DispatchGroup) {
        
        let availableTypes = attachment.registeredTypeIdentifiers.compactMap { UTType($0) }
        print("[ShareExt] loadBestData: Available types: \(availableTypes.map { $0.identifier })")
        
        var typeToLoad: UTType? = nil
        for type in preferredTypes {
            if let specificType = availableTypes.first(where: { $0.conforms(to: type) }) {
                typeToLoad = specificType
                print("[ShareExt] loadBestData: Found match for \(type.identifier), will load \(specificType.identifier)")
                break
            }
        }
        
        guard let finalType = typeToLoad else {
            let noTypeError = NSError(domain: "ShareError", code: 10, userInfo: [NSLocalizedDescriptionKey: "No compatible data representation found."])
            print("[ShareExt] loadBestData: \(noTypeError.localizedDescription)")
            handleSaveError(noTypeError, group: group)
            return
        }

        print("[ShareExt] loadBestData: Trying loadDataRepresentation(forTypeIdentifier: \(finalType.identifier))...")
        attachment.loadDataRepresentation(forTypeIdentifier: finalType.identifier) { [self] (data, error) in
            if let dataToSave = data {
                let fileExtension = finalType.preferredFilenameExtension ?? "data"
                let fileNameToSave = "image_\(UUID().uuidString).\(fileExtension)"
                
                self.performSave(data: dataToSave, fileName: fileNameToSave, subject: subject, folder: folder, context: context, group: group)
            } else {
                let dataError = error ?? NSError(domain: "ShareError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to load data for type \(finalType.identifier)."])
                self.handleSaveError(dataError, group: group)
            }
        }
    }

    private func handleSaveError(_ error: Error, group: DispatchGroup) {
        // Defer leaving the group
        defer {
            print("[ShareExt] Leaving group due to error.")
            group.leave()
        }
        
        print("[ShareExt] Save failed:", error.localizedDescription)
        DispatchQueue.main.async {
            // Set the *first* error that occurs
            if self.errorMessage == nil {
                self.errorMessage = "Failed to save file: \(error.localizedDescription)"
            }
            // We don't trigger haptics here, we'll do one big success/fail at the end
        }
    }
}

