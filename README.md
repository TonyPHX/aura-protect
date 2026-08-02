# Aura Protect

A fast native macOS ClamAV front end. The official universal ClamAV runtime is bundled; Homebrew is not required.

The Aura Protect artwork in `Assets` is packaged as the application, Finder, and Dock icon.

## Build

```sh
chmod +x build_app.sh
./build_app.sh
```

Open `outputs/Aura Protect.app`. The app uses its bundled ClamAV engine and can also discover external installations.

The bundled runtime is ClamAV 1.5.3 from the official Cisco-Talos release. Its source, verified package digest, and GPLv2 license are recorded under `Vendor/ClamAV` and included in the app bundle.

## Safety

Detected files are reported but never automatically deleted or moved. Review detections before taking action; false positives are possible.

## Open source and attribution

Aura Protect is free and open-source software licensed under the [GNU General Public License, version 2 only](LICENSE). Copyright © 2026 Tony Simek and Aura Protect contributors.

Aura Protect is powered by [ClamAV](https://www.clamav.net), which is maintained by the ClamAV Team and Cisco Systems, Inc. The bundled ClamAV 1.5.3 runtime is licensed under GPLv2; its corresponding [source code](https://github.com/Cisco-Talos/clamav/tree/clamav-1.5.3), license, and official third-party notices are identified in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `Vendor/ClamAV/licenses`.

Aura Protect is an independent community project and is not affiliated with, sponsored by, or endorsed by Cisco Systems or the ClamAV project. Product names and trademarks belong to their respective owners.
