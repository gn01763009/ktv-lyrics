import AppKit
import os
import UniformTypeIdentifiers

/// Lets the user choose a `.lrc` file and hands its text to the coordinator.
@MainActor
struct LRCImportPicker {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "LRCImportPicker")

    let coordinator: AppCoordinator

    func run() {
        let panel = NSOpenPanel()
        panel.title = "匯入 .lrc"
        panel.prompt = "匯入"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc"), .plainText].compactMap { $0 }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            coordinator.importLRC(try LRCFileReader.read(url))
        } catch {
            Self.logger.error("Could not import \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            coordinator.postNotice("♪ 匯入失敗：\(error.localizedDescription)")
        }
    }
}
