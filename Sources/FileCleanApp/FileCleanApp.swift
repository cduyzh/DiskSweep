import SwiftUI
import AppKit

@main
struct FileCleanApp: App {
    @StateObject private var store = FileCleanStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("DiskSweep", id: "main") {
            GeometryReader { geometry in
                WorkspaceView().environmentObject(store)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
                .preferredColorScheme(store.colorScheme)
                .tint(Palette.accent)
                .frame(minWidth: 1080, minHeight: 700)
                .onAppear {
                    delegate.configure(store: store)
                    store.refreshVolumes()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.navigate(.settings) }.keyboardShortcut(",")
            }
            CommandGroup(after: .toolbar) {
                Button(store.scanning ? "取消扫描" : "扫描用户目录") {
                    if store.scanning { store.cancelScan() } else { store.startScan() }
                }.keyboardShortcut("r")
                Button("重复文件检测") { store.runDuplicateScan() }
                    .disabled(store.result == nil || store.duplicatesStage.isRunningLike)
                Divider()
                Button("显示 / 隐藏详情") { store.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("搜索") { NotificationCenter.default.post(name: .focusFileCleanSearch, object: nil) }.keyboardShortcut("f")
            }
            CommandGroup(replacing: .saveItem) {
                Button("导出当前清单…") { store.exportCSV() }.keyboardShortcut("s")
                    .disabled(store.page != .large && store.page != .duplicates)
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 DiskSweep") { store.navigate(.settings) }
                Button("更新历史…") { store.showReleaseHistory = true }
            }
        }
    }
}

extension Notification.Name { static let focusFileCleanSearch = Notification.Name("fileClean.focusSearch") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: FileCleanStore?

    func configure(store: FileCleanStore) {
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }
}
