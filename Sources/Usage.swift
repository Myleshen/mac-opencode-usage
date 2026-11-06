import Foundation

// Port of ~/dot-files/cachyos/noctalia/plugins/opencode-usage/lib/usage.luau.
// Difference: credentials come from `opencode auth export` rather than opencode's
// sqlite file, so a schema change cannot break the app.

enum Period: String, CaseIterable {
    case five, week, month, today
}

struct ModelUsage: Identifiable {
    let id: String
    var five = 0.0
    var week = 0.0
    var month = 0.0
    var today = 0.0
    // Lifetime totals. The usage API clamps `since` to roughly three days, so
    // week/month dollars cannot be queried; lifetime (no `since`) can.
    var total = 0.0
    var totalRequests = 0
    var totalInput = 0
    var totalOutput = 0
    var totalCacheRead = 0
    var requests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var limit: Double?

    func value(_ period: Period) -> Double {
        switch period {
        case .five: return five
        case .week: return week
        case .month: return month
        case .today: return today
        }
    }
}

struct UsageData {
    var five = 0.0
    var week = 0.0
    var month = 0.0
    var today = 0.0
    var monthRequests = 0
    var lifetimeTotal = 0.0
    var lifetimeRequests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var models: [ModelUsage] = []
    var updatedAt = Date()
    var fiveSinceAt = Date()
    var weekSinceAt = Date()
    var monthSinceAt = Date()
    var todaySinceAt = Date()
    // Percentages straight from the console's own meters, when opencode has a
    // linked console workspace. nil means the console API numbers are used.
    var meters: Meters?
    // Prepaid balance for managed inference (Zen). nil when the workspace has
    // no billing account, or when the billing route is unreachable.
    var credits: Credits?
}

// /console/api/billing/status. The amounts are micro-cents, like the usage
// API's costs, so 1e8 of them is one dollar.
struct Credits {
    let available: Double
    let balance: Double
    // "pay-as-you-go", "prepaid", or "invoice".
    let mode: String?
    let canPurchase: Bool
    // Total successfully purchased, from /billing/payment-attempts. nil when
    // there is no purchase history to compare against.
    let purchased: Double?
    // An invoiced workspace's limit; nil on prepaid, where `purchased` is the
    // only denominator available.
    let limit: Double?

    // What 100% means: the credit limit when one exists, otherwise everything
    // bought so far. The console exposes no other "total" for prepaid.
    var basis: Double? {
        if let limit, limit > 0 { return limit }
        if let purchased, purchased > 0 { return purchased }
        return nil
    }

    var used: Double? {
        guard let basis else { return nil }
        return min(max(basis - available, 0), basis)
    }

    var usedFraction: Double? {
        guard let used, let basis, basis > 0 else { return nil }
        return used / basis
    }
}

// UsageLimits.Go from opencode's server: the numbers the console itself shows.
struct Meters {
    struct Meter {
        let percent: Double
        let resetsAt: Date?

        func value(_ period: Period) -> Double { percent / 100 }
    }

    var five: Meter
    var week: Meter
    var month: Meter
    // Name of the console workspace the meter came from; also the only place
    // the workspace is identified, so no org setting is needed.
    var workspace: String?

    func meter(_ period: Period) -> Meter? {
        switch period {
        case .five: return five
        case .week: return week
        case .month: return month
        case .today: return nil
        }
    }
}


enum Usage {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    struct Top {
        let model: ModelUsage
        let pct: Double
        let value: Double
        let cap: Double
    }

    static let api = "https://opencode.ai/console/api"

    // Below a cent a model is noise on a card; the expanded list still shows it.
    static let meaningful = 0.01

