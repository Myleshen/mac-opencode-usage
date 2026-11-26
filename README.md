# OpenCode Usage

<img src="docs/icon.png" width="96" align="right" alt="">

A macOS menu bar app that shows what your OpenCode **Go** plan is using, right
now. Port of the Noctalia plugin from my dotfiles.

```sh
brew install --cask Myleshen/tap/opencode-usage
```

The menu bar shows the gauge and three figures — `H 5% W 13% M 14%` — the
same percentages the console dashboard shows, with the console's own reset
times. Optionally add `C 17%` for the credit-usage percentage. Any
combination can be turned off in settings; click for per-model spend, requests
and tokens.

The figures come from the Go plan's own meters when the key can read them, and
fall back to sums of the usage API otherwise (see
[Where the percentages come from](#where-the-percentages-come-from)).

## Requirements

- macOS 14 or newer.
- opencode installed and signed in to a Go plan. The app reads the credential
  from the CLI once per launch (`opencode auth export`) and keeps it in memory:
  no key store, no login screen. If the key is missing or expired, the panel
  says so and points at `opencode auth login`.

## First-time setup

Steps 2 and 4 are interactive by design: one pastes a key, the other approves a
device code in the browser.

```shell
# 1. the CLI, which holds the credentials this app reads
brew install sst/tap/opencode

# 2. your OpenCode Go key — pick "OpenCode Go", paste the key from
#    https://opencode.ai/console (Settings → API keys)
opencode auth login

# 3. the app (cask lives in Myleshen/homebrew-tap)
brew tap Myleshen/tap
brew install --cask opencode-usage
open /Applications/OpenCodeUsage.app

# 4. optional: link the console workspace in the CLI, only so `--limits` can
#    show opencode's own usage route; the app's meters come from the Go key
opencode auth login "OpenCode Console" --method device
```

Step 4 prints a code and a URL — open the URL, enter the code, approve. Then
check what the app sees:

```shell
/Applications/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --dump
```

A `5h meter:` line means the panel shows `5-hour` with a `5h resets …` row, from
the plan's own meters. A `5h starts …` line means the Go key could not read
`/console/api/go/status`, and the app falls back to rolling sums — still
correct, just not the console's own numbers.

Finally, click the menu bar gauge → gear → **Launch at login**.

Move to a new release with `brew upgrade --cask opencode-usage`; the cask is
pinned to a tagged version, so Homebrew sees the bump. You can also download
`OpenCodeUsage.zip` from the latest release and drag the app out by hand.

### Ad-hoc signing (first launch)

The build is signed ad-hoc, not notarised, so a copy that came through a
browser carries a quarantine flag and Gatekeeper will call it *damaged*. The
cask clears the flag in a `postflight` step, so a Homebrew install just works.
For a manual download, clear it yourself once:

```shell
xattr -dr com.apple.quarantine /Applications/OpenCodeUsage.app
```

or right-click the app → **Open** → **Open** to approve it. Nothing is
downloaded again at runtime; the only network traffic is the usage API and the
public model list.

## Build

```shell
./build.sh                      # this machine's arch
ARCHS="arm64 x86_64" ./build.sh # universal
./build.sh --debug              # dev build that runs beside the install
open build/OpenCodeUsage.app
```

`--debug` builds `build/OpenCodeUsage-dev.app` with bundle id
`dev.myleshen.opencode-usage.debug` and version `1.0.26-dev`. It keeps its own
settings, instance lock and login item, so it runs next to the `/Applications`
install without changing any of it. Remove it when you are done: quit the dev
app and `rm -rf build/OpenCodeUsage-dev.app`.

No Xcode project, no packages: `build.sh` runs one `swiftc` call and assembles
the bundle. The icon lives in `Resources/AppIcon.icns`; `./icon.sh` redraws it
from `Resources/icon.swift`.

Self-checks:

```shell
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --selftest   # offline asserts
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --dump       # live fetch, prints numbers
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --limits     # ask opencode's own usage route
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --update     # compare against the latest release
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --loginitem on|off  # same as the settings toggle
```

## Settings

Open the panel, click the gear.

| Setting | Default | Notes |
| --- | --- | --- |
| Refresh | 60 min | Timer keeps running while the panel is closed. |
| Warn / critical | 80% / 95% | Panel color and warning triangle. |
| Menu bar | H + W + M | Which figures to show; add C for the credit-usage percentage. |
| Launch at login | off | Writes and registers `~/Library/LaunchAgents/dev.myleshen.opencode-usage.plist`. Remembered in preferences, so a brew upgrade that deletes the agent gets it back on the next launch. |
| Quit | — | Button at the bottom of settings; a MenuBarExtra has no Quit item of its own. |

The footer shows the running version, and `· vX.Y.Z available` once GitHub
reports a newer release (checked at most once a day).

### One scope only

The console attributes each request to a principal, and API-key traffic is
billed to a *service account*, not to your member id. On my workspace the
member account had $0.85 this month while the account total was $10 — same Go
quota, so filtering to the member id would have under-reported it by an order of
magnitude. The app therefore always shows every principal the key can see.

## Plans and the model list

The limits are read from the public model list at
<https://opencode.ai/inference/go/v1/models> rather than compiled in, so a model
added by OpenCode shows up on the next refresh instead of waiting for an app
release. No auth header is needed. `go.monthly_usage.go` is the model's monthly
limit in dollars and `name` is its display name; the free models carry no `go`
limit and are skipped. The list is fetched once a day, keyed through the same
normalisation as the usage API ids and cached in `UserDefaults`; a failed fetch
keeps the previous table and waits a day before retrying. A copy of the current
28-model table is bundled as the offline fallback, which `--dump` names
(`limits 33 models (api)` or `(bundled)`). Go Plus has substantially higher
limits and Go Teams is Go + $5 per model, so on those plans the printed limits
(and any percentage computed without the plan's meters) will be low. There is
no plan field in any API to detect it from, so the app does not guess.

Below the model cards, **All N models with usage** expands into an
alphabetical list of only the models that have spend, with all-time spend and
that model's limit. Untouched models are left out, but they still count towards
the plan table fetched above.

A model missing from the model list has no limit to compare against, so it
shows "no limit data" and a banner, while spend and request counts keep
updating.

## Where the percentages come from

Two sources, in this order:

1. **The plan's own meters** — `GET /console/api/go/status`, authorised by the
   same Go key, returns `access.meters.fiveHour`, `.week` and `.month`, each
   with `usedMicroCents`, `limitMicroCents` and `resetsAt`. The percent is
   used/limit and the reset instant is the console's own, so the details row
   reads `5h resets 19:45 +05:30`. All three figures come from the same payload:
   the weekly window resets Monday **00:00 UTC**, and the monthly one at the
   subscription's period end (`access.endsAt`).
2. **A rolling five-hour sum** of the console usage API, if those meters are
   absent. Then the panel labels the card `Last 5h` and shows the window start
   and end instead of a reset time, because a rolling sum has no future
   boundary.

When fallback 2 is in use the panel says so outright — a **No plan meters**
banner sits above the cards. The two sources can disagree materially (9% vs the
console's 14% on the same account), so it is never silent.

`./OpenCodeUsage --dump` prints which of the two is in use (`5h meter:` or
`5h starts …`).

## Available credits

The Go plan's included allowance is separate from the prepaid balance that pays
for managed-inference (Zen) usage. The panel therefore shows two credit cards,
**Available credits** and **Credits used** (`$4.24` and a percentage in the
example above), from:

```
GET /console/api/billing/status
GET /console/api/billing/payment-attempts
```

The same OpenCode Go key authorises both, and amounts are converted the same
way as usage costs (`micro-cents / 1e8`). `availableMicroCents` is what the
console calls "Available credits"; `available` already accounts for a credit
limit, so it is shown instead of the raw ledger balance.

There is no "total credits" field in the status payload, so the used percentage
is built from the purchase history: the sum of **succeeded** `credit_purchase`
attempts is 100%, and `used = purchased − available`. Failed attempts and Go
subscription payments (`go_initial`) are ignored. On an invoiced workspace
`creditLimitMicroCents` is used as the denominator instead. Without either
total (no purchase history, no limit) the second card shows `—` rather than
inventing a percentage. The response's `mode` (`pay-as-you-go`, `prepaid`,
`invoice`) is printed below the balance and in **Details**.

Both billing fetches are deliberately best-effort: a workspace with no billing
account, or a key without access to the billing route, leaves the cards hidden
instead of failing the Go refresh. `--dump` prints `available credits —` and
omits the used line in that case.

## How it works

1. Asks the CLI for the active Go credential (`opencode auth export`) once per
   launch rather than reading opencode's sqlite file, so a schema change cannot
   break it. The key is kept in memory and never leaves the machine except as
   the `Authorization` header to `opencode.ai`.
2. `GET /console/api/go/status` for the plan's five-hour, weekly and monthly
   meters: percent = `usedMicroCents / limitMicroCents`, each meter's own
   `resetsAt`, and the subscription period (`access.endsAt`). Those percentages
   are what the bar shows. The plan's month is that period — measured on this
   account: Oct 31 to Nov 30, $60 allowance, resets at renewal — so it is
   **not** the same window, or the same measure, as the calendar month's spend
   from the usage API. Both are labelled; neither is derived from the other.
3. `GET /console/api/usage/models?since=…` for the 5h and today windows,
   `from=…&to=…` calendar days for the week and month lists, plus one call with
   no window for lifetime totals. Filters `provider == "opencode-go"` and
   converts `totalCostMicroCents / 1e8` to USD. These sums drive the per-model
   cards, and the bar only when step 2 has no meter.
4. `GET /console/api/billing/status` and `/billing/payment-attempts` for the
   **Available credits** and **Credits used** cards. Best-effort, so a
   workspace without billing simply hides those cards.
5. `GET /console/api/usage/cost-by-day?from=…&to=…` for the 14-day strip.
   Quiet days are omitted, so the app zero-fills them. Best-effort: a failure
   hides the strip instead of failing the refresh.

### What range can be queried

`since` is silently clamped to the start of yesterday: `-1d` returns yesterday
onward, and `-2d`, `-4d`, `-30d` all return exactly the same rows. So a month of
`since` is a two-day total with the wrong name.

The same endpoint also takes `from` and `to` — plain calendar days,
`yyyy-MM-dd`, **both ends inclusive**, clamped to now — which are served from
the full history and need no `range`. Measured on this account: Nov 1–10
$22.14, Oct 1–31 $20.56, and `from` = `to` = Nov 7 $0.0136, matching that day's
`cost-by-day` bucket. So the Month window asks for the calendar month to date
and the Week window for Monday to date, and both are labelled with their real
names. `range` (`24h`, `7d`, `30d`, `6m`, `all`) still exists as a rolling span,
but it cannot express a month or a week that starts on a fixed day.

Window boundaries use the local calendar (Monday start), converted to UTC ISO
for the `since` parameter — `since` must be a `Z` timestamp: the API rejects
`+05:30`, `+00:00` and zone-less values. Durations are zone-independent, so the
5h cutoff is an exact instant; only the week/month/today boundaries depend on
this Mac's timezone.

## Notes

- The launch-at-login plist records the absolute path of the bundle. If the app
  is moved or rebuilt elsewhere, the next launch rewrites the plist to the path
  it is running from, so the login item keeps working.
- Launching the app twice is safe: the newer copy exits and the older one keeps
  the menu bar item, so the login item cannot produce a duplicate.
- There is no Quit item in the menu itself (MenuBarExtra limitation): use the
  gear → **Quit**, or `pkill -f OpenCodeUsage`.
- Per-model cards show spend, not percentages, whenever the console meter is in
  use: the meter is account-level and has no per-model split, so per-model
  percentages would not add up to it.
- Uninstall: `brew uninstall --cask opencode-usage` (it also removes the
  LaunchAgent and quits the app). `brew uninstall --zap` also drops the lock
  file.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `No OpenCode Go credential found` | Nothing for the `opencode-go` integration: `opencode auth login`, pick OpenCode Go. |
| `The OpenCode Go key was rejected (HTTP 401)` | Key expired or rotated: re-run `opencode auth login`. |
| Panel says `Last 5h` instead of `5-hour` | The Go key could not read the plan's meters in `/console/api/go/status`: check that `--dump` prints a `plan month` line and that the key is a Go subscription key. |
| `no limit data` on every card | A model newer than the model list, or a Go Plus/Teams account. Spend still works. |
| Gatekeeper says the app is damaged | Quarantine flag: `xattr -dr com.apple.quarantine /Applications/OpenCodeUsage.app`. |
| Menu bar shows two gauges | Stale copy holding no lock file — remove the other `OpenCodeUsage.app`, keep one. |
| Banner says **No plan meters** | The key could not read the plan's meters: `--dump` shows whether the plan status answered; a Go subscription key is required. |
| Settings footer names a newer version | `brew upgrade --cask opencode-usage`. |

## Releasing

Merging to `main` is the release. `main` takes pull requests only, with a green
`build` check, and there are no bypass actors — the maintainer goes through the
same gate as a contributor.
`.github/workflows/release.yml` takes the next patch from the **latest published
release**, not from the newest tag, so a run that dies before publishing is
retried at the same number instead of burning one. It tags the merged commit,
builds a universal app with that version, runs the self-test, publishes
`OpenCodeUsage.zip` with its sha256 in the notes, and then bumps `version` +
`sha256` in the cask in
[Myleshen/homebrew-tap](https://github.com/Myleshen/homebrew-tap) — the pinned
version is what lets users move forward with `brew upgrade --cask
opencode-usage`. Nothing is committed back to `main`, and a local `./build.sh`
takes its version from the last tag. `workflow_dispatch` takes an explicit
version if a patch bump is the wrong one.

The cask step needs a `TAP_DEPLOY_KEY` repository secret: the private half of an
SSH deploy key with write access to the tap, whose public half is registered
under the tap's Settings → Deploy keys. Without it the release is still
published and the workflow warns that the cask was left behind.

Homebrew reads its own clone of the tap
(`$(brew --repository)/Library/Taps/<user>/homebrew-tap`), not your working
copy, so pull that clone before verifying an install — otherwise `brew upgrade`
reinstalls the previous version and everything looks like a bad build:

```shell
git -C "$(brew --repository)/Library/Taps/myleshen/homebrew-tap" pull origin main
brew upgrade --cask opencode-usage
plutil -p /Applications/OpenCodeUsage.app/Contents/Info.plist | grep ShortVersion
```

## Contributing

Build and test steps, the file layout, and the checks CI runs are in
[CONTRIBUTING.md](CONTRIBUTING.md).
