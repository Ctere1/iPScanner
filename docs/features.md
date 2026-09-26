# Feature reference

[Back to README](../README.md) · [Acceptance status](acceptance-1.3.0.md)


<details>
<summary><strong>Discovery</strong> — CIDR/range, ping, TCP fallback, ARP, OUI vendor (3-tier), mDNS, banners</summary>

- **CIDR + range input** — `10.0.0.0/24`, `192.168.1.50-192.168.1.200`, or comma-separated multiple ranges (`10.0.0.0/24, 172.16.0.0/24`)
- **Auto-detected default subnet** from the active interface (en0/en1)
- **Concurrent ping** (32 parallel) using `/sbin/ping`
- **TCP fallback probe** (445/80/443/22/3389) for hosts that block ICMP — Windows Firewall, etc.
- **Reverse DNS** with 1-second timeout (race-cancelable)
- **MAC address** via `arp -an` parsing, subject to network reachability and macOS privacy restrictions
- **Vendor lookup** with the bundled IEEE OUI registry — MA-L (24-bit), MA-M (28-bit), and MA-S (36-bit) for sub-block matching; local/randomized MACs are not assigned a manufacturer
- **mDNS / Bonjour** service discovery (`_airplay`, `_homekit`, `_smb`, `_ssh`, `_ipp`, `_googlecast`, …)
- **HTTP / HTTPS title** and **SSH banner** fetch on demand (port-scan banner enrichment)

</details>

<details>
<summary><strong>Actions</strong> — port scanner, context menu, Wake-on-LAN, multi-select</summary>

- **Port scanner** — common-ports preset, web preset, custom ranges (`8000-8100`), bounded concurrency to avoid connection storms
- **Right-click context menu** per host: HTTP / HTTPS / SSH / VNC / RDP / SMB / AFP / Telnet / Ping in Terminal / Refresh / Wake-on-LAN / Copy IP/Hostname/MAC / Remove from list
- **Wake-on-LAN** — UDP magic packet, single host or bulk; successful sending does not confirm the device woke up
- **⌘C** copies selected IP(s) from the table
- **Multi-select** for bulk actions

</details>

<details>
<summary><strong>Inspector</strong> — open on demand, ping monitor, action grid</summary>

Select a host and choose Device Details (⌘⌥I). Details open in a sheet in compact windows and a resizable panel in wide windows.

- Header — device-type icon, IP, vendor status and estimated device type
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
- **`ipscanner` CLI** — headless binary inside the app bundle for cron / launchd / scripts (see [Command-line interface](../README.md#command-line-interface))
- **NetBIOS name fetcher** — Standard / Deep profiles pull Windows computer name + workgroup via UDP 137 when DNS is stale
- **Subnet calculator popover** — Tools menu; `/N` → network, broadcast, host range, count, dotted mask, wildcard
- **Signed in-app updates** — Sparkle checks the GitHub-hosted feed daily when enabled; manual checks are available in Help and Settings. Review release notes and choose installation in the native update window.
- **TTL column** — parsed from `/sbin/ping`, optional column with an OS hint tooltip
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
- Distributed outside the App Store with Developer ID signing and notarization

</details>

<details>
<summary><strong>Help & feedback</strong> — native help, Settings and issue reporting</summary>

- **Help** explains scan profiles, device information, snapshots, shortcuts and troubleshooting.
- **Settings** controls the default scan profile, appearance and automatic update checks.
- **Feedback** previews a bug or feature request before submitting it through Cloudflare to a public GitHub issue. A failed submission retains the draft.
- **Signed updates** and the refreshed radar icon ship with 1.3.0; [update distribution details](automatic-updates.md).

</details>

---

