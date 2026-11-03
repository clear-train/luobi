import Foundation
import AppKit
import WebKit

// MARK: - 目录与资源

let fm = FileManager.default
let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("UlyssesLite", isDirectory: true)
let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("UlyssesLite", isDirectory: true)
let stateURL = supportDir.appendingPathComponent("state.json")

// MARK: - 导出落盘

func writeExport(text: String, suggested: String?) -> String? {
    var name = suggested ?? "导出.md"
    let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
    name = name.components(separatedBy: bad).joined(separator: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { name = "导出.md" }
    if !(name.hasSuffix(".md") || name.hasSuffix(".markdown")) { name += ".md" }
    var url = docsDir.appendingPathComponent(name)
    var n = 2
    while fm.fileExists(atPath: url.path) {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        url = docsDir.appendingPathComponent("\(stem)-\(n).\(ext)")
        n += 1
        if n > 99 { break }
    }
    do {
        try Data(text.utf8).write(to: url, options: .atomic)
        return url.path
    } catch {
        return nil
    }
}

// MARK: - 文稿库读写

func readStateJSON() -> String {
    (try? String(contentsOf: stateURL, encoding: .utf8)) ?? "null"
}

func writeStateJSON(_ text: String) -> Bool {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) else { return false }
    let stable = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? data
    let tmp = stateURL.appendingPathExtension("tmp")
    do {
        try stable.write(to: tmp, options: .atomic)
        try? fm.removeItem(at: stateURL)
        try fm.moveItem(at: tmp, to: stateURL)
        return true
    } catch {
        return false
    }
}

// MARK: - 原生桥（网页 ↔ Swift，不走任何端口）

/// 网页侧通过 window.webkit.messageHandlers.bridge.postMessage 与这里通信。
/// 消息体统一为 { type: 'save' | 'export', payload: String }，payload 是 JSON 字符串。
final class Bridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge" else { return }
        let body = message.body as? [String: Any]

        switch body?["type"] as? String {
        case "save":
            let ok = writeStateJSON(body?["payload"] as? String ?? "")
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(
                    "window.__onSaved && window.__onSaved(\(ok))", completionHandler: nil)
            }

        case "export":
            var path: String?
            if let payload = body?["payload"] as? String,
               let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["text"] as? String {
                path = writeExport(text: text, suggested: obj["filename"] as? String)
            }
            // 把 {path: ...} 以 JSON 对象字面量回传（JSON 是合法 JS 表达式）
            var jsonSource = "null"
            if path != nil,
               let data = try? JSONSerialization.data(withJSONObject: ["path": path!]),
               let str = String(data: data, encoding: .utf8) {
                jsonSource = str
            }
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(
                    "window.__onExported && window.__onExported(\(jsonSource))",
                    completionHandler: nil)
            }

        default:
            break
        }
    }
}

// MARK: - 菜单

func menuitem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
    i.target = nil
    return i
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow?
    var webView: WKWebView?

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()

        guard let res = Bundle.main.resourceURL,
              fm.fileExists(atPath: res.appendingPathComponent("index.html").path) else {
            let a = NSAlert()
            a.messageText = "找不到 index.html"
            a.informativeText = "请直接运行 build/UlyssesLite.app，不要单独启动可执行文件。"
            a.runModal()
            NSApp.terminate(nil)
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 1180, height: 800)
        let win = NSWindow(contentRect: rect,
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Ulysses Lite"
        win.minSize = NSSize(width: 720, height: 480)

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        // 启动数据随第一次渲染注入，网页侧不再需要任何网络请求
        let bootJSON = readStateJSON()
        ucc.addUserScript(WKUserScript(
            source: "window.__BOOT_STATE = \(bootJSON);",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let bridge = Bridge()
        ucc.add(bridge, name: "bridge")
        config.userContentController = ucc

        let wv = WKWebView(frame: rect, configuration: config)
        wv.uiDelegate = self
        let _ = win.setFrameAutosaveName("UlyssesLiteMain")
        win.center()
        win.contentView = wv
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.webView = wv
        bridge.webView = wv

        wv.loadFileURL(res.appendingPathComponent("index.html"), allowingReadAccessTo: res)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()

        let appRoot = NSMenuItem()
        main.addItem(appRoot)
        let appMenu = NSMenu()
        appRoot.submenu = appMenu
        appMenu.addItem(menuitem("关于 Ulysses Lite",
                                 #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(menuitem("隐藏 Ulysses Lite", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(menuitem("退出 Ulysses Lite", #selector(NSApplication.terminate(_:)), "q"))

        let editRoot = NSMenuItem()
        main.addItem(editRoot)
        let editMenu = NSMenu(title: "编辑")
        editRoot.submenu = editMenu
        editMenu.autoenablesItems = false
        editMenu.addItem(menuitem("撤销", Selector(("undo:")), "z"))
        editMenu.addItem(menuitem("重做", Selector(("redo:")), "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(menuitem("剪切", Selector(("cut:")), "x"))
        editMenu.addItem(menuitem("拷贝", Selector(("copy:")), "c"))
        editMenu.addItem(menuitem("粘贴", Selector(("paste:")), "v"))
        editMenu.addItem(menuitem("全选", Selector(("selectAll:")), "a"))

        let winRoot = NSMenuItem()
        main.addItem(winRoot)
        let winMenu = NSMenu(title: "窗口")
        winRoot.submenu = winMenu
        winMenu.addItem(menuitem("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"))
        winMenu.addItem(menuitem("关闭", #selector(NSWindow.performClose(_:)), "w"))

        NSApp.mainMenu = main
    }

    // 支持网页里 <input type=file> 导入 .md
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.allowedFileTypes = ["md", "markdown", "txt"]
        panel.begin { resp in
            completionHandler(resp == .OK ? panel.urls : nil)
        }
    }
}

// MARK: - 启动

do {
    try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
} catch {
    print("目录创建失败: \(error)")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
