# 1.3.1 candidate validation

2026-09-28, Apple Silicon, macOS 27 / Xcode 27. Published as 1.3.1 build 4.

## Regression coverage

201 XCTest tests passed, including 11 new regressions covering:

- Ping process deadline, cancellation before/after launch and localhost discovery.
- Dead probes versus empty filtered results; clearing filters without showing dead probes.
- IP labels surviving MAC enrichment, snapshot save and label removal.
- Saved ranges replacing imported file targets.
- Identical snapshots containing dead probes; canonical MAC comparison badges.
- Recomputing comparisons after snapshot replacement and device removal.
- Explicit port targets overriding an unrelated table selection.

One unanswered address on the user's reported subnet took 1.815 s with the old
ping arguments and 1.005 s with numeric output and a one-second process limit.
The app additionally applies a 900 ms watchdog. This is a single-address check,
not a full-subnet performance benchmark or a guarantee of total scan duration.

## Review

Two independent read-only reviews covered UI actions and scan/persistence logic.
Confirmed findings above were fixed. Save failures now present an alert. The
inspector follows externally changed labels while preserving an unsaved draft.

## Remaining checks

- Visually check the empty/filter layout at 800, 960 and 1280 pixels, and the
  label sheet/context menu in the native app. Native UI automation was unavailable
  in this session; compilation does not establish visual acceptance.
- Exercise saved-network switching, exports to a failing destination and label
  editing in a real user session.
- Measure a complete scan on the same network/profile before and after.
- DNS/NetBIOS operations may continue until their timeouts after Stop, although
  stale results are rejected. Prompt underlying-operation cancellation remains
  follow-up work.
- The platform and update limitations in acceptance-1.3.0.md still apply.

## Local package

Candidate 1.3.1 build 4: universal Release GUI and CLI, Developer ID signatures,
Hardened Runtime, notarization (Accepted), stapling and Gatekeeper passed.
Notary submission: `772fea13-2e37-4ed0-a70e-ca327d1f4739`.
Packaged CLI scanned localhost successfully in Quick (0.37 s), Standard (1.16 s)
and Deep (2.13 s), producing valid JSON and exit code 0 in each case.
A second source review confirmed the context-target, saved-range, inspector and
export-write fixes. It did not replace native UI testing.
The exact verified DMG was published to GitHub and downloaded publicly before
promoting the build 4 appcast. Production in-app installation is left to the
owner and remains unverified here.

The DMG also passed notarization, stapling, mounted app checks and Gatekeeper.
DMG notary submission: `56cb65d3-2f76-44ae-8457-59b03707c9f5`.
Source regression CI passed: https://github.com/canberkys/iPScanner/actions/runs/36446731721 .
