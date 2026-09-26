# iPScanner 1.3.0 acceptance record

Date: 2026-09-26. Host: Apple Silicon, macOS 27.0, Xcode 27.
This is a Developer ID signed local development candidate; notarization and release acceptance remain pending. “Passed” applies to
the method listed, not every possible network or device. Previous chronological
notes remain in `verification.md`; this table is the current acceptance record.

Statuses: **Passed / Geçti**, **Failed / Başarısız**, **Environment pending / Ortam bekliyor**.
A pending manual check is explicitly identified when the limitation is test
coverage rather than missing hardware. No new public test issue was submitted.

| Feature / scenario | Status | Method and evidence |
|---|---|---|
| Quick, Standard and Deep discovery | Passed | Packaged universal CLI scanned only 127.0.0.1; each returned one host, exit 0. GUI Standard also completed with localhost DNS. See `evidence/cli-acceptance.json`. |
| IPv4, CIDR, ranges, multiple targets, invalid and oversized inputs | Passed | ScanRangeTests, ArgumentsTests and TargetFileParserTests. Packaged CLI invalid address exits 1. |
| File targets with empty range | Passed | Packaged CLI `--input` without positional range; injected GUI lifecycle test also verifies rescan scheduling. |
| Stop and immediate restart | Passed | ScanLifecycleTests reject old discovery events; snapshot load during ports ignores late results; Stop during banners does not finish or schedule a repeat. |
| Repeat waits for enrichment, ports and banners | Passed | Injected gates in ScanLifecycleTests; next repeat remains unset until the whole run finishes. |
| Every stage on real hardware, network switching during scan | Environment pending | Deterministic lifecycle coverage is present. Exhaustive real network interruption/switching has not been completed. |
| Strict MAC formats and address kinds | Passed | DeviceInformationTests: colon, short ARP octets, hyphen, flat, dotted; malformed/zero/group addresses; local MACs never receive a manufacturer. |
| IEEE priority and packaged data | Passed | OUILookupTests and known assignment from actual bundle. Generator verifies 39,295 MA-L / 6,370 MA-M / 6,981 MA-S records, bounds and exact bytes. |
| ARP parsing, conflicting records, process errors, timeout and cancellation | Passed | DeviceInformationTests use fixtures and controlled processes. Conflicting entries cannot assign a guessed router MAC. |
| Actual MAC acquisition on macOS 27 | Environment pending | Terminal ARP contained entries; the Swift child process returned exit 0 and zero bytes. Signed topology capability/profile required for further validation. GUI warning was inspected. |
| Refresh discards old vendor information | Passed | Authoritative merge regression; refresh explicitly clears previous enrichment and marks unavailable/dead data historical. Full per-device network refresh matrix remains manual. |
| Device classification | Passed | DeviceClassifierTests plus DNS suffix regression; conflicting/weak evidence returns Unknown; inspector shows evidence and historical status. |
| DNS | Passed | DNSResolverTests and actual localhost reverse lookup in GUI/CLI. |
| NetBIOS | Passed | Wire-format tests cover parsing, including responses without echoed questions. Real Windows/Samba device verification remains pending. |
| Bonjour removed/re-added services and stale callbacks | Passed | BonjourInventory tests reject old resolution tokens after removal/re-add. Network generation checks protect restarts. |
| Live Bonjour discovery and interface changes | Environment pending | Live advertiser disappearance/reappearance and network switching still need a controlled integration pass. |
| Ports, HTTP title, SSH banner, timeout and active cancellation | Passed | LocalServiceTests use TCP services bound to 127.0.0.1; PortScannerTests and lifecycle gates supplement them. |
| Search, no matches and clear action | Passed | Native GUI search hid all five fixture rows; Clear Search and Filters restored them. |
| Sort/filter/columns/saved ranges complete interaction matrix | Environment pending | Existing implementations retained and model tests pass; full final UI traversal/persistence matrix not completed. |
| Labels and old MAC formatting | Passed | Native GUI saved a #tag label. Regression verifies older unpadded MAC label lookup and no false snapshot differences across MAC formats. |
| Snapshot and exports | Passed | SnapshotTests, SnapshotDiffTests and ExportServiceTests; old version-1 fixture opened in GUI. CSV columns preserved; vendorStatus is optional JSON metadata. |
| Subnet calculator | Passed | SubnetCalculatorTests; complete final popover keyboard interaction still manual. |
| Connection tools / missing handlers | Environment pending | IPv4 validation and explicit launch/command errors implemented; end-to-end SSH, VNC, RDP, SMB, AFP and Telnet checks require installed clients/services. |
| Wake-on-LAN packet | Passed | LocalServiceTests verifies all 102 bytes, repeated MAC and rejected invalid/group MAC. Timeout/cancellation states no longer report success. |
| Wake-on-LAN physical wake | Environment pending | Requires a sleeping WoL-capable device; sent packet is explicitly not wake confirmation. |
| Feedback delivery and failures | Passed | 6 Worker tests + FeedbackServiceTests/FeedbackDraftTests. Earlier explicitly approved issue #11 verified relay delivery; no new issue created. Draft retained on error and submit disabled while sending. |
| Feedback layout and help | Passed | Native help/form/preview inspected in previous pass; screenshots 05 and 07. Final simultaneous keyboard/VoiceOver coverage pending below. |
| Update success/error/recovery and daily throttle | Passed | UpdateResponseTests inject newer release, HTTP 503, malformed JSON, recovery and recent-check throttling. Earlier live manual check succeeded. |
| Clean preferences startup | Passed | Separate quality-preview bundle identity opened with Standard profile, hidden sidebar and empty results; user's app identity/preferences untouched. |
| Full upgrade from user's existing preferences | Environment pending | Old snapshot and MAC-label compatibility tested; complete settings migration on a copied preferences domain still manual. |
| Light/dark visual layout | Passed | Earlier light compact/wide screenshots; new 900-point dark results screenshot 08. Dark inspector and missing-MAC warning inspected. |
| Exact 800 / 960 / 1280 widths in both themes | Environment pending | Earlier 800 light pass exists. Current automation could not reliably resize window edges/select theme; exact full matrix not passed. |
| Keyboard and VoiceOver | Environment pending | Cmd-O, Cmd-R, Cmd-Option-I, Cmd-comma and label Enter inspected. Full keyboard traversal and actual VoiceOver narration not completed. |
| Universal GUI and CLI, bundle collision prevention | Passed | `lipo` shows x86_64 + arm64 in both; bundle guard and negative collision tests pass. Developer ID signatures, secure timestamps and Hardened Runtime verify. |
| Intel hardware / macOS 14.4 / Sequoia 15 (15.8 if available) | Environment pending | Not available here. Deployment target 14.4 and universal slices are build checks only. |
| Developer ID signing | Passed | GUI and CLI signatures verified with Apple trust chain, Team ID 9QB26WKA4K, Hardened Runtime and secure timestamps. |
| Notarization, Gatekeeper downloaded DMG | Environment pending | No notarytool credentials profile available. No notarized release or quarantine install acceptance claimed. |

## Evidence and commands

The final test/build summaries, package sizes and CLI checks are in `evidence/`.
Full local Xcode logs are in the task's `work/quality-*.log`; generated artifacts
are not committed. Reproduce with the commands in `verification.md`, plus:

```sh
python3 scripts/build-vendor-db.py --check
(cd feedback-relay && npm test)
bash scripts/tests/bundle-layout.sh
```

## macOS 27 source

Apple DTS describes the Network Topology Observation capability and provisioning
profile requirement: https://developer.apple.com/forums/thread/841958 . The ARP
empty-output report is discussed at https://developer.apple.com/forums/thread/822025?page=2 .
Do not bypass OS privacy restrictions with a Terminal proxy. Validate GUI and CLI
separately in the later signing phase.
