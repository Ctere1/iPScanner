# Installer background

`background.png` and `background@2x.png` are the standard and Retina artwork.
Regenerate both with `scripts/render-dmg-background.swift` (see the signing guide).
Finder supplies the real draggable app and Applications icons; these are not
painted into the background. `scripts/dmg-settings.py` defines their positions.

Do not hide the app extension with SetFile or add a custom icon to the signed
bundle: this creates FinderInfo metadata that fails strict signature validation.
The release pipeline verifies the application after the disk-image round trip.
