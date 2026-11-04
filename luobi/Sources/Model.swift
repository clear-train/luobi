import Foundation

// MARK: - 数据模型：分组（树）+ 多篇文稿

struct Folder: Codable {
    var id: String
    var name: String
    var parentId: String? = nil
    var expanded: Bool? = nil   // nil 视作展开，兼容旧数据
}

/// 人物 / 设定卡片的字段。写小说时最难记的是"这个人的口头禅、和谁什么关系"，
/// 所以把它从正文里拎出来变成结构化的几栏。
struct CardData: Codable, Equatable {
    var name: String = ""
    var relation: String = ""      // 关系：主角的母亲 / 邻居 / 反派
    var appearance: String = ""    // 外貌
    var catchphrase: String = ""   // 口头禅

    enum CodingKeys: String, CodingKey { case name, relation, appearance, catchphrase }

    init() {}

    init(name: String = "", relation: String = "", appearance: String = "", catchphrase: String = "") {
        self.name = name; self.relation = relation
        self.appearance = appearance; self.catchphrase = catchphrase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? ""
        catchphrase = try c.decodeIfPresent(String.self, forKey: .catchphrase) ?? ""
    }
}

struct Sheet: Codable {
    var id: String
    var title: String
    var content: String
    var updatedAt: Double = 0
    var folderId: String? = nil   // nil = 放在最外层
    var card: CardData? = nil     // 非空 = 这是一张人物/设定卡片
    var target: Int = 0           // 这一章的目标字数，0=不设

    enum CodingKeys: String, CodingKey {
        case id, title, content, updatedAt, folderId, card, target
    }

    init(id: String, title: String, content: String = "",
         updatedAt: Double = 0, folderId: String? = nil, card: CardData? = nil, target: Int = 0) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
        self.folderId = folderId
        self.card = card
        self.target = target
    }

    // 手写解码：手改过 / 老版本的 JSON 缺字段时按默认值补，不整份报废
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        card = try c.decodeIfPresent(CardData.self, forKey: .card)
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 0
    }
}


// MARK: - 书

/// 一本书 = 一组文稿 + 一棵分组树 + 当前打开的那一篇。
/// 书库页（Library）列出所有 Book；「随笔夹」也是一本 Book，只是 kind == "essays"，
/// 它的作用是接住"随手想记两句但还没决定放哪本书"的内容。
struct Book: Codable, Identifiable {
    var id: String
    var title: String
    var kind: String = "book"        // "book" | "essays"
    var createdAt: Double = 0
    var updatedAt: Double = 0
    var sheets: [Sheet] = []
    var folders: [Folder] = []
    var activeId: String = ""

    var isEssays: Bool { kind == "essays" }

    /// 只数正文：人物卡和设定不算"写了多少字"
    var words: Int {
        sheets.reduce(0) { sum, s in
            guard s.card == nil else { return sum }
            return sum + statCJK(s.content) + statLatin(s.content)
        }
    }
    var chapterCount: Int { sheets.filter { $0.card == nil }.count }
    var cardCount: Int { sheets.filter { $0.card != nil }.count }

    static func new(id: String = UUID().uuidString, title: String, kind: String = "book") -> Book {
        let now = Date().timeIntervalSince1970
        return Book(id: id, title: title, kind: kind, createdAt: now, updatedAt: now)
    }
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
    var indentChars: Int = 2           // 首行缩进几个字（0 = 不缩进），中文习惯是 2
    var lineSpacing: Double = 7        // 行间距（17pt 下的基准值，随字号等比缩放）
    var paragraphSpacing: Double = 0   // 段间距（正文用空行分段时，这里留 0 就够）（同上）
    var dailyGoal: Int = 0             // 每日目标字数，0 = 不设
    var dailyBase: [String: Int] = [:] // "2026-11-03" -> 当天开工时全书字数
    var dailyDone: [String: Int] = [:] // "2026-11-03" -> 当天最多写到过多少字
    var writeSeconds: [String: Int] = [:] // "2026-11-03" -> 当天真正在写的秒数
    var pomodoroDone: [String: Int] = [:] // "2026-11-03" -> 当天完成的番茄数
    var focusMinutes: Int = 25            // 一个专注段多长
    var breakMinutes: Int = 5             // 一段休息多长
    var hourlyWords: [String: Int] = [:]  // "2026-11-03 21" -> 那个小时写了多少字
    var peakWPM: Int = 0                  // 观测到的最快写作速度（字/分钟）

