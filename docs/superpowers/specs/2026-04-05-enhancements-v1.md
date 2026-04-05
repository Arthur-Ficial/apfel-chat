# apfel-chat v1.0.0 Enhancements Spec

**Date:** 2026-04-05
**Status:** Approved (user delegated all decisions)

## 1. Context Window Awareness

**Problem:** Users can't tell which messages are inside/outside the AI's context window.

**Solution:**
- On startup and periodically, fetch `/health` to get `context_window` (token count)
- Track cumulative token count from newest message backward
- Messages that exceed the context window get grayed out (opacity 0.4)
- Add a subtle divider line with "Context window limit" label between in/out messages
- Store context window size in ChatViewModel

**Implementation:**
- Add `contextWindow: Int?` to ChatViewModel (fetched from health endpoint)
- Add computed property `contextCutoffIndex` — walks messages from end, summing tokens until exceeding window
- MessageBubble gets `isOutOfContext: Bool` parameter → applies `.opacity(0.4)`
- ChatView shows divider at cutoff point

## 2. ohr/auge Integration

**Problem:** Built-in SFSpeechRecognizer works but ohr has better language support (30 langs) and auge enables vision.

**Solution:**
- Check if `ohr` binary exists in PATH (same pattern as finding `apfel`)
- If ohr exists, use it as STT backend instead of SFSpeechRecognizer
- ohr command: `ohr --mic --language en-US` (pipes transcription to stdout)
- auge: v2 feature, skip for now (no clear chat use case yet)
- Settings: show which STT backend is active

**Implementation:**
- Add `OhrSpeechInput` class conforming to `SpeechInput` protocol
- Uses `Process` to run `ohr --mic --language <lang>` and read stdout
- ServerManager gains `findOhrBinary() -> String?`
- ApfelChatApp: prefer OhrSpeechInput when ohr is available, fall back to OnDeviceSpeechInput
- Test: MockSpeechInput already covers the protocol

## 3. Design Polish

**Remaining issues from user feedback:**
- Messages outside context window grayed out (covered in #1)
- Input area should feel like a central element
- Professional alignment everywhere
- Proper app icon placeholder

## 4. First Release v1.0.0

**What:** Run the release script to create DMG + GitHub release + Homebrew formula.
- The release script already exists at `scripts/release.sh`
- Creates `.app` bundle, DMG, tarball, GitHub release, Homebrew formula
- Test the release process end-to-end
