import Foundation

// MARK: - 数据模型：多篇文稿

struct Sheet: Codable {
    var id: String
    var title: String
    var content: String
    var updatedAt: Double = 0
}

struct DocState: Codable {
    var sheets: [Sheet]
    var activeId: String
    var typewriter: Bool = true
    var markdown: Bool = true

    static func initial() -> DocState {
        let s = Sheet(id: UUID().uuidString, title: "第一章", content: "开始写。")
        return DocState(sheets: [s], activeId: s.id)
    }

    func sheet(id: String) -> Sheet? { sheets.first { $0.id == id } }
}

// 旧版单篇文档的形状，只迁移用
struct LegacyDoc: Codable {
    var title: String?
    var content: String?
    var typewriter: Bool?
    var markdown: Bool?
}

// MARK: - 文稿库（唯一允许碰磁盘的模块）

enum Vault {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UlyssesNative", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("state.json") }

    static func ensure() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load() -> DocState {
        ensure()
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return .initial() }
        if let fresh = try? JSONDecoder().decode(DocState.self, from: data),
           !fresh.sheets.isEmpty, fresh.sheet(id: fresh.activeId) != nil {
            return fresh
        }
        if let legacy = try? JSONDecoder().decode(LegacyDoc.self, from: data) {
            let s = Sheet(id: UUID().uuidString,
                          title: legacy.title ?? "未命名",
                          content: legacy.content ?? "")
            return DocState(sheets: [s], activeId: s.id,
                            typewriter: legacy.typewriter ?? true,
                            markdown: legacy.markdown ?? true)
        }
        return .initial()
    }

    static func save(_ doc: DocState) -> Bool {
        ensure()
        do {
            let tmp = file.appendingPathExtension("tmp")
            try JSONEncoder().encode(doc).write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 统计

func statCJK(_ s: String) -> Int {
    s.unicodeScalars.filter { u in
        (0x2E80...0x9FFF).contains(u.value)
            || (0x3400...0x4DBF).contains(u.value)
            || (0xF900...0xFAFF).contains(u.value)
            || (0x3040...0x30FF).contains(u.value)
    }.count
}

func statLatin(_ s: String) -> Int {
    var n = 0
    var inWord = false
    for u in s.unicodeScalars {
        let isLetter = u.value < 0x80 && (u.properties.isAlphabetic || u.properties.numericType != nil)
        if isLetter {
            if !inWord { n += 1; inWord = true }
        } else {
            inWord = false
        }
    }
    return n
}
