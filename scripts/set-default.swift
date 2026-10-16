// 사용법: swift scripts/set-default.swift <앱 경로>  — 그 앱을 PDF 기본 앱으로 지정한다.
// duti(LSSetDefaultRoleHandlerForContentType)는 이 macOS에서 오류 없이 무시되므로 NSWorkspace API를 쓴다.
import AppKit
import UniformTypeIdentifiers
let app = URL(fileURLWithPath: CommandLine.arguments[1])
var done = false
NSWorkspace.shared.setDefaultApplication(at: app, toOpen: UTType.pdf) { error in
    print(error.map { "error: \($0)" } ?? "ok")
    done = true
}
while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
print(NSWorkspace.shared.urlForApplication(toOpen: UTType.pdf)?.path ?? "nil")
