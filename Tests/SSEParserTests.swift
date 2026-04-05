import Testing
import Foundation
@testable import apfel_chat

@Suite("SSE Parser")
struct SSEParserTests {

    @Test("Parses content delta from SSE line")
    func parseContentDelta() throws {
        let line = #"data: {"id":"req-1","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#
        let delta = SSEParser.parse(line: line)
        #expect(delta?.text == "Hello")
        #expect(delta?.finishReason == nil)
    }

    @Test("Parses finish reason")
    func parseFinishReason() throws {
        let line = #"data: {"id":"req-1","choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#
        let delta = SSEParser.parse(line: line)
        #expect(delta?.finishReason == "stop")
    }

    @Test("Parses usage chunk")
    func parseUsage() throws {
        let line = #"data: {"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        let delta = SSEParser.parse(line: line)
        #expect(delta?.usage?.promptTokens == 10)
        #expect(delta?.usage?.completionTokens == 5)
        #expect(delta?.usage?.totalTokens == 15)
    }

    @Test("Returns nil for DONE signal")
    func parseDone() {
        let delta = SSEParser.parse(line: "data: [DONE]")
        #expect(delta == nil)
    }

    @Test("Returns nil for non-data lines")
    func parseNonData() {
        #expect(SSEParser.parse(line: ": keepalive") == nil)
        #expect(SSEParser.parse(line: "") == nil)
        #expect(SSEParser.parse(line: "event: ping") == nil)
    }

    @Test("Parses error in stream")
    func parseStreamError() {
        let line = #"data: {"error":{"message":"Context length exceeded","type":"context_length_exceeded"}}"#
        let delta = SSEParser.parse(line: line)
        #expect(delta == nil)
        let error = SSEParser.parseError(line: line)
        #expect(error?.message == "Context length exceeded")
        #expect(error?.type == "context_length_exceeded")
    }
}
