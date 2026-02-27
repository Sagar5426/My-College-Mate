import Foundation
import Vision
import PDFKit
import UIKit
import ZIPFoundation

struct TextExtractor {
    
    /// Extracts text from a file asynchronously based on its type
    static func extractText(from url: URL, type: FileType) async -> String? {
        switch type {
        case .pdf:
            return PDFDocument(url: url)?.string
        case .image:
            return await extractTextFromImage(url: url)
        case .docx:
            return extractTextFromDocx(url: url)
        case .unknown:
            return nil
        }
    }
    
    /// Uses the Vision framework to perform OCR on an image
    private static func extractTextFromImage(url: URL) async -> String? {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                continuation.resume(returning: recognizedText)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Unzips the DOCX file, reads the internal document.xml, and strips the XML tags to get raw text
    private static func extractTextFromDocx(url: URL) -> String? {
        let fileManager = FileManager.default
        // Create a unique temporary directory to unzip the contents
        let tempDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            
            // Unzip the .docx file using ZIPFoundation
            try fileManager.unzipItem(at: url, to: tempDirectoryURL)
            
            // The actual text of a Word Document is always stored in this specific XML file
            let documentXMLURL = tempDirectoryURL.appendingPathComponent("word/document.xml")
            
            guard fileManager.fileExists(atPath: documentXMLURL.path) else {
                try? fileManager.removeItem(at: tempDirectoryURL) // Cleanup
                return nil
            }
            
            // Read the raw XML string
            let xmlString = try String(contentsOf: documentXMLURL, encoding: .utf8)
            
            // Use Regular Expressions to strip out all XML tags (e.g., <w:t>, </w:t>, <w:p>)
            // This replaces anything inside < > with a space
            let rawText = xmlString.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
            
            // Clean up extra spaces that the regex might have left behind
            let cleanedText = rawText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Delete the temporary unzipped folder to save space
            try? fileManager.removeItem(at: tempDirectoryURL)
            
            return cleanedText.isEmpty ? nil : cleanedText
            
        } catch {
            print("Failed to extract DOCX text: \(error)")
            // Ensure cleanup happens even if an error is thrown midway
            try? fileManager.removeItem(at: tempDirectoryURL)
            return nil
        }
    }
}
