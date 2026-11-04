import AppKit

/// 影子：过去的自己这时候写到哪儿了。
///
/// 数据来源是先前的 hourlyWords（按小时记的字数）。把"同一天的同一小时"跨天取平均，
/// 就能得到一条"过去的自己"的基准线；今天已经过去多少小时，就取对应区间的累计值。
/// 它不需要任何新数据，写几天就自动有了。
struct ShadowStats {
    var expected: Int      // 过去的自己，到这个点大概写了多少
    var actual: Int        // 今天的你，到现在写了多少
    var days: Int          // 有记录的天数（不含今天）

    var hasHistory: Bool { days > 0 }
    var delta: Int { actual - expected }
    var verdict: String {
        if !hasHistory { return "再写几天就有参照了" }
        if delta >= 0 { return "领先 \(delta) 字" }
        return "落后 \(-delta) 字"
    }
}

extension DocState {

    func shadow(now: Date = Date()) -> ShadowStats {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let todayKey = fmt.string(from: now)
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)

        // 按小时聚合成"每天平均"
        var sums: [Int: Int] = [:]
        var seenDays = Set<String>()
        for (key, words) in hourlyWords {
            // key 形如 "2026-11-04 15"
            guard key.count >= 13 else { continue }
            let day = String(key.prefix(10))
            guard day != todayKey else { continue }
            guard let h = Int(key.suffix(2)) else { continue }
            sums[h, default: 0] += words
            seenDays.insert(day)
        }
        guard !seenDays.isEmpty else {
            return ShadowStats(expected: 0, actual: todayWritten, days: 0)
        }
        let days = seenDays.count
        func avg(_ h: Int) -> Double { Double(sums[h] ?? 0) / Double(days) }

        var expected = 0.0
        for h in 0..<hour { expected += avg(h) }
        expected += avg(hour) * (Double(minute) / 60.0)

        return ShadowStats(expected: Int(expected.rounded()), actual: todayWritten, days: days)
    }
}

extension EditorRoot {

    var shadowModeEnabled: Bool {
        UserDefaults.standard.object(forKey: "shadowMode") as? Bool ?? true
    }

    @objc func toggleShadowMode(_ sender: Any?) {
        UserDefaults.standard.set(!shadowModeEnabled, forKey: "shadowMode")
        startupNote = shadowModeEnabled ? "影子模式已打开：和过去的自己比" : "影子模式已关闭"
        refreshBar()
        rebuildStatusMenu()
    }
}
