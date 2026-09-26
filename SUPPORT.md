# Help and support

Download the [latest signed release](https://github.com/canberkys/iPScanner/releases/latest).
Drag iPScanner into Applications, then open it. Version 1.3.0 fixes the v1.2.0
GUI/CLI packaging collision; old users should install 1.3.0 manually once.

- **Getting started:** [README](README.md#get-started) or Help → iPScanner Help.
- **Features and shortcuts:** [feature reference](docs/features.md).
- **Updates:** Help → Check for Updates; automatic checks can be changed in Settings.
- **Known limits:** [acceptance record](docs/acceptance-1.3.0.md).

## Reporting a problem

Use the [bug report form](https://github.com/canberkys/iPScanner/issues/new?template=bug_report.yml)
or Help → Report an Issue in the app. Include the app version, macOS version,
Mac architecture, reproduction steps and expected behavior. Search existing
issues first. The app's feedback relay also creates a **public** GitHub issue;
remove private IPs, MACs, credentials and identifying log details before sending.

For an opening failure, include the relevant crash report from
`~/Library/Logs/DiagnosticReports/` after redacting personal information. Do not
remove quarantine as a routine installation step; current releases are signed
and notarized.

## Common network questions

- A device that blocks probes may not appear. Try Standard rather than Quick.
- MAC/vendor information is not guaranteed across routed networks. Randomized MACs
  do not reliably identify a manufacturer; macOS restrictions can prevent ARP access.
- Device types are estimates. Open details to review the evidence.
- Sending a Wake-on-LAN packet does not prove a device woke up.

For a missing capability, use the [feature request form](https://github.com/canberkys/iPScanner/issues/new?template=feature_request.yml).