    // MARK: - Windows

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday, matching the Linux widget.
        return calendar
    }

    static func weekStart(_ now: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    }

    static func monthStart(_ now: Date) -> Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? now
    }

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Limits and formatting

    static func cap(_ model: ModelUsage, _ period: Period) -> Double? {
        guard let limit = model.limit, limit > 0 else { return nil }
        switch period {
        case .five: return limit * 0.2
        case .week: return limit * 0.5
        case .month: return limit
        case .today: return nil
        }
    }

    // The model list is labelled with docs display names, the usage rows carry
    // API ids, so match them through the same normalisation the limits table
    // uses. Comparing the strings directly silently shows "no usage" for every
    // model.
    static func spend(_ data: UsageData, name: String) -> ModelUsage? {
        let key = Limits.normalize(name)
        return data.models.first { Limits.normalize($0.id) == key }
    }

    static func top(_ data: UsageData?, _ period: Period) -> Top? {
        guard let data else { return nil }
        // The console's meter wins when there is one: its window boundary is the
        // one the user sees in the browser, which the spend sums cannot recover.
        if let meter = data.meters?.meter(period) {
            let best = data.models
                .filter { cap($0, period) != nil }
                .max { $0.value(period) < $1.value(period) }
            let model = best ?? ModelUsage(id: "account")
            return Top(
                model: model,
                pct: meter.value(period),
                value: best?.value(period) ?? 0,
                cap: best.flatMap { cap($0, period) } ?? 0
            )
        }
        var best: Top?
        for model in data.models {
            guard let cap = cap(model, period), cap > 0 else { continue }
            let pct = model.value(period) / cap
            if best == nil || pct > best!.pct {
                best = Top(model: model, pct: pct, value: model.value(period), cap: cap)
            }
        }
        return best
    }

    // Current zone as "+05:30", so a time can be read without guessing the zone.
    static var offset: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }

    static func money(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 10 { return String(format: "$%.1f", value) }
        if value >= 0.01 { return String(format: "$%.2f", value) }
        if value > 0 { return String(format: "$%.3f", value) }
        return "$0.00"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func compact(_ value: Int) -> String {
        let n = Double(value)
        if n >= 1_000_000_000 { return String(format: "%.1fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return String(Int(n))
    }

    // MARK: - HTTP

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func send(_ url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(decoding: data.prefix(400), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 401 || status == 403 {
                throw Failure("The OpenCode Go key was rejected (HTTP \(status)). It is probably expired — run `opencode auth login` to refresh it. \(body.prefix(120))")
            }
            throw Failure("HTTP \(status) from the usage API: \(body.prefix(180))")
        }
        return data
    }

    static func request(_ url: URL, key: String) async throws -> [String: Any] {
        let data = try await send(url, key: key)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("Could not parse the usage API response.")
        }
        return object
    }

    static func rows(_ url: URL, key: String) async throws -> [[String: Any]] {
        let data = try await send(url, key: key)
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure("Could not parse the billing API response.")
        }
        return rows
    }

    // Ask the CLI instead of reading its database: `auth export` is the
    // supported interface, and the sqlite schema changes between releases.
    static func credential() throws -> String {
        guard let cli = opencodeCLI() else {
            throw Failure("Could not find the `opencode` CLI. Install it with `brew install sst/tap/opencode`.")
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["auth", "export"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw Failure("Could not run `opencode auth export`: \(error.localizedDescription)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure("Could not read the output of `opencode auth export`.")
        }
        for entry in entries where entry["integrationID"] as? String == "opencode-go" {
            guard let value = entry["value"] as? [String: Any] else { continue }
            if let key = value["key"] as? String, !key.isEmpty { return key }
            if let key = value["access"] as? String, !key.isEmpty { return key }
        }
        throw Failure("No OpenCode Go credential found. Run `opencode auth login`.")
    }

    // launchd starts the app with a minimal PATH, so Homebrew prefixes are
    // checked explicitly before falling back to PATH.
    static func opencodeCLI() -> URL? {
        let candidates = ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = "\(directory)/opencode"
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    // `since` nil asks for lifetime: the only range wider than the API's
    // roughly three-day lookback cap.
    static func models(since: Date?, key: String) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var page = 1
        while true {
            var components = URLComponents(string: api + "/usage/models")!
            components.queryItems = [
                URLQueryItem(name: "pageSize", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]
            if let since {
                components.queryItems?.insert(
                    URLQueryItem(name: "since", value: iso.string(from: since)),
                    at: 0
                )
            }

            let body = try await request(components.url!, key: key)
            items += body["items"] as? [[String: Any]] ?? []

            let info = body["pageInfo"] as? [String: Any] ?? [:]
            let next = Int(number(info["page"]) ?? Double(page))
            let count = Int(number(info["pageCount"]) ?? 1)
            guard next < count else { return items }
            page = next + 1
        }
    }

    // MARK: - Credits

    // Supplementary, so every failure is nil instead of an error: a workspace
    // without billing must not turn a working Go refresh into a failed one.
    static func credits(key: String) async -> Credits? {
        guard let statusURL = URL(string: api + "/billing/status") else { return nil }
        async let status = try? request(statusURL, key: key)
        async let bought = creditPurchases(key: key)
        guard let body = await status else { return nil }
        return credits(from: body, purchased: await bought)
    }

    // The billing status carries the balance; the payment attempts are what
    // turn it into a "used" percentage, because prepaid has no total of its own.
    static func credits(from body: [String: Any], purchased: Double? = nil) -> Credits? {
        // `availableMicroCents` is what the console calls "Available credits";
        // it already accounts for a credit limit, so prefer it to the ledger
        // balance when both are present.
        guard let available = number(body["availableMicroCents"]) else { return nil }
        let balance = number(body["balanceMicroCents"]) ?? available
        let limit = number(body["creditLimitMicroCents"])
        return Credits(
            available: available / 100_000_000,
            balance: balance / 100_000_000,
            mode: body["mode"] as? String,
            canPurchase: body["canPurchaseCredits"] as? Bool ?? false,
            purchased: purchased,
            limit: limit.map { $0 / 100_000_000 }
        )
    }

    // Sum only purchases that actually succeeded. Failed attempts stay in the
    // list ($10 in the fixture below), and Go subscription payments are a
    // different product, so neither belongs in the credit denominator.
    static func creditPurchases(from rows: [[String: Any]]) -> Double? {
        let amounts = rows
            .filter {
                $0["attemptType"] as? String == "credit_purchase"
                    && $0["status"] as? String == "succeeded"
            }
            .compactMap { number($0["amountMicroCents"]) }
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +) / 100_000_000
    }

    static func creditPurchases(key: String) async -> Double? {
        guard let url = URL(string: api + "/billing/payment-attempts") else { return nil }
        guard let list = try? await rows(url, key: key) else { return nil }
        return creditPurchases(from: list)
    }

    // MARK: - Aggregation

    static func aggregate(
        windows: [Period: [[String: Any]]],
        since: [Period: Date]
    ) -> UsageData {
        var data = UsageData()
        data.fiveSinceAt = since[.five] ?? Date()
        data.weekSinceAt = since[.week] ?? Date()
        data.monthSinceAt = since[.month] ?? Date()
        data.todaySinceAt = since[.today] ?? Date()

        var byId: [String: ModelUsage] = [:]
        var order: [String] = []

        for period in Period.allCases {
            for item in windows[period] ?? [] {
                guard item["provider"] as? String == "opencode-go" else { continue }
                let id = item["model"] as? String ?? "(unknown)"
                var model = byId[id] ?? ModelUsage(id: id, limit: Limits.value(model: id))
                if byId[id] == nil { order.append(id) }

                let cost = (number(item["totalCostMicroCents"]) ?? 0) / 100_000_000

                switch period {
                case .five:
                    model.five = cost
                    data.five += cost
                case .week:
                    model.week = cost
                    data.week += cost
                case .today:
                    model.today = cost
                    data.today += cost
                case .month:
                    model.month = cost
                    data.month += cost
                    model.requests = Int(number(item["totalRequests"]) ?? 0)
                    model.input = Int(number(item["totalInputTokens"]) ?? 0)
                    model.output = Int(number(item["totalOutputTokens"]) ?? 0)
                    model.cacheRead = Int(number(item["totalCacheReadTokens"]) ?? 0)
                    model.cacheWrite = Int(number(item["totalCacheWrite5mTokens"]) ?? 0)
                        + Int(number(item["totalCacheWrite1hTokens"]) ?? 0)

                    data.monthRequests += model.requests
                    data.input += model.input
                    data.output += model.output
                    data.cacheRead += model.cacheRead
                    data.cacheWrite += model.cacheWrite
                }
                byId[id] = model
            }
        }

        data.models = order.compactMap { byId[$0] }.sorted { a, b in
            let aUse = a.limit.map { $0 > 0 ? a.month / $0 : -1 } ?? -1
            let bUse = b.limit.map { $0 > 0 ? b.month / $0 : -1 } ?? -1
            return aUse == bUse ? a.month > b.month : aUse > bUse
        }
        data.updatedAt = Date()
        return data
    }

    static func fetch() async throws -> UsageData {
        // The key implies its workspace: the usage API needs no org header, and
        // the meter reports which workspace it answered for.
        let key = try credential()

        let now = Date()
        let since: [Period: Date] = [
            .five: now.addingTimeInterval(-5 * 3600),
            .week: weekStart(now),
            .month: monthStart(now),
            .today: calendar.startOfDay(for: now),
        ]

        async let lifetimeRows = models(since: nil, key: key)
        async let creditStatus = credits(key: key)

        var windows: [Period: [[String: Any]]] = [:]
        try await withThrowingTaskGroup(of: (Period, [[String: Any]]).self) { group in
            for period in Period.allCases {
                let at = since[period]!
                group.addTask {
                    (period, try await models(since: at, key: key))
                }
            }
            for try await (period, items) in group {
                windows[period] = items
            }
        }
        var data = aggregate(windows: windows, since: since)

        // Lifetime rides along in the same refresh so the model list can show a
        // figure the API actually serves for the range it claims.
        var byId = Dictionary(uniqueKeysWithValues: data.models.map { ($0.id, $0) })
        for item in try await lifetimeRows {
            guard item["provider"] as? String == "opencode-go" else { continue }
            let id = item["model"] as? String ?? "(unknown)"
            var model = byId[id] ?? ModelUsage(id: id, limit: Limits.value(model: id))
            model.total = (number(item["totalCostMicroCents"]) ?? 0) / 100_000_000
            model.totalRequests = Int(number(item["totalRequests"]) ?? 0)
            model.totalInput = Int(number(item["totalInputTokens"]) ?? 0)
            model.totalOutput = Int(number(item["totalOutputTokens"]) ?? 0)
            model.totalCacheRead = Int(number(item["totalCacheReadTokens"]) ?? 0)
            byId[id] = model
            data.lifetimeTotal += model.total
            data.lifetimeRequests += model.totalRequests
        }
        data.models = byId.values.sorted { $0.total > $1.total }
        data.meters = metersFromCLI()
        data.credits = await creditStatus
        return data
    }

    // MARK: - Console meters

    // `opencode api` talks to the local server, which knows the console
    // workspace's real meter (percent + reset time). Empty data means opencode
    // is not signed into a console workspace, so callers fall back to spending.
    static func metersFromCLI() -> Meters? {
        return meters(from: cliJSON())
    }

    static func meters(from data: Data) -> Meters? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["data"] as? [String: Any],
              let go = info["go"] as? [String: Any]
        else { return nil }

        func meter(_ key: String) -> Meters.Meter? {
            guard let raw = go[key] as? [String: Any],
                  let percent = number(raw["percent"])
            else { return nil }
            let resets = number(raw["resetsAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
            return Meters.Meter(percent: percent, resetsAt: resets)
        }

        guard let five = meter("rolling"), let week = meter("weekly"), let month = meter("monthly") else {
            return nil
        }
        let workspace = (info["workspace"] as? [String: Any])?["name"] as? String
        return Meters(five: five, week: week, month: month, workspace: workspace)
    }

    static func cliJSON() -> Data {
        // The CLI can come back empty right after launch (server still coming
        // up), and a nil meter silently downgrades the whole panel to sums.
        for attempt in 0..<2 {
            let data = cliOnce()
            if !data.isEmpty { return data }
            if attempt == 0 { Thread.sleep(forTimeInterval: 1) }
        }
        return Data()
    }

    private static func cliOnce() -> Data {
        guard let cli = opencodeCLI() else { return Data() }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["api", "GET", "/api/experimental/usage/limits"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return Data() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    // MARK: - Debug dump

    static func describe(_ data: UsageData) -> String {
        var lines = ["go plan · updated \(data.updatedAt)"]
        for period in [Period.five, .week, .month] {
            if let top = top(data, period) {
                lines.append("\(period.rawValue): \(percent(top.pct)) · \(top.model.id) · \(money(top.value)) of \(money(top.cap))")
            } else {
                lines.append("\(period.rawValue): —")
            }
        }
        lines.append("today \(money(data.today))")
        lines.append("all time \(money(data.lifetimeTotal)) · \(data.lifetimeRequests) req")
        lines.append("available credits \(data.credits.map { money($0.available) } ?? "—")")
        if let credits = data.credits, let used = credits.usedFraction, let spent = credits.used, let basis = credits.basis {
            lines.append("credits used \(percent(used)) · \(money(spent)) of \(money(basis))")
        }
        lines.append("limits \(Limits.count) models (\(Limits.isDynamic ? "docs" : "bundled"))")
        if let meter = data.meters?.five {
            lines.append("5h meter: \(percent(meter.value(.five))) from the console, resets \(meter.resetsAt?.description ?? "unknown")")
        } else {
            lines.append("5h starts \(iso.string(from: data.fiveSinceAt)) ends \(iso.string(from: data.updatedAt)) (rolling sum)")
        }
        for model in data.models {
            lines.append(
                "  \(model.id) limit \(model.limit.map(money) ?? "unlimited") "
                    + "5h \(money(model.five)) total \(money(model.total)) \(model.totalRequests) req"
            )
        }
        // The panel's "All models" list is labelled with docs display names, so
        // dump the same join: a docs name that fails to find its API id shows
        // up here as a missing row instead of "no usage" in the UI.
        let listed = Limits.models().compactMap { name -> String? in
            guard let model = spend(data, name: name), model.month > 0 else { return nil }
            let limit = Limits.value(model: name).map(money) ?? "-"
            return "  \(name) \(money(model.month)) of \(limit)"
        }
        if !listed.isEmpty {
            lines.append("cards \(data.models.filter { $0.month >= meaningful }.count) models (month >= \(money(meaningful)))")
        lines.append("model list rows with spend:")
            lines.append(contentsOf: listed)
        }
        return lines.joined(separator: "\n")
    }
}
