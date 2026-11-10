import Foundation

// One menu bar item per user, even when two copies of the app exist (the
// /Applications install and a build under ~/dev). The bundle-id check could not
// see the other copy because LaunchServices keys apps by path, so this is an
// exclusive flock the kernel releases when the process dies.
enum InstanceLock {
    private static var descriptor: Int32 = -1

    static func acquire() -> Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // One lock per bundle id, so a debug build and the install can run at
        // once; the install keeps its old file name to still see older copies.
        let id = Bundle.main.bundleIdentifier ?? ""
        let name = id == "dev.myleshen.opencode-usage" ? "OpenCodeUsage" : "OpenCodeUsage-\(id)"
        let path = directory.appendingPathComponent("\(name).lock").path
        descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        // Fail open: a broken lock must not make the app unlaunchable.
        guard descriptor >= 0 else { return true }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
}
