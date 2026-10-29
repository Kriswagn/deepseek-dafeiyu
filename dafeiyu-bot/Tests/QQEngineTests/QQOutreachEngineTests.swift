import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

private final class OutreachModelProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var mode = "private"
    private static var count = 0
    private static var waiting: [OutreachModelProtocol] = []
    static func reset(_ value: String) { lock.lock(); defer { lock.unlock() }; mode = value; count = 0; waiting = [] }
    static var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func release() {
        lock.lock(); let requests = waiting; waiting = []; mode = "group"; lock.unlock()
        for request in requests { request.respond(mode: "group") }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; let mode = Self.mode; Self.lock.unlock()
        if mode == "pause" || mode == "activity" {
            Self.lock.lock(); Self.waiting.append(self); Self.lock.unlock(); return
        }
        respond(mode: mode)
    }
    private func respond(mode: String) {
        let texts = mode == "quiet" ? [] : ["burst", "interruptBurst"].contains(mode) ? (1...5).map { "合成主动话题\($0)" } : ["最近有什么好听的歌？", "想换个歌单试试。"]
        let decision = String(decoding: try! JSONSerialization.data(withJSONObject: ["messages": texts]), as: UTF8.self)
        let object: [String: Any] = ["choices": [["message": ["content": decision], "finish_reason": "stop"]], "usage": ["total_tokens": 3]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object)); client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct QQOutreachEngineTests {
    @Test(arguments: ["private", "group", "quiet", "pause", "activity", "dailyLimit", "unknown", "burst", "interruptBurst", "disabled", "singleReply", "randomQuiet"])
    func scheduledMessagesUseScopedQueueAndDurableLimits(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = ["group", "activity", "interruptBurst"].contains(mode)
        if group { try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape")) }
        if mode == "unknown" { try Data().write(to: directory.appendingPathComponent("drop-send")) }
        if mode == "interruptBurst" { try Data().write(to: directory.appendingPathComponent("interrupt-outreach")) }
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        OutreachModelProtocol.reset(mode)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [OutreachModelProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let testTime = Date().addingTimeInterval(3 * 3600)
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session), outreachClock: { testTime })
        defer { engine.disconnect() }
        engine.config.expectedSelfID = "12345"; engine.config.endpoint = "ws://127.0.0.1:\(port)"
        engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1
        engine.config.effectivePersona.style = .tieba; engine.config.effectivePersona.stickersEnabled = false
        engine.config.effectiveGroupParticipationEnabled = true; engine.config.memoryEnabled = false
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first { $0.group == group }))
        engine.config.targets[0].enabled = true
        let key = engine.config.targets[0].key
        engine.config.effectiveOutreach.enabled = mode != "disabled"
        engine.config.effectiveOutreach.targets = [key]
        if mode == "dailyLimit" { engine.config.effectiveOutreach.dailyMessages = 1 }
        engine.start(singleReply: mode == "singleReply")
        engine.scheduleOutreach(randomValue: mode == "randomQuiet" ? 0 : 1); engine.scheduleOutreach(randomValue: 1)
        if ["disabled", "singleReply", "randomQuiet"].contains(mode) {
            #expect(OutreachModelProtocol.calls == 0); #expect(engine.sends.attempts == 0); return
        }
        if mode == "pause" || mode == "activity" {
            let deadline = Date().addingTimeInterval(3)
            while OutreachModelProtocol.calls == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
            try #require(OutreachModelProtocol.calls > 0)
            if mode == "activity" {
                let event: [String: Any] = ["post_type": "message", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": 7, "message": [["type": "text", "data": ["text": "合成群成员正在聊天"]]]]
                try JSONSerialization.data(withJSONObject: [event]).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
                try await Task.sleep(nanoseconds: 200_000_000)
                #expect(engine.outreachLedger.activity["12345:" + key] != nil)
                OutreachModelProtocol.release()
                let until = Date().addingTimeInterval(2)
                while engine.outreachLedger.attempts.last?.state != "cancelled" && Date() < until { try await Task.sleep(nanoseconds: 20_000_000) }
                #expect(engine.outreachLedger.attempts.last?.state == "cancelled")
                #expect(engine.running); #expect(engine.sends.attempts == 0); return
            }
            engine.pause(); try await Task.sleep(nanoseconds: 100_000_000)
            #expect(engine.sends.attempts == 0); return
        }
        let expected = mode == "quiet" ? 0 : ["dailyLimit", "unknown", "interruptBurst"].contains(mode) ? 1 : mode == "burst" ? 5 : 2
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if mode == "quiet", engine.outreachLedger.attempts.last?.state == "quiet" { break }
            if mode == "unknown", engine.sends.uncertain == 1 { break }
            if mode == "interruptBurst", engine.outreachLedger.attempts.last?.state == "cancelled" { break }
            if mode != "unknown", engine.sends.confirmed == expected && engine.outreachLedger.attempts.last?.state == "completed" { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        #expect(engine.sends.attempts == expected)
        #expect(engine.outreachLedger.attempts.count == 1)
        #expect(engine.outreachLedger.used(account: "12345", config: engine.config.effectiveOutreach, now: testTime) == expected)
        #expect(engine.config.persona(for: key).effectiveStyle == .tieba)
        if mode == "unknown" { #expect(engine.sends.uncertain == 1); #expect(!engine.running) }
        else { #expect(engine.sends.confirmed == expected) }
        engine.scheduleOutreach(randomValue: 1)
        #expect(engine.outreachLedger.attempts.count == 1)
        let file = directory.appendingPathComponent("qq-state.json")
        let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let ledger = try JSONDecoder().decode(QQOutreachLedger.self, from: JSONSerialization.data(withJSONObject: stored["outreachLedger"]!))
        #expect(ledger.used(account: "12345", config: engine.config.effectiveOutreach, now: testTime) == expected)
    }
}
