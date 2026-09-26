# Automatic updates

The GUI uses Sparkle 2.9.6, as vLens does. The CLI has no Sparkle dependency.
One updater is shared by Settings and the menu. Explicit existing automatic-check
preferences migrate; new installations use Sparkle's permission prompt. Optional
checks run daily while the app is running. Installation follows the user's choice
in Sparkle's native window, which also shows release notes.

## Trust and packaging

- HTTPS feed: `https://raw.githubusercontent.com/canberkys/iPScanner/main/appcast.xml`.
- Developer ID signing, Hardened Runtime, notarization and stapling remain required.
- Sparkle's nested helpers are signed before its framework and the outer app.
- Ed25519 update signatures use the **ipscanner** Keychain account. The private key
  is never embedded or committed. `SUPublicEDKey` is the public verification key.
- `SUVerifyUpdateBeforeExtraction` requires signature verification before unpacking.
- Build numbers must increase; the published 1.3.0 release uses build **3**.
- Debug disables Hardened Runtime for ad-hoc local builds; Release keeps it enabled.

## Release order

1. Run `scripts/build-dmg.sh VERSION`. It tests, signs, notarizes, staples and
   verifies the DMG, then uses Sparkle's `generate_appcast` with embedded notes.
   Every step must succeed. An appcast containing the archive’s Ed25519 signature is produced under `update-feed/`.
2. Test installation from an older build, plus cancellation and invalid-signature
   rejection, before claiming the update path is validated.
3. Publish the exact DMG and checksum to the matching GitHub Release.
4. Verify that the public DMG is accessible and its checksum matches.
5. Only then promote the generated `appcast.xml` to the main branch. Never expose
   an update pointing at a draft or missing asset.

The public feed advertises the verified v1.3.0 build 3 release. The previous v1.2.0 app has no
Sparkle installer, so users must install 1.3.0 manually once.

## CI credentials

The release workflow additionally expects the `SPARKLE_PRIVATE_KEY` environment
secret (the base64 key format accepted by Sparkle). Configure it through a secure
secret-management flow, never in an issue or chat. It is written to a private
runner-temporary file and removed with the other signing credentials. Local
builds use the Keychain directly. CI secret provisioning is not yet verified.

Sources: [Sparkle setup](https://sparkle-project.org/documentation/),
[SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/).

## Local validation — 2026-09-26

190 application tests passed after integration. A Developer ID signed test copy
(version 1.2.9/build 1, localhost feed) downloaded the notarized build 2 DMG and
installed/relaunched as 1.3.0/build 2. The installed GUI hash matched the target.
An intentionally invalid Ed25519 signature was rejected with Sparkle's update
error. This tests a local full update, not a production GitHub download or delta.
Build 3 subsequently packages the current help copy and Sparkle license notice;
its app and DMG both passed notarization and final package validation.
