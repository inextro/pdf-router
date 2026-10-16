// PDFRouter: PDF 기본 앱 자리에 앉아, 파일 경로를 보고 열 앱을 골라 넘긴 뒤 바로 종료한다.
// Zotero 첨부 폴더와 사용자가 고른 폴더 아래의 PDF는 PaperMark로, 나머지는 Preview로 연다.
// 파일 없이 직접 실행하면 폴더를 고르는 설정 창을 띄운다.
import AppKit
import SwiftUI

let paperMarkCandidates = ["~/Applications/PaperMark.app", "/Applications/PaperMark.app"]
let fallbackApp = URL(fileURLWithPath: "/System/Applications/Preview.app")
let foldersKey = "paperFolders"

/// 틸드를 펼치고 심링크를 풀어, `~/Google Drive/...`처럼 다른 경로로 들어와도 같은 문자열이 되게 한다.
func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
}

/// Zotero 프로필의 prefs.js에서 첨부 파일이 놓이는 폴더를 읽는다.
/// - `baseAttachmentPath`: 링크 첨부의 기준 폴더(예: Google Drive 안의 zotero 폴더)
/// - `dataDir`/storage: Zotero가 직접 저장한 첨부(설정이 없으면 ~/Zotero)
func zoteroAttachmentRoots() -> [String] {
    let profiles = URL(fileURLWithPath: canonicalPath("~/Library/Application Support/Zotero/Profiles"))
    let dirs = (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? []
    var roots: [String] = []
    var dataDir = "~/Zotero"
    for dir in dirs {
        guard let prefs = try? String(contentsOf: dir.appendingPathComponent("prefs.js"), encoding: .utf8) else { continue }
        if let base = pref("extensions.zotero.baseAttachmentPath", in: prefs) { roots.append(base) }
        if let value = pref("extensions.zotero.dataDir", in: prefs) { dataDir = value }
    }
    roots.append(dataDir + "/storage")
    return roots.map(canonicalPath)
}

/// `user_pref("key", "value");` 한 줄에서 문자열 값을 꺼낸다. 값은 JSON 문자열 규칙으로 이스케이프돼 있다.
func pref(_ key: String, in prefs: String) -> String? {
    let pattern = #"user_pref\("\#(NSRegularExpression.escapedPattern(for: key))",\s*("(?:[^"\\]|\\.)*")\);"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: prefs, range: NSRange(prefs.startIndex..., in: prefs)),
          let range = Range(match.range(at: 1), in: prefs) else { return nil }
    return try? JSONDecoder().decode(String.self, from: Data(prefs[range].utf8))
}

/// 설정 창에서 사용자가 고른 폴더. UserDefaults(com.inextro.pdfrouter)에 저장한다.
var chosenFolders: [String] {
    get { UserDefaults.standard.stringArray(forKey: foldersKey) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: foldersKey) }
}

let paperMarkApp = paperMarkCandidates.map(canonicalPath).first(where: FileManager.default.fileExists(atPath:))
    .map { URL(fileURLWithPath: $0) }

func app(for file: URL, paperRoots: [String]) -> URL {
    let path = canonicalPath(file.path)
    let isPaper = paperRoots.contains { path.hasPrefix($0 + "/") }
    return isPaper ? (paperMarkApp ?? fallbackApp) : fallbackApp
}

/// 설정 창의 상태. Command Line Tools에는 SwiftUI 매크로 플러그인이 없어 `@State` 대신 ObservableObject를 쓴다.
final class FolderList: ObservableObject {
    @Published var folders = chosenFolders {
        didSet { chosenFolders = folders }
    }
    @Published var selection = Set<String>()
}

struct SettingsView: View {
    @StateObject private var model = FolderList()
    private let zoteroFolders = zoteroAttachmentRoots()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PDFs inside these folders open in PaperMark. Every other PDF opens in Preview.")
            if paperMarkApp == nil {
                Text("PaperMark is not installed, so every PDF opens in Preview for now.")
                    .foregroundStyle(.orange)
            }
            List(selection: $model.selection) {
                Section("Your folders") {
                    if model.folders.isEmpty {
                        Text("Click Add Folder… to choose one.").foregroundStyle(.secondary)
                    }
                    ForEach(model.folders, id: \.self) { folder in
                        Label(displayPath(folder), systemImage: "folder").tag(folder)
                    }
                }
                Section("Zotero attachment folders (found automatically)") {
                    ForEach(zoteroFolders, id: \.self) { folder in
                        Label(displayPath(folder), systemImage: "books.vertical").foregroundStyle(.secondary)
                    }
                }
            }
            .onDeleteCommand(perform: removeSelected)
            HStack {
                Button("Add Folder…", action: addFolders)
                Button("Remove", action: removeSelected).disabled(model.selection.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }

    private func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !model.folders.contains(url.path) {
            model.folders.append(url.path)
        }
    }

    private func removeSelected() {
        model.folders.removeAll(where: model.selection.contains)
        model.selection.removeAll()
    }
}

final class Router: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var pending = 0
    private var quitTimer: Timer?
    private var receivedFiles = false
    private var settingsWindow: NSWindow?

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        quitTimer?.invalidate()
        // 설정 창에서 폴더를 바꾼 직후에도 맞게 보내도록 폴더 목록은 요청마다 새로 읽는다.
        let paperRoots = zoteroAttachmentRoots() + chosenFolders.map(canonicalPath)
        for (target, files) in Dictionary(grouping: urls, by: { app(for: $0, paperRoots: paperRoots) }) {
            pending += 1
            NSWorkspace.shared.open(files, withApplicationAt: target, configuration: .init()) { _, error in
                if let error { NSLog("PDFRouter: \(target.lastPathComponent) 열기 실패: \(error)") }
                DispatchQueue.main.async { [self] in
                    pending -= 1
                    scheduleQuit()
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 파일과 함께 실행되면 application(_:open:)이 먼저 불린다. 파일 없이 실행됐으면(앱을 직접 더블클릭) 설정 창을 띄운다.
        if !receivedFiles { showSettings() }
        scheduleQuit()
    }

    /// 종료를 기다리는 동안 앱을 다시 실행하면 새 프로세스 대신 이쪽으로 온다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        scheduleQuit()
    }

    private func showSettings() {
        quitTimer?.invalidate()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "PDFRouter"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
            // 평소에는 Dock 아이콘 없이 돌지만, 창을 띄울 때는 일반 앱처럼 보여야 ⌘W, ⌘Q가 먹는다.
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = makeMainMenu()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PDFRouter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let mainMenu = NSMenu()
        for submenu in [appMenu, fileMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    /// 넘길 파일이 남아 있지 않고 설정 창도 닫혀 있으면 잠시 뒤 종료한다. 연달아 열기 요청이 오면 종료 중인
    /// 프로세스로 들어가 버려지므로, 바로 끝내지 않고 그동안 새 요청이 오면 타이머를 다시 맞춘다.
    private func scheduleQuit() {
        guard pending == 0, settingsWindow == nil else { return }
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in NSApp.terminate(nil) }
    }
}

let router = Router()
NSApplication.shared.delegate = router
NSApplication.shared.run()
