import Foundation
import AppKit

@MainActor
enum CLIInstallerService {
    /// Returns the path to the bundled CLI executable inside Connection Watch.app/Contents/MacOS/connection-watch
    static var bundledCLIPath: String {
        let macOSDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let candidate = macOSDir.appendingPathComponent("connection-watch").path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        // Fallback if running in test environment or symlinked
        let localBin = TelemetryStore.installedCLISymlinkURL.path
        if FileManager.default.fileExists(atPath: localBin) {
            return localBin
        }
        return candidate
    }

    /// Best CLI path to display to the user / AI agent
    static var preferredCLIPathForAgent: String {
        let localBin = TelemetryStore.installedCLISymlinkURL.path
        if FileManager.default.fileExists(atPath: localBin) {
            return localBin
        }
        return bundledCLIPath
    }

    /// Automatically creates/updates `~/.local/bin/connection-watch` symlink pointing to the bundled CLI binary.
    @discardableResult
    static func installSymlinkIfNeeded() -> Bool {
        let sourcePath = bundledCLIPath
        guard FileManager.default.fileExists(atPath: sourcePath) else { return false }

        let fm = FileManager.default
        let targetURL = TelemetryStore.installedCLISymlinkURL
        let binDir = targetURL.deletingLastPathComponent()

        do {
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: targetURL.path) || (try? fm.destinationOfSymbolicLink(atPath: targetURL.path)) != nil {
                try? fm.removeItem(at: targetURL)
            }
            try fm.createSymbolicLink(atPath: targetURL.path, withDestinationPath: sourcePath)

            // Also attempt /usr/local/bin/connection-watch if /usr/local/bin is writable
            let usrLocalURL = URL(fileURLWithPath: "/usr/local/bin/connection-watch")
            if fm.isWritableFile(atPath: "/usr/local/bin") {
                if fm.fileExists(atPath: usrLocalURL.path) || (try? fm.destinationOfSymbolicLink(atPath: usrLocalURL.path)) != nil {
                    try? fm.removeItem(at: usrLocalURL)
                }
                try? fm.createSymbolicLink(atPath: usrLocalURL.path, withDestinationPath: sourcePath)
            }
            return true
        } catch {
            return false
        }
    }

    /// Copies the complete AI Agent Skill Markdown to the macOS clipboard.
    static func copyAgentSkillToClipboard() {
        installSymlinkIfNeeded()
        let markdown = AgentSkillGenerator.generateSkillMarkdown(cliPath: bundledCLIPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }
}
