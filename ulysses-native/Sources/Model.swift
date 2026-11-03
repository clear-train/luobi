import Foundation

// MARK: - 数据模型：分组（树）+ 多篇文稿

struct Folder: Codable {
    var id: String
    var name: String
    var parentId: String? = nil
    var expanded: Bool? = nil   // nil 视作展开，兼容旧数据
}

struct Sheet: Codable {
    var id: String
    var title: String
    var content: String
    var updatedAt: Double = 0
    var folderId: String? = nil   // nil = 放在最外层
}

struct DocState: Codable {
    var sheets: [Sheet]
    var activeId: String
    var typewriter: Bool = true
    var markdown: Bool = true
    var theme: String = "paper"      // paper | ivory | green | deep
    var goal: Int = 0                // 目标总字数，0=未启用
    var folders: [Folder] = []
    var sidebarVisible: Bool = true
    var fontSize: Double = 17
    var seenGuide: Bool = false     // 首次启动自动弹一次使用指南

    init(sheets: [Sheet], activeId: String) {
        self.sheets = sheets
        self.activeId = activeId
    }

    enum CodingKeys: String, CodingKey {
        case sheets, activeId, typewriter, markdown, theme, goal, folders, sidebarVisible, fontSize, seenGuide
    }

    // 手写解码：老版本 state.json 缺字段时回落默认值，不丢数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sheets = try c.decode([Sheet].self, forKey: .sheets)
        activeId = try c.decode(String.self, forKey: .activeId)
        typewriter = try c.decodeIfPresent(Bool.self, forKey: .typewriter) ?? true
        markdown = try c.decodeIfPresent(Bool.self, forKey: .markdown) ?? true
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "paper"
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 0
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 17
        seenGuide = try c.decodeIfPresent(Bool.self, forKey: .seenGuide) ?? false
    }

    static func initial() -> DocState {
        let folder = Folder(id: UUID().uuidString, name: "小说")
        let s = Sheet(id: UUID().uuidString, title: "第一章", content: "开始写。", folderId: folder.id)
        let guide = Sheet(id: UUID().uuidString, title: "使用指南", content: """
# 欢迎使用 Ulysses Native

这是一个把「写字」放在第一位的本地写作软件。下面是最短的上手路径。

## 三步开始

1. 左下角「＋文」新建一篇；「▤ 分组」建一个文件夹，把文稿归进去。
2. 直接把想法敲进来，不用管格式。
3. 停笔 0.8 秒会自动保存。

## 几个按钮

- 顶部工具栏从左到右：＋文（新建文稿）、▤ 分组（新建文件夹）、侧栏（收起/展开）、导入、导出、打字机、排版、主题、目标、指南。
- 侧栏里的文稿可以直接拖进文件夹；右键有重命名、删除。
- 打字机：正在写的这一行始终停在屏幕中间，眼睛不用追。
- 排版：# 开头是标题，**两边两个星号**是加粗，> 开头是引用。

## 你的字存在哪儿

~/Library/Application Support/UlyssesNative/state.json

这是唯一的数据文件。想备份，复制它就行；想换电脑，把它带过去。

## 少记快捷键

功能都做成了可点的按钮和右键菜单，只有四个最常用的键：
⌘N 新建文稿　⌘S 保存　⌘O 导入　⌘E 导出
""", folderId: nil)
        return DocState(sheets: [s, guide], activeId: s.id).with(folders: [folder])
    }

    func with(folders: [Folder]) -> DocState {
        var copy = self
        copy.folders = folders
        return copy
    }

    func sheet(id: String) -> Sheet? { sheets.first { $0.id == id } }
    func folder(id: String) -> Folder? { folders.first { $0.id == id } }

    /// 某个分组下的直接子分组
    func childFolders(of parent: String?) -> [Folder] {
        folders.filter { $0.parentId == parent }
    }

    /// 某个分组下的直接子文稿
    func sheets(in parent: String?) -> [Sheet] {
        sheets.filter { ($0.folderId ?? nil) == parent }
    }
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
            var doc = DocState(sheets: [s], activeId: s.id)
            doc.typewriter = legacy.typewriter ?? true
            doc.markdown = legacy.markdown ?? true
            return doc
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
