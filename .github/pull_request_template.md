## What changed

<!-- One or two sentences. What does a user see differently? -->

## Checks

- [ ] `ARCHS="arm64 x86_64" ./build.sh` succeeds without new warnings
- [ ] `./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --selftest` passes
- [ ] README updated if anything user-visible changed
- [ ] No version bump (the release workflow tags the merge)
- [ ] New logic has an assert in `Sources/SelfTest.swift`

## Notes for the reviewer

<!-- Anything you were unsure about, or deliberately left out. -->