    // --- 书库：books 里放着每一本书的完整内容（含当前这本的副本）---
    // 当前正在写的这一本，仍然以 sheets/folders/activeId 三个字段作为"工作副本"，
    // 这样侧栏、大纲板、统计等上百处 doc.sheets 的代码不用改。
    var books: [Book] = []
    var activeBookId: String = ""
    var libraryOpen: Bool = false         // true = 显示书库页，false = 在写作界面

    init(sheets: [Sheet], activeId: String) {
        self.sheets = sheets
        self.activeId = activeId
        migrateToBooksIfNeeded()
    }

    enum CodingKeys: String, CodingKey {
        case sheets, activeId, typewriter, markdown, theme, goal, folders, sidebarVisible, fontSize, seenGuide, indentChars, lineSpacing, paragraphSpacing, dailyGoal, dailyBase, dailyDone, writeSeconds, pomodoroDone, focusMinutes, breakMinutes, hourlyWords, peakWPM
        case books, activeBookId, libraryOpen
    }

    /// 只用于读老数据：0.8 之前的「是否缩进」开关
    private enum LegacyKeys: String, CodingKey {
        case indentParagraphs
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
        // 老版本只有一个「是否缩进」开关，迁移成"缩进几个字"
        if let n = try c.decodeIfPresent(Int.self, forKey: .indentChars) {
            indentChars = max(0, min(4, n))
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let on = try? legacy.decodeIfPresent(Bool.self, forKey: .indentParagraphs), on == false {
            indentChars = 0
        }
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 7
        paragraphSpacing = try c.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 0
        // 上一版默认是 13/12，会把"空行分段 + 段距"叠成三倍行距；
        // 明显是旧默认值的直接迁移成新默认（用户手动调过的值不受影响）
        if lineSpacing == 13 && paragraphSpacing == 12 {
            lineSpacing = 7
            paragraphSpacing = 0
        }
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 0
        dailyBase = try c.decodeIfPresent([String: Int].self, forKey: .dailyBase) ?? [:]
        dailyDone = try c.decodeIfPresent([String: Int].self, forKey: .dailyDone) ?? [:]
        writeSeconds = try c.decodeIfPresent([String: Int].self, forKey: .writeSeconds) ?? [:]
        seenGuide = try c.decodeIfPresent(Bool.self, forKey: .seenGuide) ?? false
        pomodoroDone = try c.decodeIfPresent([String: Int].self, forKey: .pomodoroDone) ?? [:]
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 5
        hourlyWords = try c.decodeIfPresent([String: Int].self, forKey: .hourlyWords) ?? [:]
        peakWPM = try c.decodeIfPresent(Int.self, forKey: .peakWPM) ?? 0
        books = try c.decodeIfPresent([Book].self, forKey: .books) ?? []
        activeBookId = try c.decodeIfPresent(String.self, forKey: .activeBookId) ?? ""
        libraryOpen = try c.decodeIfPresent(Bool.self, forKey: .libraryOpen) ?? false
        migrateToBooksIfNeeded()
    }

    // MARK: - 书库

    var currentBookIndex: Int? { books.firstIndex { $0.id == activeBookId } }
    var currentBook: Book? { currentBookIndex.map { books[$0] } }
    var bookTitle: String { currentBook?.title ?? "未命名" }
    var essaysBook: Book? { books.first { $0.isEssays } }

    /// 把工作副本写回 books 里当前这本（保存、切换、离开写作页时都要调）
    mutating func syncCurrentBook() {
        guard let i = currentBookIndex else { return }
        books[i].sheets = sheets
        books[i].folders = folders
        books[i].activeId = activeId
        books[i].updatedAt = Date().timeIntervalSince1970
    }

