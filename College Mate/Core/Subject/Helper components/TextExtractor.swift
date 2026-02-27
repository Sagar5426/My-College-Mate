//
//  TextExtractor.swift
//  My College Mate
//
//  Created by Sagar Jangra on 27/02/2026.
//


import Foundation
import Vision
import PDFKit
import UIKit

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
    
    /// Uses NSAttributedString to read Word Documents
    /// iOS does not natively support DOCX text extraction without a 3rd-party unzipping library.
        /// Returning nil falls back to searching by filename only.
        private static func extractTextFromDocx(url: URL) -> String? {
            print("DOCX deep-search is currently unsupported natively on iOS.")
            return nil
        }
}
