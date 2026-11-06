# OpenCode Usage

<img src="docs/icon.png" width="96" align="right" alt="">

A macOS menu bar app that shows what your OpenCode **Go** plan is using, right
now. Port of the Noctalia plugin from my dotfiles.

The menu bar shows the gauge and three figures — `H 5% W 13% M 14%` — the
same percentages the console dashboard shows, with the console's own reset
times. Optionally add `C 17%` for the credit-usage percentage. Any
combination can be turned off in settings; click for per-model spend, requests
and tokens.

The figures come from the console's meter when opencode is signed in to a
console workspace, and fall back to sums of the usage API otherwise (see
[Where the percentages come from](#where-the-percentages-come-from)).

## Requirements

- macOS 14 or newer.
- opencode installed and signed in to a Go plan. The app asks the CLI for the
  credential (`opencode auth export`) and keeps nothing of its own: no key
  store, no login screen. If the key is missing or expired, the panel says so
  and points at `opencode auth login`.

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

# 4. recommended: link the console workspace, which is where the real
#    5-hour / weekly / monthly meters and reset times come from
opencode auth login "OpenCode Console" --method device
```

Step 4 prints a code and a URL — open the URL, enter the code, approve. Then
check which source the app is using:

```shell
/Applications/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --limits
```

Real meter data means the panel shows `5-hour` with a `5h resets …` row.
`{"data":null}` means step 4 did not complete, and the app falls back to rolling
sums — still correct, just not the console's own numbers.

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
downloaded again at runtime; the only network traffic is the usage API.

## Build

```shell
./build.sh                      # this machine's arch
ARCHS="arm64 x86_64" ./build.sh # universal
open build/OpenCodeUsage.app
```

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
| Refresh | 10 min | Timer keeps running while the panel is closed. |
| Warn / critical | 80% / 95% | Panel color and warning triangle. |
| Menu bar | H + W + M | Which figures to show; add C for the credit-usage percentage. |
| Launch at login | off | Writes and registers `~/Library/LaunchAgents/dev.myleshen.opencode-usage.plist`. |
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

The limits are read from the pricing table on
<https://opencode.ai/docs/go/> rather than compiled in, so a model added by
OpenCode shows up on the next refresh instead of waiting for an app release.
The page is fetched once a day (and on any refresh when the cache is older than
that), parsed for the `go` slot, and cached in `UserDefaults`; a copy of the
current 28-model table is bundled as the offline fallback, which `--dump` names
(`limits 28 models (docs)` or `(bundled)`). Go Plus has substantially higher
limits and Go Teams is Go + $5 per model, so on those plans the printed limits
(and any percentage computed without a console session) will be low. There is
no plan field in any API to detect it from, so the app does not guess.

Below the model cards, **All N models with usage** expands into an
alphabetical list of only the models that have spend, with all-time spend and
that model's limit. Untouched models are left out, but they still count towards
the plan table fetched above.

A model missing from the docs table has no limit to compare against, so it
shows "no limit data" and a banner, while spend and request counts keep
updating.

## Where the percentages come from

Two sources, in this order:

1. **The console's own meter** — `opencode api GET /api/experimental/usage/limits`
   returns `go.rolling` as `{percent, limited, resetsAt}`. That is the number the
   console dashboard shows, with the real window boundary, so the app uses it
   whenever it is there. Requires opencode to be signed into a console workspace
   (`account` / `workspace` tables populated by the device sign-in above); the
   details row then reads `5h resets 19:45 +05:30`. The same payload names the
   workspace, which is what the subtitle shows (`Default · Go plan`) — there is
   no org or workspace setting, because the key already implies it. All three
   figures come from the same payload, whose boundaries are not the ones you
   would guess: the weekly window resets Monday **00:00 UTC**, and the monthly
   window is a rolling ~30 days, not the calendar month.
2. **A rolling five-hour sum** of the console usage API, if that meter is absent.
   Then the panel labels the card `Last 5h` and shows the window start and end
   instead of a reset time, because a rolling sum has no future boundary.

When fallback 2 is in use the panel says so outright — a **No console session** banner
sits above the cards, with the command to fix it. The two sources can disagree
materially (9% vs the console's 14% on the same account), so it is never silent.

`./OpenCodeUsage --limits` prints the raw meter response, which is how to tell
which source is in use.

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

1. Asks the CLI for the active Go credential (`opencode auth export`) rather
   than reading opencode's sqlite file, so a schema change cannot break it. The
   key never leaves the machine except as the `Authorization` header to
   `opencode.ai`.
2. Asks the local opencode server for the console meter
   (`opencode api GET /api/experimental/usage/limits`). If it has data, those
   percentages are what the bar shows.
3. `GET /console/api/usage/models?since=…` for the 5h and today windows, plus
   one call with no `since` for lifetime totals. Filters `provider ==
   "opencode-go"` and converts `totalCostMicroCents / 1e8` to USD. These sums
   drive the per-model cards, and the bar only when step 2 has no meter.
4. `GET /console/api/billing/status` and `/billing/payment-attempts` for the
   **Available credits** and **Credits used** cards. Best-effort, so a
   workspace without billing simply hides those cards.

### Why there are no weekly or monthly dollar figures

`since` is silently clamped: ask for 2 days back and you get the same numbers as
for 7 days back, because the endpoint only retains roughly three days of detail.
Measured on this account at one instant — `-1d` 2,651 requests, `-2d` 4,297,
`-3d` 4,298, `-4d` … `-7d` 4,299 — a flat plateau, and the same for cost. So a
week or month of spend cannot be queried at all, and anything labelled that way
would just be a three-day total with the wrong name.

What the API does serve is honest: the meter's percentages (step 2), the 5-hour
and today windows (inside the retention), and lifetime totals (no `since`). The
panel shows exactly those, and the Weekly and Monthly cards show the meter's
reset time instead of a dollar figure. The console's own page shows a week of
spend from a store the public API does not expose, which is why its dollar
figure cannot be reproduced here.

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
| Panel says `Last 5h` instead of `5-hour` | No console session, so `--limits` returns `{"data":null}`: re-run the device sign-in. |
| `no limit data` on every card | A model newer than the built-in table, or a Go Plus/Teams account. Spend still works. |
| Gatekeeper says the app is damaged | Quarantine flag: `xattr -dr com.apple.quarantine /Applications/OpenCodeUsage.app`. |
| Menu bar shows two gauges | Stale copy holding no lock file — remove the other `OpenCodeUsage.app`, keep one. |
| Banner says **No console session** | The device sign-in lapsed or was never done: `opencode auth login "OpenCode Console" --method device`, then refresh. |
| Settings footer names a newer version | `brew upgrade --cask opencode-usage`. |

## Releasing

`.github/workflows/release.yml` builds a universal app, runs the self-test, zips
it and publishes `OpenCodeUsage.zip` on a `v*` tag.

Then bump the cask in [Myleshen/homebrew-tap](https://github.com/Myleshen/homebrew-tap):
`version "<tag without v>"` and `sha256` of the published asset (the hash is
printed in the release notes). That pinned version is what lets users move
forward with `brew upgrade --cask opencode-usage`; skip it and the tap keeps
serving the old build.

Homebrew reads its own clone of the tap
(`$(brew --repository)/Library/Taps/<user>/homebrew-tap`), not your working
copy, so pull that clone before verifying an install — otherwise `brew upgrade`
reinstalls the previous version and everything looks like a bad build:

```shell
git -C "$(brew --repository)/Library/Taps/myleshen/homebrew-tap" pull origin main
brew upgrade --cask opencode-usage
plutil -p /Applications/OpenCodeUsage.app/Contents/Info.plist | grep ShortVersion
```
