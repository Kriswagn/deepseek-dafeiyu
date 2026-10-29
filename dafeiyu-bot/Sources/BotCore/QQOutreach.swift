import Foundation

/// Idle conversation invitations are separate from replies and group participation.
public struct QQOutreachConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var targets: [String] = []
    public var idleMinutes = 60
    public var dailyMessages = 20
    public var maxBurst = 5
    public var startHour = 0
    public var endHour = 24
    public var timeZone = "Asia/Shanghai"
    public init() {}
    public func validate() throws {
        guard (30...1440).contains(idleMinutes), (1...100).contains(dailyMessages),
              (1...5).contains(maxBurst), (0...23).contains(startHour), (1...24).contains(endHour),
              startHour < endHour, TimeZone(identifier: timeZone) != nil,
              targets.count <= 20, Set(targets).count == targets.count,
              targets.allSatisfy({ key in
                  let parts = key.split(separator: ":")
                  return parts.count == 2 && ["private", "group"].contains(String(parts[0])) && QQConfig.validID(String(parts[1]))
              }), !enabled || !targets.isEmpty else { throw CoreError.invalid("主动消息：空闲 30–1440 分钟、每日 1–100 条、每轮 1–5 条，须选择会话及时段") }
    }
    public func permits(_ now: Date) -> Bool {
        guard enabled, let zone = TimeZone(identifier: timeZone) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return (startHour..<endHour).contains(calendar.component(.hour, from: now))
    }
    public func day(_ now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}

public struct QQOutreachAttempt: Codable, Equatable, Sendable {
    public var id = UUID().uuidString
    public let scope: String
    public let at: Date
    /// Reserved before each transport submission. Unknown sends remain charged.
    public var messages = 0
    public var state = "evaluating"
    public init(scope: String, at: Date) { self.scope = scope; self.at = at }
}

public struct QQOutreachLedger: Codable, Equatable, Sendable {
    public var activity: [String: Date] = [:]
    public var activityVersions: [String: Int]?
    public var nextCheck: [String: Date] = [:]
    public var attempts: [QQOutreachAttempt] = []
    public init() {}
    public func used(account: String, config: QQOutreachConfig, now: Date) -> Int {
        attempts.filter { $0.scope.hasPrefix(account + ":") && config.day($0.at) == config.day(now) }.reduce(0) { $0 + $1.messages }
    }
    public func evaluationCount(account: String, config: QQOutreachConfig, now: Date) -> Int {
        attempts.filter { $0.scope.hasPrefix(account + ":") && config.day($0.at) == config.day(now) }.count
    }
    public mutating func touch(_ scope: String, now: Date) {
        activity[scope] = max(activity[scope] ?? .distantPast, now); nextCheck.removeValue(forKey: scope)
        let nextRevision = revision(scope) + 1
        if activityVersions == nil { activityVersions = [:] }
        activityVersions![scope] = nextRevision
    }
    public func revision(_ scope: String) -> Int { activityVersions?[scope] ?? 0 }
    public mutating func recover() {
        for index in attempts.indices where attempts[index].state == "evaluating" || attempts[index].state == "sending" {
            attempts[index].state = "interrupted"
        }
    }
    public mutating func trim(now: Date) {
        attempts = Array(attempts.filter { now.timeIntervalSince($0.at) < 7 * 86400 }.suffix(500))
        activity = activity.filter { now.timeIntervalSince($0.value) < 30 * 86400 }
        activityVersions = activityVersions?.filter { activity[$0.key] != nil }
        nextCheck = nextCheck.filter { $0.value > now.addingTimeInterval(-86400) }
    }
    public func due(scope: String, since: Date, config: QQOutreachConfig, now: Date) -> Bool {
        let account = String(scope.split(separator: ":").first ?? "")
        let idleSince = max(since, activity[scope] ?? since)
        return config.permits(now) && now.timeIntervalSince(idleSince) >= Double(config.idleMinutes * 60)
            && (nextCheck[scope].map { now >= $0 } ?? false)
            && used(account: account, config: config, now: now) < config.dailyMessages
            && evaluationCount(account: account, config: config, now: now) < 40
            && !attempts.contains { $0.scope.hasPrefix(account + ":") && now.timeIntervalSince($0.at) < 15 * 60 }
    }
    public mutating func reserveMessage(id: String, account: String, config: QQOutreachConfig, now: Date) throws {
        guard used(account: account, config: config, now: now) < config.dailyMessages,
              let index = attempts.firstIndex(where: { $0.id == id && $0.scope.hasPrefix(account + ":") }),
              config.day(attempts[index].at) == config.day(now), attempts[index].messages < config.maxBurst else {
            throw CoreError.invalid("主动消息额度已用完或任务已跨日")
        }
        attempts[index].messages += 1; attempts[index].state = "sending"
    }
    public mutating func finish(id: String, state: String) {
        if let index = attempts.firstIndex(where: { $0.id == id }) { attempts[index].state = state }
    }
}

public struct QQOutreachDecision: Decodable, Sendable {
    public let messages: [String]
    public static func decode(_ raw: String, maxBurst: Int, maxCharacters: Int) throws -> Self {
        guard raw.utf8.count <= 12000,
              let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              Set(object.keys) == ["messages"] else { throw CoreError.invalid("主动消息格式无效") }
        let result = try JSONDecoder().decode(Self.self, from: Data(raw.utf8))
        guard result.messages.count <= maxBurst, Set(result.messages).count == result.messages.count,
              result.messages.allSatisfy({ text in
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maxCharacters
                  && !text.contains("[CQ:") && !text.contains("sk-") && !text.contains("http://") && !text.contains("https://")
              }) else { throw CoreError.invalid("主动消息条数、字数或内容格式无效") }
        return result
    }
}
