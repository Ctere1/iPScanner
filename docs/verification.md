> Current acceptance status: [acceptance-1.3.0.md](acceptance-1.3.0.md).
> Notes below are chronological and may describe earlier builds.

# 1.3.0 verification status

Local development verification on 2026-09-26, Apple Silicon, macOS 27.0,
Xcode 27.0. Developer ID signing and publication are deferred at the owner's request.

## Completed

- Inspected the published v1.2.0 DMG; SHA-256 matches the GitHub asset digest.
  Its disk image integrity and ad-hoc signature pass, both architectures are
  present, and deployment target is 14.4. Its app entry point prints CLI usage
  and exits 1: the GUI/CLI filename collision is confirmed.
- Debug and Release GUI and CLI builds succeeded. Both final Release executables
  contain arm64 and x86_64; deployment target remains 14.4.
- All 173 unit tests passed, with zero failures. ScanLifecycleTests covers waiting
  for banners before completion/rescan, Stop and immediate restart, late events,
  snapshot replacement during Deep ports, imported targets with empty range text,
  and Stop during banners. Three new OUI parser tests also passed.
- Bundle-layout regression fixtures pass: distinct executables accepted;
  identical GUI/CLI and missing helper rejected.
- Local app assembled with GUI in Contents/MacOS/iPScanner and CLI in
  Contents/Helpers/ipscanner. Ad-hoc signature passes strict/deep verification;
  layout check and packaged CLI help pass. This is a local test signature only.
- Final local Release app opens normally. GUI localhost scan completed in 2.5 s;
  packaged CLI Quick scan completed in 0.64 s and returned valid JSON.
- Vendor database parser benchmark with bundled IEEE data completed in 2.9 s
  in an unoptimized test executable. The previous implementation exceeded the
  60 s measurement timeout with the same resource files.
- Native UI checks: import targets with empty text enables Scan; Stop displays
  stopped state; version-1 snapshot loads; explicit details open as a sheet at
  compact width and as a right panel at wide width; Command-Option-I works.
- Light appearance inspected at 800 and 1728 logical-pixel window widths.
  Updated screenshots use fictional documentation addresses and hostnames.
- Project/workflow YAML, shell scripts and Info.plist syntax validated.

## Product experience follow-up

- Added vLens-inspired native help topics, feedback drafts and Settings.
- Three feedback tests verify URL encoding, optional environment data, empty and
  oversized drafts, and feature-request formatting. All 170 tests pass.
- Opened Getting Started from the main empty state; checked help layout visually.
- Opened Settings with Command-comma and completed a live manual GitHub update
  check. Settings displayed the installed version, last attempt and up-to-date result.
- Opened the feedback window; empty required fields disabled continuation.
  Entered a local test draft, expanded its preview and removed environment details;
  the preview reflected the removal. No issue was submitted.
- Debug and Release builds succeeded. The local test app is refreshed with these
  changes; Developer ID signing remains deferred.

## Remaining release gates

- Exact 960 and 1280 widths, dark appearance, full keyboard navigation and actual
  VoiceOver traversal need a final manual pass. Accessibility labels were
  inspected, but this does not substitute for VoiceOver testing.
- Sequoia 15/15.8 and macOS 14.4 clean-install/runtime checks require separate
  environments. Universal slices were inspected; Intel hardware was not tested.
- Real controlled-service integration checks for cancellation of every active
  network operation are not exhaustive; lifecycle regression tests use injected
  services, supplemented by localhost and interactive Stop checks.
- Developer ID identity and notarytool credentials are not configured. The
  signing/notarization pipeline is implemented but has not run with credentials.
- Final signed DMG, Gatekeeper/quarantine install test, notarization, stapling
  and SHA-256 release artifact remain pending. A local ad-hoc app is not proof
  of Gatekeeper acceptance for downloaded distributions.

No GitHub release or issue comment has been posted. The issue response is a draft.
Original project files remain untouched; changes are in the delivered source copy.

## Reproduce

```bash
xcodegen generate
xcodebuild test -scheme iPScanner -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
xcodebuild -scheme ipscanner -configuration Release -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
bash scripts/tests/bundle-layout.sh
```

Follow signing-guide-tr.md after local review for the final signed release.

## Cloudflare feedback delivery

- Direct Send Feedback replaces the browser handoff. Public issue disclosure and
  preview remain visible; only an explicit submission sends the report.
- 173 app tests and 6 Worker tests pass. Client tests cover confirmed receipt,
  rejected receipt URLs and service unavailability; Worker tests cover size and
  rate limits, payload validation, fixed repository and safe error responses.
- Deployed ipscanner-feedback-relay to Cloudflare. Live /health returned
  ready=false and /feedback returned HTTP 503, correctly failing closed without
  GITHUB_PAT. The required rate-limit binding is installed.
- Native UI exposes Send Feedback and the public issue disclosure.
- GitHub secret configuration and a successful live issue submission remain
  pending. No live issue was created during testing.

## Live feedback verification

After the owner configured GITHUB_PAT and explicitly approved a public test,
/health returned ready=true. A controlled POST to /feedback returned HTTP 200
and issueNumber=11. GitHub CLI independently confirmed the exact submitted body
at https://github.com/canberkys/iPScanner/issues/11. The test issue was closed
as completed after verification. No user or network data was sent.

This confirms the live relay-to-GitHub delivery and token permissions. It does
not verify receipt of GitHub email/push notifications, which depend on account
notification settings. Earlier pending-secret notes above describe the setup
state before this successful test.

## Feedback layout refinement

Rebuilt the feedback UI with a fixed header/footer, grouped labeled fields,
optional system information, a separate preview sheet and a dedicated success
screen. Release compilation and bundle layout/signature checks passed. The bug
form and preview sheet were inspected in a separate local app identity, preserving
the user's running scan session. No live feedback was submitted in this UI pass.
The refreshed app is in outputs/feedback-ui-test/iPScanner.app.
