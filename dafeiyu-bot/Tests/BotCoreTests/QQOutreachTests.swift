import Foundation
import Testing
@testable import BotCore

struct QQOutreachTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func idleIsOnlyEligibilityAndActivityResetsIt() throws {
        var settings = QQOutreachConfig(); settings.enabled = true; settings.targets = ["private:54321"]
        try settings.validate()
        var ledger = QQOutreachLedger(); let scope = "12345:private:54321", since = now.addingTimeInterval(-7200)
        #expect(!ledger.due(scope: scope, since: since, config: settings, now: now))
        ledger.nextCheck[scope] = now
        #expect(ledger.due(scope: scope, since: since, config: settings, now: now))
        ledger.touch(scope, now: now.addingTimeInterval(-3599)); ledger.nextCheck[scope] = now
        let revision = ledger.revision(scope)
        ledger.touch(scope, now: now.addingTimeInterval(-3600)); ledger.nextCheck[scope] = now
        #expect(ledger.revision(scope) == revision + 1) // Second-resolution or delayed events still cancel an admitted burst.
        #expect(!ledger.due(scope: scope, since: since, config: settings, now: now))
        #expect(!ledger.due(scope: scope, since: now, config: settings, now: now))
        settings.enabled = false
        #expect(!ledger.due(scope: scope, since: since, config: settings, now: now))
    }
    @Test func sharedMessageBudgetSurvivesRestartAndUnknownDelivery() throws {
        var settings = QQOutreachConfig(); settings.enabled = true; settings.targets = ["private:54321", "group:99999"]
        var ledger = QQOutreachLedger()
        for index in 0..<4 {
            let attempt = QQOutreachAttempt(scope: index % 2 == 0 ? "12345:private:54321" : "12345:group:99999", at: now)
            ledger.attempts.append(attempt)
            for _ in 0..<5 { try ledger.reserveMessage(id: attempt.id, account: "12345", config: settings, now: now) }
        }
        #expect(ledger.used(account: "12345", config: settings, now: now) == 20)
        #expect(throws: (any Error).self) { try ledger.reserveMessage(id: ledger.attempts[0].id, account: "12345", config: settings, now: now) }
        var restored = try JSONDecoder().decode(QQOutreachLedger.self, from: JSONEncoder().encode(ledger)); restored.recover()
        #expect(restored.used(account: "12345", config: settings, now: now) == 20)
        #expect(restored.attempts.allSatisfy { $0.state == "interrupted" })
        #expect(restored.used(account: "77777", config: settings, now: now) == 0)
        #expect(restored.used(account: "12345", config: settings, now: now.addingTimeInterval(86400)) == 0)
    }
    @Test func burstAndDecisionMustBeBoundedAndExplicit() throws {
        #expect(try QQOutreachDecision.decode(#"{"messages":[]}"#, maxBurst: 5, maxCharacters: 60).messages.isEmpty)
        #expect(try QQOutreachDecision.decode(#"{"messages":["最近有听到什么好听的歌？"]}"#, maxBurst: 5, maxCharacters: 60).messages.count == 1)
        for raw in [#"{"messages":["一样","一样"]}"#, #"{"messages":["https://example.invalid"]}"#, #"{"messages":["超长测试"]}"#, #"{"messages":[],"send":true}"#] {
            #expect(throws: (any Error).self) { try QQOutreachDecision.decode(raw, maxBurst: 5, maxCharacters: 3) }
        }
        var settings = QQOutreachConfig(); settings.maxBurst = 6
        #expect(throws: (any Error).self) { try settings.validate() }
        settings.maxBurst = 5; settings.targets = ["group:0001"]
        #expect(throws: (any Error).self) { try settings.validate() }
    }
    @Test func timezoneAndAttemptFairnessAreBounded() {
        var settings = QQOutreachConfig(); settings.enabled = true; settings.startHour = 9; settings.endHour = 22
        let midnight = ISO8601DateFormatter().date(from: "2026-10-29T16:00:00Z")!
        #expect(!settings.permits(midnight))
        #expect(settings.day(midnight) == "2026-10-30")
        settings.startHour = 0; settings.endHour = 24
        #expect(settings.permits(midnight))
        var ledger = QQOutreachLedger(); let scope = "12345:group:99999"
        ledger.nextCheck[scope] = now
        ledger.attempts.append(QQOutreachAttempt(scope: "12345:private:54321", at: now.addingTimeInterval(-60)))
        #expect(!ledger.due(scope: scope, since: now.addingTimeInterval(-7200), config: settings, now: now))
    }
}