    /// 打开另一本书：先存当前，再把目标装载成工作副本
    mutating func openBook(_ id: String) -> Bool {
        if id == activeBookId { return true }
        syncCurrentBook()
        guard let i = books.firstIndex(where: { $0.id == id }) else { return false }
        activeBookId = id
        sheets = books[i].sheets
        folders = books[i].folders
        activeId = books[i].activeId
        if !sheets.contains(where: { $0.id == activeId }) { activeId = sheets.first?.id ?? "" }
        libraryOpen = false
        return true
    }

    @discardableResult
    mutating func createBook(_ title: String) -> String {
        syncCurrentBook()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = Book.new(title: t.isEmpty ? "未命名" : t)
        books.append(b)
        return b.id
    }

    /// 删书：至少留一本；删的是当前这本时自动切到第一本
    @discardableResult
    mutating func deleteBook(_ id: String) -> Bool {
        guard books.count > 1, let i = books.firstIndex(where: { $0.id == id }) else { return false }
        let wasActive = (id == activeBookId)
        books.remove(at: i)
        if wasActive, let next = books.first {
            activeBookId = next.id
            sheets = next.sheets
            folders = next.folders
            activeId = next.activeId
            if !sheets.contains(where: { $0.id == activeId }) { activeId = sheets.first?.id ?? "" }
        }
        return true
    }

    mutating func renameBook(_ id: String, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].title = t
        books[i].updatedAt = Date().timeIntervalSince1970
    }

