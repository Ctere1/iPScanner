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

## Release verification

Version 1.3.0 build 3 keeps the GUI and CLI separate. The universal app and DMG
passed Developer ID verification, Apple notarization, stapling and Gatekeeper.
The app opens on this Apple Silicon macOS 27 host. Regression tests reject the
original overwritten-executable layout. The exact Sequoia 15.8 environment from
the report was not available; that platform validation remains open.

The confirmed artifact defect is fixed in the 1.3.0 release. The reporter is
invited to comment if opening still fails on their Sequoia machines.
