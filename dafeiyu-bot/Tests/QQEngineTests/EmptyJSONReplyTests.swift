import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WeChatAIBot
import BotCore

private final class EmptyJSONProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096), output = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                output.append(contentsOf: buffer.prefix(count))
            }
            body = output
        }
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        let messages = object["messages"] as! [[String: Any]]
        let prompt = messages[0]["content"] as! String
        let recovery = prompt.contains("API 空正文恢复")
        var content: Any = NSNull()
        if recovery {
            #expect(object["response_format"] == nil)
            #expect(prompt.contains("original-system-constraint"))
            #expect(messages.last?["content"] as? String == "synthetic-current-input")
            #expect((object["thinking"] as? [String: String])?["type"] == "enabled")
            if prompt.contains("recover-fixture") {
                content = #"{"text":"收到啦。","emotion":"neutral","intensity":1}"#
            }
        } else if prompt.contains("always-empty") { content = "  \n" }
        let finish = prompt.contains("length-fixture") ? "length" : "stop"
        let data = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content, "reasoning_content": "synthetic-private-reasoning"], "finish_reason": finish]],
            "usage": ["total_tokens": 3]
        ])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private actor EmptyJSONReservations {
    var value = 0
    func reserve(limit: Int = 10) throws {
        value += 1
        if value > limit { throw CoreError.invalid("synthetic-quota") }
    }
}

@Suite struct EmptyJSONReplyTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmptyJSONProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func recoversWithoutLeakingReasoningOrLosingOriginalContext() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        var rule = ChatRule(name: "fixture"); rule.prompt = "original-system-constraint recover-fixture"
        let reservations = EmptyJSONReservations()
        let result = try await DeepSeekClient(session: session).reply(key: "synthetic", config: QQConfig().ai,
            rule: rule, history: [], text: "synthetic-current-input", jsonOutput: true, thinkingEnabled: true,
            reserve: { try await reservations.reserve() })
        #expect(await reservations.value == 2)
        #expect(result.tokens == 6)
        #expect(!result.text.contains("synthetic-private-reasoning"))
        #expect(QQPersona().decode(result.text, input: "fixture").text == "收到啦。")
    }
    @Test(arguments: ["always-empty", "length-fixture", "plain-fixture"])
    func unsuccessfulResponsesStayBounded(mode: String) async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        var rule = ChatRule(name: "fixture"); rule.prompt = "original-system-constraint " + mode
        let reservations = EmptyJSONReservations()
        do {
            _ = try await DeepSeekClient(session: session).reply(key: "synthetic", config: QQConfig().ai,
                rule: rule, history: [], text: "synthetic-current-input", jsonOutput: mode != "plain-fixture", thinkingEnabled: true,
                reserve: { try await reservations.reserve() })
            Issue.record("Expected rejection of empty or truncated output")
        } catch {
            #expect(error.localizedDescription.contains("模型未返回完整文字回复"))
        }
        #expect(await reservations.value == (mode == "always-empty" ? 3 : 1))
    }
    @Test func recoveryCannotBypassQuota() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        var rule = ChatRule(name: "fixture"); rule.prompt = "original-system-constraint recover-fixture"
        let reservations = EmptyJSONReservations()
        do {
            _ = try await DeepSeekClient(session: session).reply(key: "synthetic", config: QQConfig().ai,
                rule: rule, history: [], text: "synthetic-current-input", jsonOutput: true, thinkingEnabled: true,
                reserve: { try await reservations.reserve(limit: 1) })
            Issue.record("Expected quota to block recovery")
        } catch { #expect(error.localizedDescription == "synthetic-quota") }
        #expect(await reservations.value == 2)
    }
}
