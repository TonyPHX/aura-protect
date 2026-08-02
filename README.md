# Aura Protect

A fast native macOS ClamAV front end. The official universal ClamAV runtime is bundled; Homebrew is not required.

## Build

```sh
chmod +x build_app.sh
./build_app.sh
```

Open `outputs/Aura Protect.app`. The app uses its bundled ClamAV engine and can also discover external installations.

The bundled runtime is ClamAV 1.5.3 from the official Cisco-Talos release. Its source, verified package digest, and GPLv2 license are recorded under `Vendor/ClamAV` and included in the app bundle.

## Safety

Detected files are reported but never automatically deleted or moved. Review detections before taking action; false positives are possible.
