# apfel-chat - Project Instructions

## The Golden Goal

apfel-chat is the consumer-grade native macOS chat app for on-device AI - a private, fast, no-API-keys ChatGPT alternative that runs entirely on your Mac via apfel. The one job is a polished, lightweight everyday chat client: multi-conversation history, streaming markdown, speech in and out, and Apple Vision image reading, with nothing ever leaving the machine. It IS a finished end-user product (signed, notarised, App-Store-shaped SwiftUI). It is NOT the apfel CLI/server (that is the engine it spawns), NOT the apfel-gui debug tool, and NOT a cloud client - no network inference, no API keys, no telemetry, ever. Every feature is scored against "does this make the local chat experience faster, more private, or more pleasant"; anything else is scope creep.

## Purpose

Super-fast, lightweight, 100% local chat client for on-device AI via apfel.
Multi-chat, speech I/O, markdown rendering. ChatGPT competitor — fully private.
Sister project to apfel-gui (debug tool). This is the consumer chat client.

## Language Rules

NEVER use the word "Apple" in user-visible strings. Use instead:
- "on-device" / "your Mac" / "Foundation Models on your Mac"
- "private AI" / "local AI"

## Install & Run

```bash
brew tap Arthur-Ficial/tap
brew install apfel-chat
apfel-chat
```

## Build from source

```bash
swift build -c release
make install
swift test              # run all tests
swift run apfel-chat    # run debug build
```

## Architecture

Protocol-driven, TDD-first. Every service has a protocol + mock for testing.

```
Sources/
├── App/              # Entry point, server lifecycle
├── Models/           # Data types (Conversation, Message, etc.)
├── Protocols/        # Service protocols (ChatService, Persistence, Speech)
├── Services/         # Real implementations (HTTP, SQLite, Speech)
├── ViewModels/       # @Observable state management
└── Views/            # SwiftUI views (thin, declarative)

Tests/
├── Mocks/            # Mock service implementations
└── *Tests.swift      # Unit tests for every component
```

## Key Design Decisions

- **No external dependencies** — only system frameworks + libsqlite3
- **Protocol-driven** — every service behind a protocol for TDD
- **SQLite via raw C API** — no ORM, no SwiftData, fast and simple
- **SwiftUI @main** — App Store compatible, no NSApplication wrapper
- **SSE streaming** — URLSession.bytes for real-time token streaming
- **apfel under the hood** — spawns `apfel --serve` or connects to existing

## API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Server status, version, model availability |
| `/v1/models` | GET | Model info and capabilities |
| `/v1/chat/completions` | POST | Chat (streaming SSE) |

## Ports

- apfel server: 11440-11449 (auto-selects first available)
- API control server: 11441 (when --api flag used)

## Testing

```bash
swift test                                    # all tests
swift test --filter ApfelChatTests.SSEParserTests  # specific test class
```

All ViewModels tested with mock services. SQLite tested with :memory: database.
SSE parser tested with fixture data. No UI tests — views are thin.

## Handling GitHub Issues

When a new issue comes in, follow this process:

1. **Fetch** the full issue with `gh issue view <n> --repo Arthur-Ficial/apfel-chat --json body,comments,title,author,labels`
2. **Vet** - is it a real bug, valid feature request, or noise?
   - Does it align with the purpose (fast, private, local macOS chat)?
   - Can you reproduce it or trace the root cause in code?
   - Check comments for additional context
3. **Fix** if valid:
   - Write tests first (TDD) for bugs
   - Keep changes minimal and focused
   - Run `swift test` - all tests must pass
4. **Release** if code changed - see "Release" below
5. **Close** the issue with a short, truthful comment:
   - What was the problem and root cause
   - What was fixed (or why closed without a fix)
   - How to update (`brew upgrade apfel-chat` or download from releases)
6. **Homebrew tap:** cask files live in `Casks/` in `Arthur-Ficial/homebrew-tap` (NOT `Formula/`). Formula files for CLI tools go in `Formula/`.

## Release

```bash
./scripts/release.sh 1.0.0
```
