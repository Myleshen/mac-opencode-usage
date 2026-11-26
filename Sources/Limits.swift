import Foundation

// The Go model limits come from the public model list and move when OpenCode
// ships models, so they are fetched and cached instead of compiled in. The
// bundled table is the fallback when the list is unreachable or restructured;
// a model missing from both has no percentage, only spend.
enum Limits {
    // Bundled fallback: the Go plan's monthly limit per model, in dollars.
    static let bundled: [String: Double] = [
        "glm-5.3-flash": 60,
        "glm-5.3": 15,
        "glm-5.2": 60,
        "kimi-k3.1-pro": 15,
        "kimi-k3": 15,
        "kimi-k2.7-code": 60,
        "longcat-2.0": 60,
        "step-5-preview": 15,
        "mimo-v2.6-flash": 60,
        "mimo-v2.6-pro": 15,
        "mimo-v2.5": 60,
        "mimo-v2.5-pro": 15,
        "minimax-m3.1-flash": 20,
        "minimax-m3": 60,
        "muse-spark-1.3-contributor": 60,
        "muse-spark-1.2-contributor": 60,
        "qwen3.8-max": 15,
        "qwen3.8-flash": 30,
        "qwen3.7-plus": 60,
        "deepseek-v4.1-flash": 100,
        "deepseek-v4-pro": 15,
        "hy4-preview": 30,
        "hy3": 60,
        "grok-4.7": 15,
        "gpt-6-luna": 15,
        "gpt-5.6-luna": 15,
        "claude-haiku-5-5": 15,
        "gemini-4-argon": 30,
    ]

    private static let listURL = URL(string: "https://opencode.ai/inference/go/v1/models")!
    private static let tableKey = "limitsTable"
    private static let namesKey = "limitsNames"
    private static let dateKey = "limitsFetched"
    private static let maxAge: TimeInterval = 24 * 60 * 60
    private static let holder = Holder()

    static var count: Int { holder.count }
    static var isDynamic: Bool { holder.isDynamic }
    static var displayNames: [String] { holder.names }

    static func models() -> [String] { holder.names }

    static func value(model: String) -> Double? {
        guard let key = holder.key(for: model) else { return nil }
        return holder.table[key]
    }

    /// The table key for a display name or an API id, nil when neither is known.
    static func id(for label: String) -> String? { holder.key(for: label) }

    // The model list says "DeepSeek V4.1 Flash", the API says
    // "deepseek-v4.1-flash", so both sides go through the same shape before
    // they are compared.
    static func normalize(_ name: String) -> String {
        var text = stripParenthetical(name).lowercased()
        for (from, to) in [(".", "-"), (" ", "-"), ("_", "-")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        while text.contains("--") { text = text.replacingOccurrences(of: "--", with: "-") }
        return text
    }

    static func stripParenthetical(_ name: String) -> String {
        guard let range = name.range(of: "\\s*\\([^)]*\\)", options: .regularExpression) else { return name }
        return name.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Refreshes from the public model list when the cached copy is a day old. A
    /// failed fetch keeps whatever table we already have and still records the
    /// attempt, so a broken source is retried once a day, not every refresh.
    static func refreshIfStale(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: dateKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > maxAge else { return }

        let parsed = await fetch()
        defaults.set(Date(), forKey: dateKey)
        guard let parsed else { return }

        holder.replace(parsed)
        defaults.set(parsed.mapValues(\.limit), forKey: tableKey)
        defaults.set(parsed.mapValues(\.name), forKey: namesKey)
    }

    private static func fetch() async -> [String: (name: String, limit: Double)]? {
        var request = URLRequest(url: listURL)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = body["data"] as? [[String: Any]]
        else { return nil }
        let parsed = parse(items)
        return parsed.isEmpty ? nil : parsed
    }

    /// Pulls the `go` monthly limit out of the public model list. The list's ids
    /// are the ones the usage API returns, so they are the cache keys.
    static func parse(_ items: [[String: Any]]) -> [String: (name: String, limit: Double)] {
        var table: [String: (name: String, limit: Double)] = [:]
        for item in items {
            guard let id = item["id"] as? String,
                  let go = item["go"] as? [String: Any],
                  let usage = go["monthly_usage"] as? [String: Any],
                  let limit = (usage["go"] as? NSNumber)?.doubleValue
            else { continue }
            table[normalize(id)] = (item["name"] as? String ?? id, limit)
        }
        return table
    }

    private final class Holder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: Double]
        private var labels: [String: String]
        private(set) var isDynamic: Bool

        init() {
            let defaults = UserDefaults.standard
            let cached = defaults.dictionary(forKey: Limits.tableKey) as? [String: Double] ?? [:]
            let names = defaults.dictionary(forKey: Limits.namesKey) as? [String: String] ?? [:]
            isDynamic = !cached.isEmpty
            stored = cached
            labels = names
            if stored.isEmpty {
                for (id, limit) in Limits.bundled {
                    let key = Limits.normalize(id)
                    stored[key] = limit
                    labels[key] = id
                }
            }
        }

        var table: [String: Double] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        // The model list's display name can carry a revision suffix ("… 1017")
        // that the usage id does not, so a label is resolved to its key.
        func key(for label: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            let normalized = Limits.normalize(label)
            if stored[normalized] != nil { return normalized }
            return labels.first { Limits.normalize($0.value) == normalized }?.key
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return stored.count
        }

        var names: [String] {
            lock.lock(); defer { lock.unlock() }
            return labels.values.sorted()
        }

        func replace(_ parsed: [String: (name: String, limit: Double)]) {
            lock.lock(); defer { lock.unlock() }
            stored = parsed.mapValues(\.limit)
            labels = parsed.mapValues(\.name)
            isDynamic = true
        }
    }
}
