// PDFRouter: PDF 기본 앱 자리에 앉아, 파일 경로를 보고 열 앱을 골라 넘긴 뒤 바로 종료한다.
// Zotero 첨부 폴더 아래의 PDF는 PaperMark로, 나머지는 Preview로 연다.
import AppKit

let paperMarkCandidates = ["~/Applications/PaperMark.app", "/Applications/PaperMark.app"]
let fallbackApp = URL(fileURLWithPath: "/System/Applications/Preview.app")

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

let paperRoots = zoteroAttachmentRoots()
let paperMarkApp = paperMarkCandidates.map(canonicalPath).first(where: FileManager.default.fileExists(atPath:))
    .map { URL(fileURLWithPath: $0) }

func app(for file: URL) -> URL {
    let path = canonicalPath(file.path)
    let isPaper = paperRoots.contains { path.hasPrefix($0 + "/") }
    return isPaper ? (paperMarkApp ?? fallbackApp) : fallbackApp
}

final class Router: NSObject, NSApplicationDelegate {
    private var pending = 0
    private var quitTimer: Timer?

    func application(_ application: NSApplication, open urls: [URL]) {
        quitTimer?.invalidate()
        for (target, files) in Dictionary(grouping: urls, by: app(for:)) {
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
        // 파일 없이 실행됐으면(앱을 직접 더블클릭) 할 일이 없으니 이대로 끝난다.
        scheduleQuit()
    }

    /// 넘길 파일이 남아 있지 않으면 잠시 뒤 종료한다. 연달아 열기 요청이 오면 종료 중인 프로세스로
    /// 들어가 버려지므로, 바로 끝내지 않고 그동안 새 요청이 오면 타이머를 다시 맞춘다.
    private func scheduleQuit() {
        guard pending == 0 else { return }
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in NSApp.terminate(nil) }
    }
}

let router = Router()
NSApplication.shared.delegate = router
NSApplication.shared.run()
