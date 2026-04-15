// BundledHelpersTests — every GUI app must ship with all its dependencies.
//
// apfel-chat shells out to auge (image analysis), ohr (voice input), and
// apfel (on-device LLM). The .app bundle MUST embed all three in
// Contents/Helpers so users don't need to install anything separately.
// Anything less is broken UX.

import Foundation
import Testing

@Suite("BundledHelpers")
struct BundledHelpersTests {
    private static let buildScript: String = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // Tests/
        url.deleteLastPathComponent() // repo root
        url.appendPathComponent("scripts/build-app.sh")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    @Test("build-app.sh embeds apfel, auge, and ohr helpers",
          arguments: ["apfel", "auge", "ohr"])
    func eachHelperEmbedded(name: String) {
        #expect(
            Self.buildScript.contains("\"$APP_BUNDLE/Contents/Helpers/\(name)\"")
            || Self.buildScript.contains("\"$APP_BUNDLE/Contents/Helpers/${helper}\""),
            "build-app.sh must copy \(name) into Contents/Helpers so users don't need a separate brew install"
        )
    }

    @Test("build-app.sh fails the build when any helper is missing")
    func missingHelperFailsBuild() {
        #expect(
            Self.buildScript.contains("MISSING_HELPERS")
            && Self.buildScript.contains("exit 1"),
            "build-app.sh must abort when a required helper is missing — never ship an incomplete bundle"
        )
    }

    @Test("build-app.sh signs each embedded helper")
    func eachHelperSigned() {
        #expect(
            Self.buildScript.contains("for helper in apfel auge ohr"),
            "sign_bundle must sign every helper (apfel, auge, ohr) before signing the outer bundle"
        )
    }
}
