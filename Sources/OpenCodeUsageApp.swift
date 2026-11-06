import AppKit
import SwiftUI

@main
struct OpenCodeUsageApp: App {
    @StateObject private var store = Store()

    init() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        if CommandLine.arguments.contains("--dump") { Self.dump() }
        if CommandLine.arguments.contains("--limits") { Self.limits() }

        // Headless update check, for support: ./OpenCodeUsage --update
        if CommandLine.arguments.contains("--update") { Self.update() }

        // Headless switch for the login item: ./OpenCodeUsage --loginitem on|off
        if let i = CommandLine.arguments.firstIndex(of: "--loginitem"),
           CommandLine.arguments.count > i + 1 {
            let on = CommandLine.arguments[i + 1] == "on"
            try? LoginItem.set(on)
            print("login item \(LoginItem.enabled ? "on" : "off")")
            exit(0)
        }

        // Launching twice (login item plus a manual open) would show two menu bar
        // items that refresh independently. Only the first instance survives.
        if !InstanceLock.acquire() { exit(0) }

        LoginItem.repair()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    // opencode's own usage route, the one the desktop app uses. It answers null
    // until a console workspace is linked to the local app, so this exists to
    // check availability before the console API can be retired.
    private static func limits() -> Never {
        guard let cli = Usage.opencodeCLI() else {
            print("opencode CLI not found")
            exit(1)
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["api", "GET", "/api/experimental/usage/limits"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try? process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        print(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        exit(0)
    }

    private static func update() -> Never {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Task.detached {
            guard let tag = await UpdateCheck.fetchLatest() else {
                print("v\(current) · could not reach GitHub")
                exit(1)
            }
            print(UpdateCheck.newer(latest: tag, current: current)
                  ? "v\(current) · \(tag) available (brew reinstall --cask opencode-usage)"
                  : "v\(current) · up to date")
            exit(0)
        }
        RunLoop.main.run()
        exit(1)
    }

    // Verifies the whole fetch path without a GUI: ./OpenCodeUsage --dump
    private static func dump() -> Never {
        Task.detached {
            await Limits.refreshIfStale()
            do {
                let data = try await Usage.fetch()
                print(Usage.describe(data))
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(1)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @AppStorage("barFive") private var barFive = true
    @AppStorage("barWeek") private var barWeek = true
    @AppStorage("barMonth") private var barMonth = true
    @AppStorage("barCredits") private var barCredits = false

    var body: some View {
        let segments = self.segments
        HStack(spacing: 4) {
            // Same needle-gauge motif as the app icon; custom shapes do not
            // render inside a MenuBarExtra label.
            Image(systemName: segments.risk ? "exclamationmark.triangle.fill" : "gauge.with.needle")
            Text(segments.text)
        }
    }

    // Always prefixed so a single visible number cannot be misread: H = 5-hour,
    // W = week, M = month, C = available credits.
    private var segments: (text: String, risk: Bool) {
        guard let data = store.data else { return ("—", false) }

        var picked: [(String, String)] = []
        var risks: [Double] = []

        func add(_ label: String, _ period: Period) {
            let pct = Usage.top(data, period)?.pct
            picked.append((label, pct.map(Usage.percent) ?? "—"))
            if let pct { risks.append(pct) }
        }

        if barFive { add("H", .five) }
        if barWeek { add("W", .week) }
        if barMonth { add("M", .month) }
        // Credits keep their own format: the used percentage when the purchase
        // history allows one, otherwise the available balance. They never feed
        // the critical-usage triangle, which is about Go allowances.
        if barCredits {
            let used = data.credits?.usedFraction.map(Usage.percent)
            let available = data.credits.map { Usage.money($0.available) }
            picked.append(("C", used ?? available ?? "—"))
        }
        if picked.isEmpty { add("H", .five) }

        let risk = risks.contains { $0 >= store.critical }
        let text = picked.map { "\($0.0) \($0.1)" }.joined(separator: " ")
        return (text, risk)
    }
}

