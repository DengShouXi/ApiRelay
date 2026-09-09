import Foundation

/// 自动锁定 / 剪贴板清除共用的时长列表规则。
/// 最多 5 条；预填档与后加档同等可删；空列表与「从未写过」必须分开。
nonisolated enum DurationOptionList: Sendable {
    static let maxCount = 5
    static let maxHours = 23
    static let maxMinutes = 59
    /// 秒针 0...60，60 秒与 1 分钟同值，添加时会去重。
    static let maxSecondsComponent = 60

    static var maxTotalSeconds: Int {
        maxHours * 3600 + maxMinutes * 60 + maxSecondsComponent
    }

    static let autoLockFactory = [0, 60]
    static let clipboardFactory = [30, 120]

    enum AddResult: Equatable, Sendable {
        case added(options: [Int], selected: Int)
        case selectedExisting(options: [Int], selected: Int)
        case atCapacity
    }

    static func clamp(_ seconds: Int) -> Int {
        min(max(0, seconds), maxTotalSeconds)
    }

    static func total(hours: Int, minutes: Int, seconds: Int) -> Int {
        let h = min(max(0, hours), maxHours)
        let m = min(max(0, minutes), maxMinutes)
        let s = min(max(0, seconds), maxSecondsComponent)
        return clamp(h * 3600 + m * 60 + s)
    }

    /// 展示与轮盘回填用：把总量拆成时/分/秒，秒针落在 0...59（60 秒进到分）。
    static func components(_ totalSeconds: Int) -> (hours: Int, minutes: Int, seconds: Int) {
        let t = clamp(totalSeconds)
        return (t / 3600, (t % 3600) / 60, t % 60)
    }

    /// `nil` = 从未写过，调用方应预填；空数组 = 用户删光，不得再预填。
    static func decode(_ raw: String?) -> [Int]? {
        guard let raw else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let list = try? JSONDecoder().decode([Int].self, from: data) else { return nil }
        return normalized(list)
    }

    static func encode(_ options: [Int]) -> String {
        let data = (try? JSONEncoder().encode(normalized(options))) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func seedIfNeeded(stored: [Int]?, current: Int, factory: [Int]) -> [Int] {
        if let stored { return stored }
        var seed = normalized(factory)
        let value = clamp(current)
        if !seed.contains(value), seed.count < maxCount {
            seed.append(value)
        }
        return seed
    }

    static func adding(_ seconds: Int, to options: [Int]) -> AddResult {
        let value = clamp(seconds)
        let current = normalized(options)
        if current.contains(value) {
            return .selectedExisting(options: current, selected: value)
        }
        if current.count >= maxCount {
            return .atCapacity
        }
        return .added(options: current + [value], selected: value)
    }

    /// 删光时 `selected` 为 nil，调用方必须把功能关掉。
    static func removing(_ seconds: Int, from options: [Int], selected: Int) -> (options: [Int], selected: Int?) {
        let next = normalized(options).filter { $0 != seconds }
        if next.isEmpty { return (next, nil) }
        if selected == seconds { return (next, next[0]) }
        return (next, selected)
    }

    static func replacing(_ old: Int, with new: Int, in options: [Int]) -> AddResult {
        let withoutOld = normalized(options).filter { $0 != old }
        return adding(new, to: withoutOld)
    }

    static func displayName(_ totalSeconds: Int) -> String {
        if totalSeconds == 0 {
            return String(localized: "settings.duration.immediate")
        }
        let parts = components(totalSeconds)
        var tokens: [String] = []
        if parts.hours > 0 {
            tokens.append(String(localized: "settings.duration.part.hours \(parts.hours)"))
        }
        if parts.minutes > 0 {
            tokens.append(String(localized: "settings.duration.part.minutes \(parts.minutes)"))
        }
        if parts.seconds > 0 {
            tokens.append(String(localized: "settings.duration.part.seconds \(parts.seconds)"))
        }
        return tokens.joined(separator: " ")
    }

    /// 手输框用的时钟格式，始终三位：`H:MM:SS`（秒可到 60）。
    static func formatClock(hours: Int, minutes: Int, seconds: Int) -> String {
        let h = min(max(0, hours), maxHours)
        let m = min(max(0, minutes), maxMinutes)
        let s = min(max(0, seconds), maxSecondsComponent)
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    static func formatClock(_ totalSeconds: Int) -> String {
        let parts = components(totalSeconds)
        return formatClock(hours: parts.hours, minutes: parts.minutes, seconds: parts.seconds)
    }

    /// 解析手输结果。支持 `1:02:03`、`1：02：03`、`1:30`（分:秒）、`90`（纯秒）。
    /// 非法返回 `nil`，调用方保留原值不改轮盘。
    static func parseClock(_ raw: String) -> (hours: Int, minutes: Int, seconds: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: " ", with: "")
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            guard let only = Int(parts[0]), only >= 0 else { return nil }
            let total = clamp(only)
            let c = components(total)
            return (c.hours, c.minutes, c.seconds)
        case 2:
            guard let left = Int(parts[0]), let right = Int(parts[1]) else { return nil }
            return unpacked(hours: 0, minutes: left, seconds: right)
        case 3:
            guard let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
            return unpacked(hours: h, minutes: m, seconds: s)
        default:
            return nil
        }
    }

    private static func unpacked(hours: Int, minutes: Int, seconds: Int) -> (hours: Int, minutes: Int, seconds: Int)? {
        guard hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
        guard hours <= maxHours, minutes <= maxMinutes, seconds <= maxSecondsComponent else {
            let total = clamp(hours * 3600 + minutes * 60 + seconds)
            let c = components(total)
            return (c.hours, c.minutes, c.seconds)
        }
        return (hours, minutes, seconds)
    }

    private static func normalized(_ options: [Int]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for item in options {
            let value = clamp(item)
            if seen.insert(value).inserted {
                result.append(value)
            }
            if result.count == maxCount { break }
        }
        return result
    }
}
