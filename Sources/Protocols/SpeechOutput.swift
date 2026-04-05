@MainActor
protocol SpeechOutput: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String, languageCode: String)
    func stop()
}