    /// 随笔夹：不管现在在哪本书，写一篇"还没归档"的速记
    @discardableResult
    mutating func quickNote() -> String {
        syncCurrentBook()
        if essaysBook == nil { books.append(Book.new(title: "随笔夹", kind: "essays")) }
        guard let eid = essaysBook?.id else { return "" }
        if activeBookId != eid { _ = openBook(eid) }
        let sheet = Sheet(id: UUID().uuidString, title: "随手记 " + DocState.stamp(), content: "")
        sheets.insert(sheet, at: 0)
        activeId = sheet.id
        syncCurrentBook()
        libraryOpen = false
        return sheet.id
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    /// 老数据（没有 books）→ 包成第一本书，并补一个随笔夹
    mutating func migrateToBooksIfNeeded() {
        if books.isEmpty {
            let first = Book.new(title: "我的第一本书")
            var b = first
            b.sheets = sheets
            b.folders = folders
            b.activeId = activeId
            books = [b]
            activeBookId = b.id
            libraryOpen = true      // 第一次见到书库：先让用户挑一本书
        }
        if !books.contains(where: { $0.isEssays }) {
            books.append(Book.new(title: "随笔夹", kind: "essays"))
        }
        if activeBookId.isEmpty || !books.contains(where: { $0.id == activeBookId }) {
            activeBookId = books[0].id
        }
    }

    static func initial() -> DocState {
        let folder = Folder(id: UUID().uuidString, name: "小说")
        let s = Sheet(id: UUID().uuidString, title: "第一章", content: "开始写。", folderId: folder.id)
        let guide = Sheet(id: UUID().uuidString, title: "使用指南", content: """
# 欢迎使用落笔

这是一个把「写字」放在第一位的本地写作软件。下面是最短的上手路径。

## 三步开始

1. 一进来是**书库**：点一本书开始写；想随手记两句就点「随笔夹」里的「＋ 速记」。
2. 左侧栏顶部「＋」下拉里可以新建文稿或新建分组；书名旁边「‹ 书库」随时回书库换书。
3. 直接把想法敲进来，不用管格式；停笔 0.8 秒自动保存。

## 几个按钮

- 顶栏现在只有两个环：🍅 番茄钟、今 今日进度，鼠标停在番茄上会浮出今天的数据。新建/分组收在侧栏顶部，收起侧栏（«）也在侧栏右上角。
- 一本书一套文稿：书与书之间完全独立，书库卡片上鼠标移上去能看到这周改了多少。
- 侧栏里的文稿可以直接拖进文件夹；右键有重命名、删除。
- 打字机：正在写的这一行始终停在屏幕中间，眼睛不用追。
- 排版：# 开头是标题，**两边两个星号**是加粗，> 开头是引用。
- 缩进：每段首行空两格，中文长篇的版面习惯，点一下就能关。
- 专注：收起侧栏和工具栏，正文收成一条居中的栏，只留字。按 Esc 或点右上角回来。
- 底部状态栏写着「本篇多少字 / 全书多少字」，写长篇时心里有数。
- 成书：把分组里的稿子按侧栏顺序拼成一整本，导出网页（双击就能看/打印）、Markdown 或 Word（.rtf，发给编辑直接能开）。
- 写作目标：侧栏左下角点「写作目标」，设每天多少字；底部细进度条和状态栏会跟着涨，达标变绿。
- 排序：拖动文稿可以调顺序（也能拖进分组）；不想拖就右键「上移一位 / 下移一位」。
- 人物卡片：选中正文里的名字 → 右键 → 建人物卡；视图菜单「人物一览」能看全部人物。
- 出场索引：卡片弹窗里点「看出场章节」，能看到这个人出现在哪几章、各几次，点一下直接跳过去。
- 人物关系图：视图菜单 → 人物关系图，谁和谁有关一目了然（关系里写名字就会连线）。
- 阅读模式：视图菜单 → 阅读模式，藏起所有控件、正文只读、← → 翻篇、Esc 退出，通读改稿时用。
- 番茄钟与今日进度：顶栏两个环，同步显示在 **macOS 菜单栏图标**里；点菜单栏图标能开始/暂停番茄、看今日字数。时间到了右下角软提示，12 秒自己消失，不打断你。
- 顶栏只有「新建 / 分组 / 收起侧栏」三个按钮 + 两个环，其余动作都在菜单栏图标和应用菜单里。
- 大纲板：视图菜单 → 大纲板，章节平铺成卡片墙，拖动可重排、点一下进入那一章。
- 查找替换：编辑菜单 ⌘F，支持全库/当前分组/当前篇，改完自动备份。
- 历史版本：右键章节 → 历史版本，每次改动自动留一份，能看能恢复。
- 逐章目标：右键章节 → 设置本章目标，大纲板标明偏短/刚好/偏长。
- 新建人物卡：右键 → 新建人物卡，填姓名/关系/外貌/口头禅；正文里按住 ⌘ 点人名就能看这张卡。
- 统计：侧栏左下角点「统计」，看最近 30 天每天写了多少字、连续写了多久。
- 导入旧稿：工具栏「导入」支持 .md/.txt/.rtf/.docx，自动认编码（GBK 老稿也不乱码），全部放进一个新的「导入 日期」分组。
- 搜索：左上角搜索框搜**标题和正文**，结果显示命中片段，点一条直接跳到命中处。

## 你的字存在哪儿

~/Library/Application Support/Luobi/state.json

同一个文件夹里还有两份保险：
- state.json.bak：上一版（每次保存前自动留）
- Backups/ 里的时间戳快照：每 5 分钟一份，留最近 20 份

文件菜单里有「立即备份一份」「从备份恢复…」「打开备份文件夹」。真出事了，主文件读不出来时会自动从 .bak 或最近快照恢复，状态栏会告诉你发生了什么。

## 少记快捷键

功能都做成了可点的按钮和右键菜单，只有四个最常用的键：
⌘N 新建文稿　⌘S 保存　⌘O 导入　⌘E 导出
""", folderId: nil)
        return DocState(sheets: [s, guide], activeId: s.id).with(folders: [folder])
    }

    func with(folders: [Folder]) -> DocState {
        var copy = self
        copy.folders = folders
        copy.syncCurrentBook()
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

// MARK: - 今日写作量
//
// 做法故意很朴素：记录「今天开工时全书多少字」，之后用当前总数去减。
// 这样不用监听每一次敲键，删改也不会算错方向（删掉的字会从今日里扣回去）。

func hourKey(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH"
    return f.string(from: date)
}

func dayKey(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

func totalWords(_ doc: DocState) -> Int {
    doc.sheets.reduce(0) { $0 + statCJK($1.content) + statLatin($1.content) }
}

extension DocState {
    /// 今天写了多少字（删字会变成倒扣，最低 0）
    var todayWritten: Int {
        let base = dailyBase[dayKey()] ?? totalWords(self)
        return max(0, totalWords(self) - base)
    }

    /// 启动/跨天时补一条基线；顺手清掉两周前的记录，state.json 不至于越写越大
    mutating func ensureDailyBase() {
        let key = dayKey()
        if dailyBase[key] == nil {
            dailyBase[key] = totalWords(self)
            dailyDone[key] = 0
        }
        if dailyBase.count > 21 {
            let keep = dailyBase.keys.sorted().suffix(14)
            dailyBase = dailyBase.filter { keep.contains($0.key) }
        }
        // 成就记录留得多一些（统计要画 30 天曲线），避免和基线一起被清掉
        if dailyDone.count > 400 {
            let keep = dailyDone.keys.sorted().suffix(180)
            dailyDone = dailyDone.filter { keep.contains($0.key) }
        }
    }

    /// 每次保存时记下今天的最好成绩
    mutating func recordDaily() {
        let key = dayKey()
        if dailyBase[key] == nil { dailyBase[key] = totalWords(self) }
        dailyDone[key] = max(dailyDone[key] ?? 0, todayWritten)
    }

    /// 记一段写作时间（秒）。只保留最近 180 天，一天最多算 12 小时，
    /// 免得挂着窗口过夜把"写作时长"变成"开机时长"。
    mutating func addWriteSeconds(_ n: Int) {
        guard n > 0 else { return }
        let key = dayKey()
        let capped = min((writeSeconds[key] ?? 0) + n, 12 * 3600)
        writeSeconds[key] = capped
        if writeSeconds.count > 200 {
            let keep = writeSeconds.keys.sorted().suffix(180)
            writeSeconds = writeSeconds.filter { keep.contains($0.key) }
        }
    }

    var todaySeconds: Int { writeSeconds[dayKey()] ?? 0 }

    /// 完成一个番茄（只记"专注"结束，休息不算）
    /// 记一笔"这个小时写了多少字"
    mutating func recordHourly(_ delta: Int) {
        guard delta > 0 else { return }
        let k = hourKey()
        hourlyWords[k, default: 0] += delta
        if hourlyWords.count > 24 * 90 {
            let cutoff = dayKey(Date().addingTimeInterval(-90 * 86400))
            hourlyWords = hourlyWords.filter { $0.key >= cutoff + " 00" }
        }
    }

    /// 写作节奏：哪个小时写得最多、最快手速、峰值之后什么时候掉下来
    func rhythm() -> RhythmStats {
        var totals = [Int](repeating: 0, count: 24)
        var daysWith = [Int](repeating: 0, count: 24)
        for (k, v) in hourlyWords {
            let parts = k.split(separator: " ")
            guard parts.count == 2, let h = Int(parts[1]), h >= 0, h < 24 else { continue }
            totals[h] += v
            daysWith[h] += 1
        }
        var avgs = [Int](repeating: 0, count: 24)
        for h in 0..<24 where daysWith[h] > 0 { avgs[h] = totals[h] / daysWith[h] }
        let active = (0..<24).filter { daysWith[$0] > 0 }
        let peak = active.max { avgs[$0] < avgs[$1] } ?? 21
        let low = active.min { avgs[$0] < avgs[$1] } ?? 9
        var inflection: Int? = nil
        if avgs[peak] > 0 {
            var h = peak
            for _ in 0..<23 {
                h = (h + 1) % 24
                if daysWith[h] > 0, avgs[h] < avgs[peak] / 2 { inflection = h; break }
            }
        }
        let observed = Set(hourlyWords.keys.compactMap { $0.split(separator: " ").first.map(String.init) }).count
        return RhythmStats(totals: totals, averages: avgs, activeHours: active,
                           peakHour: peak, lowHour: low, peakAvg: avgs[peak], lowAvg: avgs[low],
                           inflectionHour: inflection, peakWPM: peakWPM, observedDays: observed)
    }

    mutating func addPomodoro() {
        let key = dayKey()
        pomodoroDone[key] = (pomodoroDone[key] ?? 0) + 1
        if pomodoroDone.count > 200 {
            let keep = pomodoroDone.keys.sorted().suffix(180)
            pomodoroDone = pomodoroDone.filter { keep.contains($0.key) }
        }
    }

    var todayPomodoros: Int { pomodoroDone[dayKey()] ?? 0 }

    /// 最近 N 天的平均写作时长（秒），只除以"有记录的天数"，不让空白天稀释
    func averageWriteSeconds(days: Int = 7) -> Int {
        let cal = Calendar.current
        var total = 0, used = 0
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let v = writeSeconds[dayKey(d)] ?? 0
            if v > 0 { total += v; used += 1 }
        }
        return used == 0 ? 0 : total / used
    }

    /// 连续达标天数（今天没达标就从昨天往回数）
    var dailyStreak: Int {
        guard dailyGoal > 0 else { return 0 }
        var streak = 0
        var cursor = Date()
        if todayWritten < dailyGoal { cursor = cursor.addingTimeInterval(-86400) }
        for _ in 0..<400 {
            let key = dayKey(cursor)
            let done = dailyDone[key] ?? 0
            if done >= dailyGoal { streak += 1; cursor = cursor.addingTimeInterval(-86400) } else { break }
        }
        return streak
    }
}

// MARK: - 人物卡片

extension DocState {
    /// 所有卡片（人物/设定）
    var cardSheets: [Sheet] { sheets.filter { $0.card != nil } }

    /// 按名字找卡片：先找卡片名字段，再退回文稿标题
    func cardSheet(named name: String) -> Sheet? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return sheets.first { s in
            guard let c = s.card else { return false }
            return c.name.trimmingCharacters(in: .whitespaces) == n || s.title == n
        }
    }

    /// 正文里这句话出现了哪些卡片名字（长的优先，避免"小明"抢了"小明妈妈"）
    func cardNamesIn(_ text: String) -> [String] {
        let names = cardSheets.compactMap { $0.card?.name.isEmpty == false ? $0.card!.name : $0.title }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        return names.filter { text.contains($0) }
    }
}

/// 一个人名在某一章里出现过几次（出场索引的一行）
struct CardMention {
    let sheetId: String
    let title: String
    let count: Int
    let firstRange: NSRange
}

extension DocState {
    /// 反向链接：这个名字在哪些正文里出现过、各出现几次。
    /// 卡片自己的备注不算「出场」，所以只扫 card == nil 的文稿。
    func mentions(of name: String) -> [CardMention] {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        var out: [CardMention] = []
        for s in sheets where s.card == nil {
            let ns = s.content as NSString
            guard ns.length > 0 else { continue }
            var count = 0
            var first = NSNotFound
            var search = NSRange(location: 0, length: ns.length)
            while search.length > 0 {
                let r = ns.range(of: key, options: [], range: search)
                if r.location == NSNotFound { break }
                if first == NSNotFound { first = r.location }
                count += 1
                let next = r.location + max(1, r.length)
                if next >= ns.length { break }
                search = NSRange(location: next, length: ns.length - next)
            }
            if count > 0 {
                out.append(CardMention(sheetId: s.id, title: s.title, count: count,
                                       firstRange: NSRange(location: first, length: key.count)))
            }
        }
        return out
    }
}

// MARK: - 写作统计

struct DayCount {
    let key: String      // 2026-11-03
    let date: Date
    let count: Int       // 那天最多写到过多少字
}

/// 写作节奏：按"一天里的第几个小时"聚合，回答"我什么时候写得动"
struct RhythmStats {
    var totals: [Int]        // 24 个整点，累计字数
    var averages: [Int]      // 24 个整点，平均每次写到多少字
    var activeHours: [Int]   // 有记录的小时
    var peakHour: Int
    var lowHour: Int
    var peakAvg: Int
    var lowAvg: Int
    var inflectionHour: Int? // 峰值之后掉到一半以下的小时
    var peakWPM: Int         // 最快手速（字/分钟）
    var observedDays: Int
}

struct WriteStats {
    var days: [DayCount] = []      // 最近 N 天，旧的在前
    var activeDays: Int = 0        // 有记录的天数（写过字）
    var longestStreak: Int = 0     // 最长连续写作天数
    var totalWords: Int = 0        // 所有记录加起来
    var monthWords: Int = 0        // 本月累计
    var maxCount: Int = 0          // 用于图表缩放的峰值
}

extension DocState {
    /// 汇总写作统计。days 控制曲线天数（30/90），其余指标始终基于全部记录。
    func writeStats(days: Int = 30) -> WriteStats {
        let cal = Calendar.current
        var stats = WriteStats()

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sortedKeys = dailyDone.keys.sorted()
        stats.activeDays = sortedKeys.filter { (dailyDone[$0] ?? 0) > 0 }.count
        stats.totalWords = dailyDone.values.reduce(0, +)
        stats.maxCount = dailyDone.values.max() ?? 0

        let monthPrefix = String(dayKey().prefix(7))
        stats.monthWords = dailyDone.filter { $0.key.hasPrefix(monthPrefix) }.values.reduce(0, +)

        // 最长连续：从最早一天顺次扫，遇到断档就结算
        var streak = 0
        var prev: Date? = nil
        for key in sortedKeys {
            guard let d = df.date(from: key), (dailyDone[key] ?? 0) > 0 else { streak = 0; prev = nil; continue }
            if let p = prev, let gap = cal.dateComponents([.day], from: p, to: d).day, gap == 1 {
                streak += 1
            } else {
                streak = 1
            }
            stats.longestStreak = max(stats.longestStreak, streak)
            prev = d
        }

        // 最近 N 天（含今天），没有记录的补 0，这样曲线不会断开
        var list: [DayCount] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let key = dayKey(d)
            list.append(DayCount(key: key, date: d, count: dailyDone[key] ?? 0))
        }
        stats.days = list
        return stats
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
    static var supportBase: URL {
        // 测试用：把「Application Support 根」也换成临时目录，才能在不碰真实数据的前提下验迁移
        if let s = ProcessInfo.processInfo.environment["LUOBI_SUPPORT"], !s.isEmpty {
            return URL(fileURLWithPath: s, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var dir: URL {
        // 测试/探针可以用环境变量把整个文稿库指到临时目录，避免碰真实数据
        let env = ProcessInfo.processInfo.environment
        if let custom = env["LUOBI_HOME"] ?? env["ULYSSES_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return supportBase.appendingPathComponent("Luobi", isDirectory: true)
    }

    /// 改名前的文稿库（Ulysses Native）。首次启动会自动搬过来，旧目录原样留着当保险。
    static var legacyDir: URL { supportBase.appendingPathComponent("UlyssesNative", isDirectory: true) }

    /// 这次启动是否发生了「旧名字 → 落笔」的搬迁，界面据此提示一句
    static var migrationNote: String? = nil

    private static func migrateIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dir.path),
              fm.fileExists(atPath: legacyDir.path) else { return }
        do {
            try fm.copyItem(at: legacyDir, to: dir)
            migrationNote = "已把旧文稿库搬进「落笔」，原来的 UlyssesNative 目录也没删"
        } catch {
            migrationNote = "旧文稿库搬迁失败，可以手动拷 ~/Library/Application Support/UlyssesNative 到 Luobi"
        }
    }
    static var file: URL { dir.appendingPathComponent("state.json") }
    /// 上一次成功保存前的旧文件，主文件坏掉时用
    static var backupFile: URL { dir.appendingPathComponent("state.json.bak") }
    /// 定时快照目录
    static var backupsDir: URL { dir.appendingPathComponent("Backups", isDirectory: true) }

    /// 手动或定时快照的间隔（秒）：自动保存很频繁，但快照不需要那么频繁
    static let snapshotInterval: TimeInterval = 300
    static let maxSnapshots = 20
    private static var lastSnapshotAt = Date.distantPast

    /// 本次启动是否发生了「主文件坏了、从备份恢复」的情况，界面据此提示
    static var lastRecoveryNote: String? = nil

    static func ensure() {
        migrateIfNeeded()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }

    static func load() -> DocState {
        ensure()
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return .initial() }
        if var fresh = try? JSONDecoder().decode(DocState.self, from: data),
           !fresh.sheets.isEmpty, fresh.sheet(id: fresh.activeId) != nil {
            fresh.ensureDailyBase()
            return fresh
        }
        if let (recovered, note) = Vault.recover() {
            Vault.lastRecoveryNote = note
            return recovered
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
            let data = try JSONEncoder().encode(doc)
            let tmp = file.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            // 覆盖前把旧文件留一份，防止新文件写坏后无处可退
            if let old = try? Data(contentsOf: file), !old.isEmpty {
                try? old.write(to: backupFile, options: .atomic)
            }
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tmp, to: file)
            maybeSnapshot(data)
            return true
        } catch {
            return false
        }
    }

    /// 每隔 snapshotInterval 存一份带时间戳的快照，最多留 maxSnapshots 份
    private static func maybeSnapshot(_ data: Data) {
        let now = Date()
        if now.timeIntervalSince(lastSnapshotAt) < snapshotInterval { return }
        lastSnapshotAt = now
        writeSnapshot(data)
    }

    /// 强制立刻存一份快照（「立即备份」按钮、退出前都可以调）
    @discardableResult
    static func snapshotNow(_ doc: DocState) -> URL? {
        ensure()
        guard let data = try? JSONEncoder().encode(doc) else { return nil }
        lastSnapshotAt = Date()
        return writeSnapshot(data)
    }

    @discardableResult
    private static func writeSnapshot(_ data: Data) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "state-\(f.string(from: Date())).json"
        let url = backupsDir.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        rotateSnapshots()
        return url
    }

    struct BackupEntry {
        let url: URL
        let date: Date
        let sheetCount: Int
        var title: String {
            let df = DateFormatter()
            df.dateFormat = "M月d日 HH:mm"
            return "\(df.string(from: date))　\(sheetCount) 篇"
        }
    }

    /// 所有可用快照，新的排前面
    static func listBackups() -> [BackupEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: backupsDir.path) else { return [] }
        var out: [BackupEntry] = []
        for n in names where n.hasPrefix("state-") && n.hasSuffix(".json") {
            let url = backupsDir.appendingPathComponent(n)
            guard let data = try? Data(contentsOf: url),
                  let doc = try? JSONDecoder().decode(DocState.self, from: data) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            out.append(BackupEntry(url: url, date: date, sheetCount: doc.sheets.count))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func restore(from url: URL) -> DocState? {
        guard let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(DocState.self, from: data),
              !doc.sheets.isEmpty else { return nil }
        return doc
    }

    private static func rotateSnapshots() {
        // 按文件本身轮转（不依赖能不能解析），这样坏掉的快照也会被清出去
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: backupsDir.path) else { return }
        var files: [(URL, Date)] = []
        for n in names where n.hasPrefix("state-") && n.hasSuffix(".json") {
            let url = backupsDir.appendingPathComponent(n)
            let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            files.append((url, d ?? Date.distantPast))
        }
        if files.count <= maxSnapshots { return }
        let sorted = files.sorted { $0.1 > $1.1 }
        for f in sorted[maxSnapshots...] { try? fm.removeItem(at: f.0) }
    }

    /// 文件坏了也不至于丢光：主文件 → .bak → 最新快照
    static func recover() -> (DocState, String)? {
        if let data = try? Data(contentsOf: backupFile),
           let doc = try? JSONDecoder().decode(DocState.self, from: data), !doc.sheets.isEmpty {
            return (doc, "主文件读取失败，已从上一版本（state.json.bak）恢复")
        }
        if let newest = listBackups().first, let doc = restore(from: newest.url) {
            return (doc, "主文件与上一版本都不可用，已从 \(newest.title) 的快照恢复")
        }
        return nil
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
