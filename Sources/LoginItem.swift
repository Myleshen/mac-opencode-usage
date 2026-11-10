import Foundation

// LaunchAgent instead of SMAppService: the app is locally built and ad-hoc
// signed, where SMAppService silently fails outside /Applications.
enum LoginItem {
    // Follows the bundle id, so a debug build registers its own agent and
    // cannot repoint the install's login item.
    static let label = Bundle.main.bundleIdentifier ?? "dev.myleshen.opencode-usage"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var enabled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // A rebuild or a move leaves the plist pointing at a path that no longer
    // exists, so fix it on launch instead of silently losing the login item.
    static func repair() {
        guard enabled,
              let path = Bundle.main.executableURL?.path,
              let plist = NSDictionary(contentsOf: url) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              arguments.first != path else { return }
        try? set(true)
    }

    static func set(_ on: Bool) throws {
        if on {
            // Drop any stale registration first, then write and register. The
            // bootstrap starts a second copy, which the app's startup dedupe
            // exits immediately; registering is what makes it a real login item.
            launchctl(["bootout", "gui/\(getuid())/\(label)"])
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [Bundle.main.executableURL?.path ?? CommandLine.arguments[0]],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            launchctl(["bootstrap", "gui/\(getuid())", url.path])
        } else {
            // Target the job by label: it stays loaded after the plist is removed.
            launchctl(["bootout", "gui/\(getuid())/\(label)"])
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func launchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        // Wait: bootstrap must finish before the caller reports the state.
        try? process.run()
        process.waitUntilExit()
    }
}
