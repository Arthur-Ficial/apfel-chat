import Foundation

final class AugeService: @unchecked Sendable {
    let augePath: String

    init?(augePath: String? = nil) {
        if let path = augePath {
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            self.augePath = path
        } else if let found = Self.findAugeBinary() {
            self.augePath = found
        } else {
            return nil
        }
    }

    static func findAugeBinary() -> String? {
        if let resolved = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map({ "\($0)/auge" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return resolved
        }
        let fallbacks = ["/usr/local/bin/auge", "/opt/homebrew/bin/auge"]
        return fallbacks.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    struct AnalysisResult: Sendable {
        var ocrText: String?
        var classifications: [(label: String, confidence: Double)]
        var barcodes: [String]
        var faceCount: Int
        var filename: String

        var summary: String {
            var parts: [String] = ["[Image Analysis: \(filename)]"]

            if let text = ocrText, !text.isEmpty {
                let truncated = text.count > 2000
                    ? String(text.prefix(2000)) + "... (truncated)"
                    : text
                parts.append("Text found (OCR): \(truncated)")
            } else {
                parts.append("Text found (OCR): none")
            }

            if !classifications.isEmpty {
                let top5 = classifications.prefix(5).map {
                    "\($0.label) (\(Int($0.confidence * 100))%)"
                }
                parts.append("Classification: \(top5.joined(separator: ", "))")
            } else {
                parts.append("Classification: none")
            }

            if !barcodes.isEmpty {
                parts.append("Barcodes: \(barcodes.joined(separator: ", "))")
            }

            if faceCount > 0 {
                parts.append("Faces: \(faceCount) detected")
            }

            return parts.joined(separator: "\n")
        }

        /// Estimated token count (rough: 1 token per 4 chars)
        var estimatedTokens: Int {
            summary.count / 4
        }
    }

    /// Run all analyses on an image file in parallel.
    func analyze(imagePath: String) async -> AnalysisResult {
        let filename = URL(fileURLWithPath: imagePath).lastPathComponent

        async let ocr = runAuge(args: ["--ocr", imagePath, "-o", "json"])
        async let classify = runAuge(args: ["--classify", imagePath, "-o", "json"])
        async let barcode = runAuge(args: ["--barcode", imagePath, "-o", "json"])
        async let faces = runAuge(args: ["--faces", imagePath, "-o", "json"])

        let ocrOutput = await ocr
        let classifyOutput = await classify
        let barcodeOutput = await barcode
        let facesOutput = await faces

        // Parse OCR
        var ocrText: String?
        if let data = ocrOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String { ocrText = text }
            else if let results = json["results"] as? [[String: Any]] {
                ocrText = results.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
        }

        // Parse classifications
        var classifications: [(String, Double)] = []
        if let data = classifyOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            classifications = results.compactMap { item -> (String, Double)? in
                guard let label = item["label"] as? String ?? item["identifier"] as? String,
                      let confidence = item["confidence"] as? Double else { return nil }
                return (label, confidence)
            }
        }

        // Parse barcodes
        var barcodes: [String] = []
        if let data = barcodeOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            barcodes = results.compactMap { $0["payload"] as? String ?? $0["value"] as? String }
        }

        // Parse faces
        var faceCount = 0
        if let data = facesOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let count = json["count"] as? Int { faceCount = count }
            else if let results = json["results"] as? [Any] { faceCount = results.count }
        }

        return AnalysisResult(
            ocrText: ocrText,
            classifications: classifications,
            barcodes: barcodes,
            faceCount: faceCount,
            filename: filename
        )
    }

    private func runAuge(args: [String]) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: augePath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
