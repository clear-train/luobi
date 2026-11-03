import AppKit

// MARK: - 写作计时
//
// 为什么做这个而不是继续卷字数功能：
//   字数是结果，时间是习惯。一天只能挤出 40 分钟的人，盯着"今天要写 3000 字"
//   只会更挫败；但"今天坐了 40 分钟"是达成的，能持续。
//
// 计时规则（宁可少算，不可多算）：
//   · 只有窗口在前台、并且是键盘焦点时才计时
//   · 只有最近 2 分钟里有输入才算"正在写"，发呆/开会不算
//   · 每 20 秒一拍，攒够 60 秒才落盘一次（不折腾磁盘）
//   · 一天最多算 12 小时（防止挂着过夜）

extension EditorRoot {

    static let sessionTick: TimeInterval = 20

    /// 记一次"人还在"（打字、改标题、切稿都算）
    func noteActivity() {
        lastActivityAt = Date()
    }

    func startSessionTracking() {
        guard sessionTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: EditorRoot.sessionTick, repeats: true) { [weak self] _ in
            self?.tickSession()
        }
        RunLoop.main.add(t, forMode: .common)
        sessionTimer = t
    }

    func stopSessionTracking() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    /// 一拍：判断"人还在写吗"，是就记 20 秒
    func tickSession() {
        guard let win = window, win.isKeyWindow, NSApp.isActive else { return }
        guard Date().timeIntervalSince(lastActivityAt) < 120 else { return }
        sessionAccrued += Int(EditorRoot.sessionTick)
        if sessionAccrued >= 60 { flushSession() }
    }

    /// 把攒的秒数写进文稿并落盘
    func flushSession() {
        guard sessionAccrued > 0 else { return }
        doc.addWriteSeconds(sessionAccrued)
        sessionAccrued = 0
        persistNow()
    }
}
