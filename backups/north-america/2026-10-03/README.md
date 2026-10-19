# North America archive

US/CA railway packages, stations, route sections, sample journeys, branding,
source audits and removed test contracts are preserved here outside app inputs.
`manifest.json` records each original path, byte count and SHA-256. Mixed-country
files are archived before their North America records are removed.

The iOS application supports jp/tw/hk/mo/kr. It does not read this directory or
load, split, migrate or restore North America stores. Historical user files on
devices are not modified by this repository archive operation.

Additional archival inventories: `legacy-sources-manifest.json` records 21
shared-source originals under `legacy-sources/`; `raw-source-files-manifest.json`
records 810 further raw-source files, including 808 files under `app/data/raw/na-rail/`.
The latter hashes establish the current archive baseline, not an independent
comparison with the original pre-move bytes. These archives remain outside app inputs.

Payloads remain intact in this directory and in the complete local package
`backups/north-america/north-america-2026-10-03.tar.gz`. They are excluded from Git
source history; Git tracks this README, three manifests and `storage.json`.

The user-authorized [draft GitHub backup](https://github.com/Sager1145/JTM-iOS-App/releases/tag/untagged-842c18b341826f8983c5)
contains the independently verified package. It remains unpublished and requires
authenticated release access. GitHub returned `uploaded`, 864,038,006 bytes and
SHA-256 `51730f1dc783f19b1fa099611219acd5479f9a30f0c77a0d6335372ef486cb31`,
matching the local package. This backup does not declare refactor acceptance.

To restore outside app inputs:

```sh
gh release download north-america-backup-2026-10-03 --repo Sager1145/JTM-iOS-App \
  --pattern north-america-2026-10-03.tar.gz --dir /path/to/offline-backup
shasum -a 256 /path/to/offline-backup/north-america-2026-10-03.tar.gz
# Compare to the SHA-256 above before extracting.
tar -xzf /path/to/offline-backup/north-america-2026-10-03.tar.gz -C /path/to/offline-backup
python3 ios/tools/verify-north-america-archive.py --archive /path/to/offline-backup/2026-10-03
```

The package preserves 1,002 payloads (1,219,923,843 bytes) plus the README and
three manifests present at packaging time. This updated README and storage
metadata are tracked separately. The raw manifest establishes the current
archive baseline only; no pre-move byte proof is claimed. The app never loads
this directory, and the backup does not restore North America support.
