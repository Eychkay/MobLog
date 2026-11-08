# MobLog source

Public source: https://github.com/Eychkay/MobLog

Source version: **1.1.3**. The release manifest links its exact repository commit. The Retail package
contains the `MobLog` and `MobLog_TrinityDB` directories. Both contain readable,
editable Lua source and their required license and attribution notices.

The repository includes the addon, generated catalog source, original artwork,
importers, editable intermediate loot data, manifests and packaging script.
Large original inputs are fetched separately at the versions recorded below.
They are not loaded from the Internet by the addon.

## Pinned upstream inputs

- TrinityCore **TDB1210.26091**:
  https://github.com/TrinityCore/TrinityCore/releases/tag/TDB1210.26091
  Archive: `TDB_full_1210.26091_2026_09_09.7z`.
  SHA-256: `fc5513334d7534a19f533124a95910193c8150379e5ed8d0db3e547ac2c5a3f5`.
- Selected AllTheThings source at commit
  `5ee014cf4cf4c9e4d4c8f3c0d2333e3ac695ad07`:
  https://github.com/ATTWoWAddon/AllTheThings/tree/5ee014cf4cf4c9e4d4c8f3c0d2333e3ac695ad07
  Exact input paths and SHA-256 hashes are recorded in
  `MobLog_TrinityDB/att-manifest.json` and `MobLog/map-manifest.json`.

Original GPL/MIT texts and attribution remain included in the addon directories.
The source fetcher checks the pinned hashes before accepting downloaded inputs.

## Rebuild

Clone the repository and select the matching release tag. Python 3.11 or newer
is required. Regenerating the catalog also requires `tar` with `.7z` support.

```sh
python tools/fetch_sources.py
python tools/att/import_att.py
python tools/att/import_maps.py
python tools/trinity/import_catalog.py
python tools/build_release.py
```

The first command downloads the pinned source inputs. Remaining commands can run
offline after those inputs are available. SQL is parsed as data, never executed.
For a ZIP of the checked-in addon files, only the final command is needed.

An optional complete offline source archive can be built explicitly with
`python tools/build_release.py --with-source` after fetching the source inputs.
Normal releases create only the installable ZIP; the release tag identifies the
matching public source. The addon does not require ATT or Python at runtime.

## Forever catalog

The Forever package contains `MobLog` and `MobLog_ForeverDB`.
The client selects its own catalog automatically. The Forever catalog uses the
pinned ATT commit above, specifically `db/Camelot/`, for NPC references, possible
drops and UI-map locations. Shared NPC names and creature types are taken from
the checked-in Trinity-derived NPC source. Retail loot, display IDs and spawn
geometry are excluded. Both GPL/MIT notices remain included. Exact input hashes
and coverage are recorded in `MobLog_ForeverDB/forever-manifest.json`.

```sh
python tools/forever/import_catalog.py --fetch
python tools/build_release.py --client forever
```

The first command fetches and verifies the pinned Forever inputs, then rebuilds
the separate catalog. It does not require ATT to be installed.
