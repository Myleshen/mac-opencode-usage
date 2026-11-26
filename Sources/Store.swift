import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var data: UsageData?
    @Published var error: String?
    @Published var busy = false
    // Release tag newer than this build, if GitHub reports one.
    @Published var latestVersion: String?

    private var timer: Timer?

    var refreshMinutes: Int {
        max(1, UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 60)
    }



    var warning: Double {
        Double(UserDefaults.standard.object(forKey: "warning") as? Int ?? 80) / 100
    }

    var critical: Double {
        Double(UserDefaults.standard.object(forKey: "critical") as? Int ?? 95) / 100
    }

    init() {
        schedule()
        Task { await refresh() }
        checkForUpdate()
    }

    // Cheap honesty about updates: `brew upgrade` does nothing for a
    // `version :latest` cask, so the footer has to say when one exists.
    func checkForUpdate() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }
        defaults.set(Date(), forKey: "lastUpdateCheck")

        Task {
            guard let tag = await UpdateCheck.fetchLatest() else { return }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            latestVersion = UpdateCheck.newer(latest: tag, current: current) ? tag : nil
        }
    }

    func schedule() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Double(refreshMinutes) * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        // The credential spawns a process and the JSON parsing is synchronous, so
        // both fetch and the limits cache run off the main thread; only the
        // published results come back here.
        let result: Result<UsageData, Error> = await Task.detached {
            // Model limits come from the public model list; the daily cache keeps this cheap.
            await Limits.refreshIfStale()
            do {
                return .success(try await Usage.fetch())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let data):
            self.data = data
            error = nil
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }

    func refreshIfStale() {
        if let data, Date().timeIntervalSince(data.updatedAt) < 60 { return }
        Task { await refresh() }
    }

    func settingsChanged() {
        schedule()
        Task { await refresh() }
    }
}
