import Foundation
import AppKit
import WebKit
import Network

// MARK: - 目录与资源

let fm = FileManager.default
let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("UlyssesLite", isDirectory: true)
let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("UlyssesLite", isDirectory: true)
let stateURL = supportDir.appendingPathComponent("state.json")

var htmlBytes = Data()

// MARK: - 导出

func writeExport(text: String, suggested: String?) -> String {
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
    try? Data(text.utf8).write(to: url, options: .atomic)
    return url.path
}

// MARK: - 本地 HTTP 服务（只监听 127.0.0.1）

final class Server {
    let candidates: [UInt16] = [57321, 57322, 57323, 57324, 57325, 57326, 57327]
    var listener: NWListener?
    var portCallback: ((UInt16?) -> Void)?
    var readyPort: UInt16?

    func start(_ cb: @escaping (UInt16?) -> Void) {
        portCallback = cb
        tryCandidate(0)
    }

    func tryCandidate(_ i: Int) {
        guard i < candidates.count else {
            DispatchQueue.main.async { self.portCallback?(nil) }
            return
        }
        let p = candidates[i]
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: p)!) else {
            tryCandidate(i + 1)
            return
        }
        self.listener = l
        l.newConnectionHandler = { [weak self] c in
            let conn = ClientConn(c)
            conn.start()
        }
        l.stateUpdateHandler = { [weak self, weak l] state in
            switch state {
            case .setup:
                break
            case .ready:
                print("server ready on port \(p)")
                self?.readyPort = p
                DispatchQueue.main.async { self?.portCallback?(p) }
            case .waiting(let err):
                print("server waiting on \(p): \(err)")
            case .failed(let err):
                print("server failed on \(p): \(err)")
                l?.cancel()
                self?.tryCandidate(i + 1)
            case .setup, .cancelled:
                break
            @unknown default:
                break
            }
        }
        l.start(queue: DispatchQueue.global(qos: .userInitiated))
    }
}

final class ClientConn {
    let nc: NWConnection
    var buf = Data()

    struct Request {
        var method = ""
        var path = ""
        var body = Data()
    }

    init(_ nc: NWConnection) { self.nc = nc }

    func start() {
        nc.start(queue: DispatchQueue.global(qos: .userInitiated))
        recv()
    }

    func recv() {
        nc.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let d = data, !d.isEmpty { self.buf.append(d) }
            if let req = self.parse() { self.reply(req); return }
            if isComplete || error != nil { self.nc.cancel(); return }
            if self.buf.count > 32 << 20 { self.nc.cancel(); return }
            self.recv()
        }
    }

    func parse() -> Request? {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return nil }
        var req = Request()
        let lines = head.components(separatedBy: "\r\n")
        if let first = lines.first {
            let parts = first.split(separator: " ")
            if parts.count >= 2 {
                req.method = String(parts[0]).uppercased()
                var path = String(parts[1])
                if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
                req.path = path
            }
        }
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2,
               kv[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard contentLength >= 0, contentLength <= 32 << 20 else { return nil }
        let bodyStart = headerEnd.upperBound
        guard buf.count - bodyStart >= contentLength else { return nil }
        if contentLength > 0 {
            req.body = buf.subdata(in: bodyStart..<(bodyStart + contentLength))
        }
        return req
    }

    func reply(_ req: Request) {
        var status = "200 OK"
        var ctype = "text/html; charset=utf-8"
        var body = htmlBytes
        var noStore = false

        switch (req.method, req.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            break
        case ("GET", "/api/state"):
            ctype = "application/json; charset=utf-8"
            body = (try? Data(contentsOf: stateURL)) ?? Data()
            if body.isEmpty { body = Data("null".utf8) }
            noStore = true
        case ("POST", "/api/state"):
            ctype = "application/json"
            noStore = true
            if let obj = try? JSONSerialization.jsonObject(with: req.body) {
                let back = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
                if let stable = back {   // 归一化后写盘，避免客户端发来半残 JSON
                    let tmp = stateURL.appendingPathExtension("tmp")
                    try? stable.write(to: tmp, options: .atomic)
                    try? fm.removeItem(at: stateURL)
                    try? fm.moveItem(at: tmp, to: stateURL)
                }
                body = Data(#"{"ok":true}"#.utf8)
            } else {
                status = "400 Bad Request"
                body = Data(#"{"ok":false}"#.utf8)
            }
        case ("POST", "/api/export"):
            ctype = "application/json"
            noStore = true
            if let obj = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
               let text = obj["text"] as? String {
                let path = writeExport(text: text, suggested: obj["filename"] as? String)
                body = (try? JSONSerialization.data(withJSONObject: ["ok": true, "path": path])) ?? Data("{}".utf8)
            } else {
                status = "400 Bad Request"
                body = Data(#"{"ok":false}"#.utf8)
            }
        default:
            status = "404 Not Found"
            ctype = "text/plain; charset=utf-8"
            body = Data("not found".utf8)
        }

        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if noStore { head += "Cache-Control: no-store\r\n" }
        head += "\r\n"
        var raw = Data(head.utf8)
        raw.append(body)
        nc.send(content: raw, completion: .contentProcessed { [weak self] _ in
            self?.nc.cancel()
        })
    }
}

// MARK: - 窗口与应用

func menuitem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
    i.target = nil
    return i
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow?
    var webView: WKWebView?
    var server = Server()

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()

        let rect = NSRect(x: 0, y: 0, width: 1180, height: 800)
        let win = NSWindow(contentRect: rect,
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Ulysses Lite"
        win.minSize = NSSize(width: 720, height: 480)
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: rect, configuration: config)
        wv.uiDelegate = self
        win.contentView = wv
        let _ = win.setFrameAutosaveName("UlyssesLiteMain")
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.webView = wv

        server.start { [weak self] port in
            guard let self = self, let p = port else {
                let a = NSAlert()
                a.messageText = "本地服务启动失败"
                a.informativeText = "57321–57327 端口都被占用了。"
                a.runModal()
                NSApp.terminate(nil)
                return
            }
            if let url = URL(string: "http://127.0.0.1:\(p)/") {
                self.webView?.load(URLRequest(url: url))
            }
            NSApp.activate(ignoringOtherApps: true)
        }
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

if let res = Bundle.main.resourceURL {
    htmlBytes = (try? Data(contentsOf: res.appendingPathComponent("index.html"))) ?? Data()
}
if htmlBytes.isEmpty {
    htmlBytes = fm.contents(atPath: "ulysses-lite.html") ?? Data()
}
if htmlBytes.isEmpty {
    let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
    htmlBytes = (try? Data(contentsOf: exeDir.appendingPathComponent("index.html"))) ?? Data()
}
if htmlBytes.isEmpty {
    print("找不到 index.html")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
