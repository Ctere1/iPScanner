# iPScanner product tour

[Back to the project](../../README.md)

These captures show the native 1.3.0 app with a fictional saved snapshot.
No user's devices, network addresses or MAC records are included. The first row
uses 127.0.0.1 so opening its inspector only pings the local Mac. Other addresses
come from the documentation range 192.0.2.0/24. Do not start a scan of the fixture.

## Walkthrough

![Results, tag search, device details, export and appearance](demo.gif)

This approximately 18-second animated walkthrough is assembled from five real UI captures;
it does not represent live discovery or elapsed scan time.

1. **Results:** responding-state sample devices, labels, names and ports.
2. **Search:** `#lab` narrows the table to two labeled devices.
3. **Details:** saved data is marked historical; the device type explains its evidence.
4. **Export:** CSV, JSON, IP:Port and text report options.
5. **Appearance:** the same results in dark appearance.

[Static tour cover](demo-poster.jpg)

## Try it yourself

Download [demo.ipscan.json](demo.ipscan.json) with GitHub's **Download raw file**
button, then use **File → Open Scan…** (`⌘O`). Loading a snapshot does not run
network discovery. Existing labels may be merged with the sample's labels, so use
a separate macOS test account if you want a completely isolated demo.

## Screenshots

### Compact results

![Light appearance](results-light.jpg)

![Dark appearance](results-dark.jpg)

### Search labels and tags

![Tag search showing two matching devices](search-tags.jpg)

### Device details

<img src="device-details.jpg" width="380" alt="Device details sheet with historical vendor status and estimated Mac evidence">

[Wide window with the right-side inspector](wide-inspector.jpg)

### Export

![Export options](export-options.jpg)

## Refreshing the media

Capture the actual app with this fixture in an isolated app identity or test
account. Keep network/device details fictional and verify every image before
committing. Capture via the normal macOS UI; do not redraw application controls.

`scripts/build-demo-media.py` assembles the walkthrough from the JPEG captures.
It requires Pillow only as a documentation build tool; the app has no added
runtime dependency. The SVG header is editable text, separate from the existing
app icon. A new app logo is not part of this media update.
