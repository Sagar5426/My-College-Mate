import SwiftUI
import PDFKit
import ImageIO

struct AsyncThumbnailView: View {
    let fileMetadata: FileMetadata
    let size: CGFloat
    
    // 1. ADD: Pass the ViewModel so we can access the cached generator
    @ObservedObject var viewModel: CardDetailViewModel
    
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage? = nil
    @State private var isLoading = true
    @State private var isDownloaded = false
    
    var body: some View {
        ZStack {
            // Background / Placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: size, height: size)
            
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.animation(.default))
            } else if !isDownloaded {
                // Cloud icon for non-downloaded files
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                // Fallback icon based on type if loading fails or isn't applicable
                fallbackIcon
            }
        }
        // Use .task instead of .onAppear + Task.detached to properly manage concurrency
        .task {
            await loadThumbnail()
        }
    }
    
    @ViewBuilder
    private var fallbackIcon: some View {
        switch fileMetadata.fileType {
        case .image:
            Image(systemName: "photo")
                .font(.title2)
                .foregroundColor(.green)
        case .pdf:
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundColor(.red)
        case .docx:
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundColor(.blue)
        default:
            Image(systemName: "doc")
                .font(.title2)
                .foregroundColor(.gray)
        }
    }
    
    @MainActor
    private func loadThumbnail() async {
        // 1. Extract data on Main Actor (safe access to fileMetadata)
        guard let fileURL = fileMetadata.getFileURL() else {
            isLoading = false
            return
        }
        
        // 2. Check existence on Main Thread
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            isLoading = false
            isDownloaded = false
            return
        }
        
        isDownloaded = true
        
        // 3. UPDATED LOGIC: Use ViewModel for PDFs to leverage Caching
        if fileMetadata.fileType == .pdf {
            // Use the cached function in ViewModel
            let image = await viewModel.generatePDFThumbnail(from: fileURL)
            self.thumbnail = image
            self.isLoading = false
        } else {
            // Existing logic for Images (Downsampling)
            let currentScale = displayScale
            let targetSize = CGSize(width: size * 2, height: size * 2)
            let fileType = fileMetadata.fileType // Extract value type (Enum)
            
            // 4. Offload heavy lifting to background, passing only safe value types
            let generatedImage = await Task.detached(priority: .userInitiated) {
                return AsyncThumbnailView.generateImage(url: fileURL, type: fileType, targetSize: targetSize, scale: currentScale)
            }.value
            
            // 5. Update UI on Main Actor
            if let img = generatedImage {
                self.thumbnail = img
            }
            self.isLoading = false
        }
    }
    
    // Static helper explicitly marked nonisolated to allow background execution
    nonisolated private static func generateImage(url: URL, type: FileType, targetSize: CGSize, scale: CGFloat) -> UIImage? {
        switch type {
        case .image:
            return downsample(imageAt: url, to: targetSize, scale: scale)
        // PDF case is now handled by ViewModel via caching, but kept here for fallback/reference
        case .pdf:
            return generatePDFPage(url: url)
        default:
            return nil
        }
    }
    
    // Efficient Image Downsampling (Static, Non-isolated)
    nonisolated private static func downsample(imageAt imageURL: URL, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else { return nil }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: downsampledImage)
    }
    
    // PDF Generation (Static, Non-isolated)
    nonisolated private static func generatePDFPage(url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
