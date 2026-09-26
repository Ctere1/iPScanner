# iPScanner 1.3.0 — draft release notes

Unpublished local candidate. Derived from `CHANGELOG.md`; finalize the version
and date only after the acceptance gates pass.

## Fixed

- Prevent the GUI/CLI filename collision that stopped the v1.2.0 app opening (#10).
- Keep discovery, enrichment, ports and banners in one cancellable scan lifecycle.
  Late results cannot replace a newer scan or loaded snapshot; automatic repeats
  wait for completion. Imported targets work with an empty range field.
- Validate complete MAC addresses, keep local/group addresses separate from vendor
  matches, clear outdated vendor information and retain old MAC-based labels.
- Avoid device-type guesses based on a DNS suffix or a generic vendor/web port.
- Remove vanished Bonjour records and reject stale resolutions after restart.
- Bound ARP queries and display collection errors and macOS 27 access guidance.

## New and changed

- Compact scanning controls, optional sidebar, adaptive device details and clear
  empty-search states. Details explain vendor status and device-type estimates.
- Native Help and Settings, previewed feedback through Cloudflare to public GitHub
  issues, and manual/optional daily GitHub update checks.
- Put AFP, Telnet and database access under Advanced. Explain missing connection
  handlers and distinguish Wake-on-LAN packet sending from confirmed device wake.
- Bundle a compact, build-validated IEEE index. The local universal app decreased
  from 20.96 MB to 14.46 MB (31%); this is app file size, not a DMG size.

## Compatibility

Native SwiftUI, IPv4, macOS deployment target 14.4, Apple Silicon and Intel binary
slices; no added third-party runtime dependency. Existing snapshot fields, CSV
columns and CLI arguments remain. `vendorStatus` is optional JSON/snapshot metadata.

**CLI location:** `iPScanner.app/Contents/Helpers/ipscanner` replaces the colliding
`Contents/MacOS/ipscanner` location. Update scripts that use the old path.

## Validation and known limitations

190 application tests and 6 Worker tests pass. Controlled localhost HTTP/SSH,
port/timeout/cancellation checks and packaged CLI profiles pass. See
`acceptance-1.3.0.md` for methods and pending coverage.

- macOS 27 can require Network Topology Observation capability/provisioning for MAC
  access. Actual MAC collection on this host remains pending signed verification.
- Intel hardware, macOS 14.4/Sequoia runtime checks, full VoiceOver and the exact
  light/dark window-size matrix remain pending.
- Registry source retrieval dates were not recorded in the original project;
  they are explicitly unknown. Source hashes are pinned in the generated index.
- The current local app and CLI are Developer ID signed with Hardened Runtime
  and secure timestamps. Notarization, downloaded-DMG Gatekeeper tests and
  GitHub Release publication remain pending. Automatic installation
  of updates is not included.
