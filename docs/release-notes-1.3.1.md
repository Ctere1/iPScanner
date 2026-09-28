# iPScanner 1.3.1

Released 2026-09-28. A focused update for scanning, labels and everyday actions.

## Fixed

- Restore **Add Label / Edit Label** in the device context menu. Labels survive MAC enrichment and snapshot saves.
- Keep scan controls and status in place when results are empty, and explain active filters while scanning.
- Limit ping process duration and avoid ping name resolution to reduce unnecessary waits on unresponsive addresses.
- Port Scan uses the devices you right-clicked, even when another row is selected.
- Selecting a saved network replaces previously imported file targets.
- Snapshot comparisons no longer count previously unresponsive addresses as missing devices; change badges and counts stay current.
- Show file-save failures and keep the inspector's label field in sync with edits.

## Changed

- A compact installer window with Retina artwork and clear drag-to-Applications instructions.
- Cleaned up repository artwork and documentation.

## Update and compatibility

Use **Check for Updates…** in iPScanner 1.3.0 to download and install this version.
Users of 1.2.0 must install the DMG manually. Universal Apple Silicon + Intel;
macOS 14.4 deployment target. Developer ID signed and notarized, with an
Ed25519-signed update archive. Existing settings and snapshot formats are retained.

## Validation and limitations

201 automated application tests passed, including 11 new regressions. Universal
GUI/CLI builds and packaged Quick, Standard and Deep localhost scans passed.
The new UI still needs a full visual pass and full-subnet performance comparison.
Intel hardware, older macOS runtime coverage and macOS 27 MAC-access limitations
remain as documented. Production 1.3.0 → 1.3.1 in-app installation is not yet
claimed as tested; the owner will perform it after publication.
