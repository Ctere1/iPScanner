<div align="center">
  <img src="assets/icon-with-text.png" width="220" alt="iPScanner">
  <h3><em>See every device on your network.</em></h3>
  <p>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/Ctere1/iPScanner?color=green" alt="License"></a>
    <img src="https://img.shields.io/badge/macOS-14.4%2B-black?logo=apple" alt="macOS 14.4+">
    <img src="https://img.shields.io/badge/binary-universal-purple" alt="Universal binary">
    <img src="https://img.shields.io/badge/tests-184-brightgreen" alt="184 tests">
    <a href="https://github.com/canberkys/iPScanner"><img src="https://img.shields.io/badge/fork%20of-canberkys%2FiPScanner-lightgrey?logo=github" alt="Fork of canberkys/iPScanner"></a>
  </p>
</div>

---

# iPScanner — A native macOS network scanner

Open-source macOS counterpart to Advanced IP Scanner. Native SwiftUI, zero third-party dependencies, universal binary (Apple Silicon + Intel).

> **This is a fork of [canberkys/iPScanner](https://github.com/canberkys/iPScanner)**, maintained at
> [Ctere1/iPScanner](https://github.com/Ctere1/iPScanner). It tracks upstream's features and adds a
> round of correctness, security and performance fixes on top — see
> [What's different in this fork](#whats-different-in-this-fork).
>
> Upstream is the original project and deserves the credit for the app itself. If you want the
> author's own builds, get them from [upstream's releases](https://github.com/canberkys/iPScanner/releases/latest).

## Screenshots

<div align="center">
  <img src="docs/screenshots/01-results.png" width="800" alt="iPScanner — scan results with the host inspector open">
  <p><em>Scan results — table with vendors, ports, and labels; the right-side inspector shows the selected host's full detail and a live ping monitor.</em></p>
</div>

<div align="center">
  <img src="docs/screenshots/02-empty.png" width="800" alt="iPScanner — start screen with auto-detected default subnet">
  <p><em>Start screen — auto-detected default subnet, scan-profile picker (Quick / Standard / Deep), interface picker, auto-rescan menu, and the saved-ranges sidebar.</em></p>
</div>

---

## What's different in this fork

Upstream at `v1.2.0` is the baseline. Everything below is fixed here and not upstream. Each item is
one commit; run `git log --oneline upstream/main..main` to see them.

### Fixes you can feel

| | Upstream behaviour | Here |
|---|---|---|
| **Scan speed** | one `/sbin/ping` process per host, each blocking a thread | ICMP socket, no subprocess — **19.0s → 6.1s** on a /24 |
| **Hostnames** | only reverse DNS, so blank on any LAN without PTR records | falls back to **mDNS**, then **NetBIOS**, and shows which source it used |
| **NetBIOS names** | never resolved against Windows hosts (parser bug) | works — `DESKTOP-…` / workgroup now populate |
| **Toolbar** | controls overlapped and drew on top of each other on a narrow window | collapses into an overflow menu instead |
| **`0.0.0.0/0`** | expanded 4.3 billion addresses (~34 GB) and wedged the app | rejected in ~9 ms |
| **Deep scan banners** | silently fetched zero banners, every time | fetches them |

### Security

- **CSV formula injection** — a scanned host's own PTR record could carry `=cmd|'/c calc'!A1`,
  which reached the export unquoted and executed when the operator opened it in Excel. Now
  neutralized.
- **App Transport Security** — upstream disables ATS process-wide (`NSAllowsArbitraryLoads`), which
  also drops the TLS floor for the update check. Scoped to `NSAllowsLocalNetworking`, which is all
  the banner probe actually needs.
- **Update URL validation** — the release URL from the API was opened without checking scheme or
  host; a forged response could hand LaunchServices a `file://` path. Now https + github.com only.

### Correctness & performance

- Crash when two alive hosts share a MAC (proxy ARP, multi-homed NIC, a router answering for
  several of its own IPs) — `Dictionary(uniqueKeysWithValues:)` trapped on the duplicate key.
- Port-scan cancellation raced its own completion, leaving the *next* scan un-cancellable.
- `stop()` didn't stop a deep-profile port scan; it kept hammering the network.
- Reverse-DNS timeout never fired — a task group awaits all its children, so the 1s budget was
  fiction and one slow host stalled the whole enrich phase.
- mDNS re-resolved every known service on every browse callback: a connection storm growing with the
  square of the number of services, for the app's lifetime.
- O(n²) host merge on the main actor (~2.1 billion string compares at the 65k cap) → O(1) index.
- Sorting re-parsed the IP string on every comparison → stored `ipNumeric`.
- Probe timeouts were never cancelled, holding connections for the full window after an answer.
- Export failures were swallowed by `try?` — a full disk looked exactly like a successful save.

### Fork-specific

- **The in-app update check points at this fork** (`iPScannerUpdateRepository` in `Info.plist`).
  Upstream's builds don't contain these fixes, so advertising them here would walk you onto a
  downgrade. Point it wherever you like by editing that key.

---

## Installation

**This fork publishes no binaries — [build it from source](#development).** Building locally also
sidesteps Gatekeeper entirely: the app is signed with your own machine's key, so there is no
quarantine flag and no `xattr` incantation.

Upstream ships a prebuilt `.dmg` at [its releases](https://github.com/canberkys/iPScanner/releases/latest).
It is ad-hoc signed rather than notarized, so macOS blocks it on first launch until you clear the
quarantine attribute — upstream's README documents that workaround. Those builds do not contain
this fork's fixes.

> ℹ️ iPScanner runs without sandboxing because network discovery needs direct ICMP / ARP / TCP
> socket access. Everything stays local — no telemetry, no third-party calls.

---

## Development

**Requirements**: macOS 14.4+, Xcode 15+, [xcodegen](https://github.com/yonki/xcodegen).

The Xcode project is generated from `project.yml` and is not checked in, so `xcodegen generate` is
the first step after cloning and again after any `project.yml` change.

```bash
brew install xcodegen
git clone https://github.com/Ctere1/iPScanner.git
cd iPScanner
xcodegen generate
```

### Build & run the app

```bash
xcodegen generate     # after cloning, and after any project.yml change
open iPScanner.xcodeproj
# ⌘R to build and run
```

From the command line, without opening Xcode:

```bash
xcodebuild build -project iPScanner.xcodeproj -scheme iPScanner \
  -configuration Debug -destination 'platform=macOS'

open ~/Library/Developer/Xcode/DerivedData/iPScanner-*/Build/Products/Debug/iPScanner.app
```

### Tests

```bash
xcodebuild test -project iPScanner.xcodeproj -scheme iPScanner -destination 'platform=macOS'
```

184 tests, no network access required. They cover the CIDR/range and target-file parsers, the
oversized-range guard, ICMP echo build/parse (including truncated and hostile packets), NetBIOS
wire format against a real captured Windows reply, OUI 3-tier vendor lookup, the subnet calculator,
CSV / IP:Port / text-report escaping (including formula injection), snapshot encode/decode and diff,
device classification, name-source resolution, saved ranges, the CLI argument parser, and update
version comparison plus release-URL validation.

### Build the CLI

```bash
xcodebuild build -project iPScanner.xcodeproj -scheme ipscanner \
  -configuration Release -destination 'platform=macOS'
```

### Build a release .dmg

```bash
brew install create-dmg              # in addition to xcodegen
./scripts/build-dmg.sh 1.2.0         # version is optional, defaults to "dev"
```

Archives Release, ad-hoc signs, and writes `build/iPScanner-<version>.dmg`. It also tries to refresh
the OUI database from `standards-oui.ieee.org`, falling back to the bundled copy when offline.

<details>
<summary>Notes on the toolchain</summary>

If `xcodebuild` reports *"tool 'xcodebuild' requires Xcode"*, `xcode-select` is pointed at the
Command Line Tools. Either repoint it (`sudo xcode-select -s /Applications/Xcode.app`) or prefix
commands for the current shell only:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

The IEEE OUI databases (`oui.txt`, `oui28.txt`, `oui36.txt`) are bundled in the repo. The release CI
workflow refreshes them from `standards-oui.ieee.org` on every tag push.

</details>

---

## Features

<details>
<summary><strong>Discovery</strong> — CIDR/range, ping, TCP fallback, ARP, OUI vendor (3-tier), mDNS, banners</summary>

- **CIDR + range input** — `10.0.0.0/24`, `192.168.1.50-192.168.1.200`, or comma-separated multiple ranges (`10.0.0.0/24, 172.16.0.0/24`)
- **Auto-detected default subnet** from the active interface (en0/en1)
- **Concurrent ping** (32 parallel) over an unprivileged ICMP socket — no subprocess per host, no blocked thread (`/sbin/ping` remains a fallback if the kernel refuses the socket)
- **TCP fallback probe** (445/80/443/22/3389) for hosts that block ICMP — Windows Firewall, etc.
- **Host names** — reverse DNS first, then mDNS, then NetBIOS, with the source shown; most LANs have no PTR records, so the fallbacks are what make the column useful
- **MAC address** via `arp -an` parsing
- **Vendor lookup** with the bundled IEEE OUI registry — MA-L (24-bit), MA-M (28-bit), and MA-S (36-bit) for sub-block accuracy
- **mDNS / Bonjour** service discovery (`_airplay`, `_homekit`, `_smb`, `_ssh`, `_ipp`, `_googlecast`, …)
- **HTTP / HTTPS title** and **SSH banner** fetch on demand (port-scan banner enrichment)

</details>

<details>
<summary><strong>Actions</strong> — port scanner, context menu, Wake-on-LAN, multi-select</summary>

- **Port scanner** — common-ports preset, web preset, custom ranges (`8000-8100`), bounded concurrency to avoid connection storms
- **Right-click context menu** per host: HTTP / HTTPS / SSH / VNC / RDP / SMB / AFP / Telnet / Ping in Terminal / Refresh / Wake-on-LAN / Copy IP/Hostname/MAC / Remove from list
- **Wake-on-LAN** — UDP magic packet, single host or bulk
- **⌘C** copies selected IP(s) from the table
- **Multi-select** for bulk actions

</details>

<details>
<summary><strong>Inspector</strong> — auto-opens on selection, ping monitor, action grid</summary>

Selecting a single host opens the right-side panel automatically. The panel is resizable and its width is persisted.

- Header — device-type icon, IP, vendor, classification
- Inline label editor with `#tag` syntax (searchable, MAC-anchored, persisted)
- Full info: hostname, MAC, anchor, open ports (with service names), service title, RTT, TTL, NetBIOS name & workgroup (Standard / Deep)
- mDNS services list
- Live ping monitor — sparkline + avg / min / max / loss stats (1s interval, 60-sample buffer)
- Action grid grouped into Connect / Tools / Copy

</details>

<details>
<summary><strong>v1.1 additions</strong> — scan profiles, interface picker, auto-rescan, snapshot diff, search highlighting, warnings hub</summary>

- **Scan profiles** — *Quick* (ping only) / *Standard* (+ TCP fallback) / *Deep* (+ auto port scan & banner fetch on alive hosts)
- **Network interface picker** — choose `en0` / `en1` / `utun` (VPN) from a menu; subnet auto-fills
- **Auto-rescan** — off / 30 s / 1 m / 5 m / 15 m, kicks in after the previous scan finishes
- **Change detection / snapshot diff** — load a previous `.ipscan.json` as comparison baseline; per-row badges (`+` new, `~` changed, `−` missing) plus a summary popover listing missing hosts
- **Permission/failure surfacing** — status-bar warnings hub (ARP table empty, banner fetch failures) with a click-through detail popover
- **Search match highlighting** — query substrings highlighted in IP / Hostname / MAC / Vendor / Title / Label cells
- **Resizable inspector** — drag the divider; width persisted

</details>

<details>
<summary><strong>v1.2 additions</strong> — file import, CLI binary, NetBIOS, subnet calculator, update check, TTL, new export formats</summary>

- **File import** — feed a `.txt` / `.csv` of IPs, CIDRs, or ranges instead of typing into the range field; invalid lines reported, duplicates deduped
- **`ipscanner` CLI** — headless binary inside the app bundle for cron / launchd / scripts (see [Command-line interface](#command-line-interface-ipscanner))
- **NetBIOS name fetcher** — Standard / Deep profiles pull Windows computer name + workgroup via UDP 137 when DNS is stale
- **Subnet calculator popover** — `function` icon in the toolbar; `/N` → network, broadcast, host range, count, dotted mask, wildcard
- **In-app update check** — auto-checks GitHub Releases once per 24 h, also available under `Help → Check for Updates…`; the repository it queries is the `iPScannerUpdateRepository` key in `Info.plist` (this fork, not upstream)
- **TTL column** — read from the ICMP reply's IP header, optional column with an OS hint tooltip
- **IP:Port export** and **Text Report export** — flat `ip:port` lines for piping into Nmap / firewalls, and a padded human-readable report for tickets

</details>

<details>
<summary><strong>Persistence & I/O</strong></summary>

- **Saved ranges** with friendly names (`Home`, `Office VLAN`) — sidebar with rename support
- **Snapshot save/load** — `.ipscan.json`, ⌘O / ⌘⌥S
- **Export** as CSV / JSON / **IP:Port list** / **Text Report** / clipboard
- Per-host labels persisted in `UserDefaults`

</details>

<details>
<summary><strong>UX</strong> — split view, app menus, appearance picker, status bar</summary>

- macOS-native: `NavigationSplitView` (sidebar + detail + inspector), `ContentUnavailableView`, App-menu commands, custom About panel, GitHub Help menu
- **Appearance picker** in `View → Appearance` (System / Light / Dark)
- **Live updates** — alive hosts stream into the table as they're discovered
- **Status bar** — progress, alive count, filter match, elapsed time, warnings, diff summary
- **Responsive toolbar** — collapses into an overflow menu as the window and inspector take space, rather than overlapping itself
- Sandbox disabled (required for ICMP / ARP / socket access)

</details>

---

## Command-line interface (`ipscanner`)

The same scanning engine is exposed as a headless `ipscanner` binary inside the app bundle, suitable for cron jobs, `launchd`, or piping into other tools.

Building from source, the binary lands in DerivedData rather than `/Applications` — see [Build the CLI](#build-the-cli). The examples below use the installed-app path.

```bash
# Discover hosts on a subnet, write JSON to a file
/Applications/iPScanner.app/Contents/MacOS/ipscanner 10.0.0.0/24 \
  --profile standard --format json --output scan.json

# Scan a target list from CSV with port scan + banner fetch, emit ip:port lines
/Applications/iPScanner.app/Contents/MacOS/ipscanner \
  --input targets.csv --ports 22,80,443 --fetch-banners --format ip-port

# Quick (ICMP-only) scan to stdout
/Applications/iPScanner.app/Contents/MacOS/ipscanner 192.168.1.0/24 --profile quick --format txt
```

Run `--help` for the full flag list. Exit codes: `0` success, `1` argument / input error, `2` runtime / scan error.

For convenience you can symlink it onto your `PATH`:

```bash
sudo ln -s /Applications/iPScanner.app/Contents/MacOS/ipscanner /usr/local/bin/ipscanner
```

---

## Roadmap

> Upstream's roadmap, kept for reference. This fork tracks upstream rather than planning its
> own feature work; its changes are the fixes listed [above](#whats-different-in-this-fork).

<details>
<summary><strong>v1.0 — completed</strong></summary>

- [x] Multi-range scan input
- [x] TCP fallback probe (ICMP-blocked hosts)
- [x] mDNS / Bonjour discovery
- [x] Wake-on-LAN
- [x] Saved ranges with names + Rename
- [x] Snapshot save/load (`.ipscan.json`)
- [x] Per-host labels (MAC-anchored, `#tag` searchable)
- [x] Live ping monitor in inspector
- [x] Service-name column for ports (22 → ssh, 9100 → printer, …)
- [x] HTTP title / SSH banner enrichment
- [x] OUI MA-L + MA-M + MA-S (sub-block accuracy)
- [x] App-menu commands + keyboard shortcuts
- [x] Appearance picker (System / Light / Dark)

</details>

<details>
<summary><strong>v1.1 — completed</strong></summary>

- [x] Scan profiles — Quick / Standard / Deep
- [x] Network interface picker
- [x] Auto-rescan
- [x] Change detection / snapshot diff
- [x] Permission/failure surfacing
- [x] Search match highlighting
- [x] Resizable inspector

</details>

<details>
<summary><strong>v1.2.0 — Operations focus — completed</strong></summary>

Moved iPScanner from a desktop tool to a usable operations tool.

- [x] **File import** — read targets from `.txt` / `.csv` (IP, CIDR, range), dedupe, report invalid lines
- [x] **TTL column** — parsed from `/sbin/ping` output, optional column, included in CSV / JSON export, OS hint tooltip
- [x] **IP:Port list export** — flat `ip:port` lines for piping into Nmap, firewall rules, scripts
- [x] **TXT report export** — human-readable summary suitable for tickets and email
- [x] **`ipscanner` CLI** — headless binary inside the app bundle. Flags: `--input`, `--ports`, `--profile`, `--fetch-banners`, `--format json|csv|txt|ip-port`, `--output`, `--quiet`, `--help`. Exit codes for automation. Single-IP scans (`ipscanner 127.0.0.1`) supported.

</details>

<details>
<summary><strong>v1.2.1 — Enterprise enrichment — partially shipped</strong></summary>

- [x] **NetBIOS name fetcher** — UDP 137 query for Windows host name / workgroup when DNS is stale
- [x] **Subnet calculator popover** — `/N` to network / broadcast / host-count, useful inline tool
- [x] **In-app update check** — periodic GitHub Releases API check, alert with View Release / Skip / Later, manual `Help → Check for Updates…`
- [ ] **Notarized release** — Apple Developer ID signature, removes the Gatekeeper friction documented in [Installation](#installation)

</details>

### v1.3 — Persistent operations

- [ ] **launchd-backed scheduled scans** — true background scans even when the app is closed (in-memory auto-rescan stays as the foreground equivalent)
- [ ] **History / time-series** — long-term per-host first-seen / last-seen / port-state tracking on top of the existing snapshot model

<details>
<summary><strong>Deferred (P2)</strong> — open to demand, not on the active list</summary>

- Multi-ping at scan time with packet-loss percentage (live inspector already covers the diagnostic case; 3× scan time is rarely worth it)
- Filtered-port detection (`open` / `closed` / `filtered` distinction; risk of mis-classification on TCP timeout)
- XML export
- Append-to-file export mode (snapshot diff is the cleaner historical model)

</details>

<details>
<summary><strong>Out of scope</strong> — explicit non-goals</summary>

- Public plugin API. Internal protocols (`TargetProvider`, `HostEnricher`, `ScanExporter`) keep the codebase clean without committing to a stable extension contract.
- Random IP feeder (Angry IP Scanner-style). Doesn't match the operational use case and invites misuse.
- HTTP proxy detection / arbitrary HTTP sender. Out of scope for a discovery tool; covered better by `curl`.
- Menu-bar mode with new-device notifications. CLI + `launchd` is the more flexible path for the same goal.
- IPv6 support. Niche for typical macOS LAN discovery; will reconsider on user demand.

</details>

---

## Tech stack

SwiftUI (macOS 14.4+, `@Observable`, `NavigationSplitView`) · Swift Concurrency (`async/await`, `TaskGroup`, `AsyncStream`) · Network framework (`NWConnection`, `NWBrowser`) · BSD sockets for ICMP echo · `Process` for `/usr/sbin/arp` · zero third-party Swift packages.

---

## License

MIT — see [LICENSE](LICENSE).

Vendor data from the [IEEE Standards Association OUI registries](https://standards-oui.ieee.org/) (public).

## Credits

**iPScanner** is by **Canberk Kılıçarslan** — [canberkki.com](https://canberkki.com) —
at [canberkys/iPScanner](https://github.com/canberkys/iPScanner). All of the app's design and
features are his work.

This fork is maintained by **Cemil Tan** at [Ctere1/iPScanner](https://github.com/Ctere1/iPScanner)
and adds the fixes listed under [What's different in this fork](#whats-different-in-this-fork).

Issues with the fork's changes → [fork issues](https://github.com/Ctere1/iPScanner/issues).
Issues with the app itself → [upstream issues](https://github.com/canberkys/iPScanner/issues).
