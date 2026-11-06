# Contributing

Thanks for looking. The app is one universal `swiftc` call and a handful of
Swift files — no Xcode project, no packages, no generated code — so a change
should stay small enough to read in one sitting.

## Build and test

```shell
./build.sh                                                    # this machine's arch
ARCHS="arm64 x86_64" ./build.sh                               # what CI and the release build
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --selftest
```

`--selftest` is offline and must stay offline: it parses fixtures, so no
credentials, no network and no cached files. If a test needs a live account it
belongs in `--dump`, not here.

Run the app while you work:

```shell
open build/OpenCodeUsage.app
```

`--dump` (live usage), `--limits` (raw meter) and `--update` (release check)
need a signed-in opencode and a network; that is fine for manual checks but
never for the self-test.

## Where things live

| File | What it owns |
| --- | --- |
| `Sources/Usage.swift` | API calls, aggregation, formatting, `--dump` |
| `Sources/Limits.swift` | the Go model table fetched from the docs page, plus the compiled fallback |
| `Sources/PanelView.swift` | the popover and settings UI |
| `Sources/OpenCodeUsageApp.swift` | menu bar item, segments, app entry point |
| `Sources/SelfTest.swift` | the offline asserts behind `--selftest` |
| `build.sh` | bundle layout, Info.plist, ad-hoc signing |

## Rules of the road

- `main` takes pull requests only: a PR and a green `build` check are required,
  and force-pushes and deletions are blocked.
- No new dependencies and no second build step. One `swiftc` call, standard
  library and SwiftUI only.
- No data loss and no hidden network traffic: the only requests are the ones
  documented in the README.
- Anything a user sees in the panel or the menu bar also belongs in `--dump`
  and gets a line in the README.
- Do not bump the version. The release workflow bumps `build.sh`, tags the
  commit and updates the Homebrew cask on every merge to `main`.
- New non-trivial logic (a parser, a branch on money, a new API response) needs
  an assert in `SelfTest.swift`.

## Pull requests

CI builds the universal app, runs `--selftest` and checks both architectures
are in the binary. Before opening a PR:

- [ ] `ARCHS="arm64 x86_64" ./build.sh` succeeds without new warnings
- [ ] `./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --selftest` passes
- [ ] README updated for anything user-visible
- [ ] no version bump

## Reporting a bug

Include the app version (the settings footer shows it), the macOS version, and
the output of `--selftest`. For a wrong number, `--limits` and `--dump` say
whether the console meters or the fallback sums were in use — they print
amounts and model names, not the key, but read before pasting.

## Releasing (maintainers)

Everything after a merge to `main` is automatic:

1. `.github/workflows/release.yml` takes the next patch from the tags and tags
   the merged commit. Nothing is committed back to `main`.
2. It builds a universal app with that version, runs `--selftest`, zips it and
   publishes `OpenCodeUsage.zip` with the sha256 in the notes.
3. It bumps `version` and `sha256` in `Casks/opencode-usage.rb` in
   [Myleshen/homebrew-tap](https://github.com/Myleshen/homebrew-tap).

Step 3 needs a `TAP_DEPLOY_KEY` secret: the private half of an SSH deploy key
with write access to the tap (the public half is on the tap under Settings →
Deploy keys). Without it the release still publishes and the workflow logs a
warning; the cask then has to be bumped by hand.

Homebrew reads its own clone of the tap, so pull that clone before checking an
upgrade locally:

```shell
git -C "$(brew --repository)/Library/Taps/myleshen/homebrew-tap" pull origin main
brew upgrade --cask opencode-usage
plutil -p /Applications/OpenCodeUsage.app/Contents/Info.plist | grep ShortVersion
```
