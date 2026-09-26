# Pinned IEEE sources

These files are retained from the existing project. Their original retrieval date
was not recorded; `sourceDate` is explicitly null. Index validation date:
2026-09-26. Do not interpret this date as the registry publication date.

Run `python3 scripts/build-vendor-db.py` to regenerate the compact app index.
`--check` verifies exact bytes, assignment bounds and minimum record counts.
The index embeds source URLs and SHA-256 digests. The build and packaging checks
reject stale indexes and bundled raw registry files. No database download occurs
at runtime. MA-S takes precedence over MA-M and MA-L.

- `oui.txt`: SHA-256 `8634b26625c50411a905aef99724259f6f87c245841497628cf1f0786f764b52`
- `oui28.txt`: SHA-256 `2d600725958719293d37a673f4d864a9c3dc791f32e221cece684b4904e31b3c`
- `oui36.txt`: SHA-256 `183c97b838264ccff5f779c9fec846adaf24dc3bf17c2d47ce1ef6a1dd9f478b`
