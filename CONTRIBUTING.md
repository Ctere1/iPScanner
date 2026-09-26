# Contributing to iPScanner

Start with the [feature reference](docs/features.md), [open issues](https://github.com/canberkys/iPScanner/issues)
and [current validation limits](docs/acceptance-1.3.0.md). For a large feature,
open a feature request first so its scope can be discussed.

## Local development

Use macOS, Xcode with a macOS 14.4-compatible SDK and XcodeGen:

```sh
brew install xcodegen
xcodegen generate
open iPScanner.xcodeproj
```

Edit `project.yml`; generated Xcode project files are not committed. Sparkle is
pinned there for the GUI. The bundled CLI remains separate and builds as
`ipscanner-cli` to avoid the case-insensitive filename collision fixed in #10.

## Before a pull request

- Explain the user-visible problem and how the change fixes it.
- Preserve saved preferences, snapshot compatibility and CLI arguments.
- Add meaningful regression coverage for behavior changes. Use localhost fixtures
  or networks you own; never scan third-party networks as a test.
- For UI changes, include screenshots with fictional device data.
- Record user-visible changes under `Unreleased` in `CHANGELOG.md`.
- Never include credentials, private scan exports or personal network details.

Relevant checks:

```sh
xcodebuild test -scheme iPScanner -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
python3 scripts/build-vendor-db.py --check
bash scripts/tests/bundle-layout.sh
(cd feedback-relay && npm test)
```

Run checks appropriate to the change and state what was not tested. A universal
build does not establish Intel or every macOS runtime compatibility.

## Release changes

Release signing is maintained separately from ordinary contributions. Follow
[automatic update distribution](docs/automatic-updates.md) and the
[signing guide](docs/signing-guide-tr.md). Do not publish an appcast entry until
its signed release asset is public and verified. Sparkle's private key and Apple
credentials belong in Keychain or protected CI secrets, never source control.
