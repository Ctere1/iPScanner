# Issue #10 — v1.2.0 exits without opening a window

## Confirmed packaging defect

The published `iPScanner-v1.2.0.dmg` was downloaded from GitHub on 2026-09-26.
Its SHA-256 matches GitHub's asset digest:

`4690edcf95676c418af570f57174b4070b6ebdbb33a8120eb8598a0c14f488c9`

- `hdiutil verify` passes.
- The bundle executable is `Contents/MacOS/iPScanner`.
- This is the only file in `Contents/MacOS`; there is no separate CLI.
- Running that executable prints the **ipscanner CLI usage** and exits with status 1.
- The executable is universal (`arm64`, `x86_64`).
- Minimum macOS version is 14.4.
- Its ad-hoc signature verifies; it has no Developer ID team identity.

The release workflow copied a binary named `ipscanner` into `Contents/MacOS`,
already containing `iPScanner`. On a case-insensitive filesystem this replaces
the GUI executable. The app therefore launches the argument-requiring CLI,
which exits immediately when Finder supplies no scan arguments. Signing alone
would not repair this package.

## Fix and regression guard

The CLI build product is named `ipscanner-cli` to prevent build-product collisions.
The distributed command lives at `Contents/Helpers/ipscanner`. The GUI remains
at `Contents/MacOS/iPScanner`. Build and bundle layout checks require both files
and reject identical contents. Release checks also exercise CLI `--help`, verify
both architectures, Developer ID signatures, Hardened Runtime, notarization,
and the app extracted from the final DMG.

## Limits

The artifact defect was reproduced by executing the published binary on an
Apple Silicon Mac running macOS 27.0. This is not a Sequoia 15.8 clean-install
test. Sequoia and macOS 14.4 verification, final Developer ID signing and a
browser-downloaded DMG first-launch test remain release gates.

## Suggested issue reply (not posted)

Thanks for reporting this. We found a packaging bug in the v1.2.0 DMG: the
command-line executable (`ipscanner`) overwrote the GUI executable
(`iPScanner`) on a case-insensitive filesystem. Opening the app therefore runs
the CLI without arguments and immediately exits. This explains why the
Gatekeeper workaround did not help.

We are preparing a corrected package with the CLI in a separate Helpers
directory, plus Developer ID signing and notarization. The replacement has
not been published yet. Once it is available, please try a fresh installation
on your Sequoia Macs. If it still fails, please share the output from
`/Applications/iPScanner.app/Contents/MacOS/iPScanner` and any matching
`iPScanner*.ips` report in `~/Library/Logs/DiagnosticReports`, after removing
personal information. We will keep this issue open until that is verified.
