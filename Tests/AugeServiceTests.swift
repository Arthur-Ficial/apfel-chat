import Testing
import Foundation
@testable import apfel_chat

@Suite("AugeService")
struct AugeServiceTests {

    @Test("findAugeBinary returns path when auge exists")
    func findAuge() {
        let path = AugeService.findAugeBinary()
        #expect(path != nil)
    }

    @Test("Init succeeds when auge is on PATH")
    func initFromPath() {
        let service = AugeService()
        #expect(service != nil)
    }

    @Test("Init with explicit path succeeds for valid binary")
    func initExplicitPath() {
        guard let found = AugeService.findAugeBinary() else { return }
        let service = AugeService(augePath: found)
        #expect(service != nil)
    }

    @Test("Init with bogus path fails")
    func initBogusPath() {
        let service = AugeService(augePath: "/nonexistent/auge")
        #expect(service == nil)
    }

    @Test("Analysis result summary formats correctly")
    func summaryFormat() {
        let result = AugeService.AnalysisResult(
            ocrText: "Hello World",
            classifications: [("document", 0.95), ("text", 0.87)],
            barcodes: [],
            faceCount: 0,
            filename: "test.png"
        )
        let summary = result.summary
        #expect(summary.contains("[Image Analysis: test.png]"))
        #expect(summary.contains("Hello World"))
        #expect(summary.contains("document (95%)"))
        #expect(summary.contains("text (87%)"))
    }

    @Test("Summary shows none for empty OCR")
    func summaryEmptyOCR() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [],
            barcodes: [],
            faceCount: 0,
            filename: "empty.png"
        )
        #expect(result.summary.contains("Text found (OCR): none"))
        #expect(result.summary.contains("Classification: none"))
    }

    @Test("Summary shows barcodes when present")
    func summaryBarcodes() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [],
            barcodes: ["https://example.com", "ABC123"],
            faceCount: 0,
            filename: "qr.png"
        )
        #expect(result.summary.contains("Barcodes: https://example.com, ABC123"))
    }

    @Test("Summary shows face count when present")
    func summaryFaces() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [],
            barcodes: [],
            faceCount: 3,
            filename: "photo.jpg"
        )
        #expect(result.summary.contains("Faces: 3 detected"))
    }

    @Test("Summary does not show faces line when zero")
    func summaryNoFaces() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [],
            barcodes: [],
            faceCount: 0,
            filename: "landscape.jpg"
        )
        #expect(!result.summary.contains("Faces:"))
    }

    @Test("Summary does not show barcodes line when empty")
    func summaryNoBarcodes() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [],
            barcodes: [],
            faceCount: 0,
            filename: "test.png"
        )
        #expect(!result.summary.contains("Barcodes:"))
    }

    @Test("Summary truncates long OCR text")
    func summaryTruncation() {
        let longText = String(repeating: "a", count: 3000)
        let result = AugeService.AnalysisResult(
            ocrText: longText,
            classifications: [],
            barcodes: [],
            faceCount: 0,
            filename: "big.png"
        )
        #expect(result.summary.count < 3000)
        #expect(result.summary.contains("truncated"))
    }

    @Test("Summary limits classifications to top 5")
    func summaryTopClassifications() {
        let result = AugeService.AnalysisResult(
            ocrText: nil,
            classifications: [
                ("a", 0.99), ("b", 0.98), ("c", 0.97),
                ("d", 0.96), ("e", 0.95), ("f", 0.94), ("g", 0.93)
            ],
            barcodes: [],
            faceCount: 0,
            filename: "test.png"
        )
        let summary = result.summary
        #expect(summary.contains("a (99%)"))
        #expect(summary.contains("e (95%)"))
        #expect(!summary.contains("f (94%)"))
        #expect(!summary.contains("g (93%)"))
    }

    @Test("Estimated tokens calculated")
    func estimatedTokens() {
        let result = AugeService.AnalysisResult(
            ocrText: "Short text",
            classifications: [],
            barcodes: [],
            faceCount: 0,
            filename: "test.png"
        )
        #expect(result.estimatedTokens > 0)
    }

    @Test("Analysis runs on real image")
    func analyzeRealImage() async throws {
        guard let auge = AugeService() else {
            // auge not installed, skip
            return
        }
        // Create a simple test image using sips to convert a blank
        let testPath = "/tmp/apfel-chat-test-image.png"

        // Create a 100x100 white PNG via CoreGraphics-backed sips
        let createProc = Process()
        createProc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        createProc.arguments = ["-x", "-R", "0,0,100,100", testPath]
        try createProc.run()
        createProc.waitUntilExit()

        guard FileManager.default.fileExists(atPath: testPath) else {
            return // screencapture may fail in CI
        }

        let result = await auge.analyze(imagePath: testPath)
        #expect(result.filename == "apfel-chat-test-image.png")
        // Should at least parse without crashing and return valid structure
        #expect(result.faceCount >= 0)

        try? FileManager.default.removeItem(atPath: testPath)
    }
}
