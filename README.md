# PreferenceLoader

A modernized `PreferenceLoader` fork focused on rootless jailbreaks and newer iOS Settings behavior (including iOS 26-era changes).

## What This Fork Fixes

- Works on modern rootless environments (`/var/jb` layout).
- Supports modern Settings controller selection instead of relying on a single legacy class.
- Avoids library-name collisions with Apple's own `libprefs` by using an internal helper library (`plprefs`).
- Uses rootless-compatible dynamic linking for substrate compatibility.
- Keeps tweak filter matching broad enough for modern Settings app variants.

## Project Layout

- `Tweak.xm`: main Settings injection logic.
- `prefs.xm`: helper library for loading PreferenceLoader entries/specifiers.
- `PreferenceLoader.plist`: tweak injection filter.
- `Makefile`: Theos build/packaging entrypoint.
- `control`: Debian package metadata.

## Build

Requirements:

- Theos setup
- iOS SDK available to Theos (project currently targets `iPhoneOS16.5.sdk`)

Build rootless package:

```sh
make clean
make package ROOTLESS=1
```

Package output:

```text
packages/preferenceloader_<version>_iphoneos-arm64.deb
```

## Install

On device:

```sh
dpkg -i /path/to/preferenceloader_<version>_iphoneos-arm64.deb
killall -9 Preferences
sbreload
```

## Notes

- This repository is tuned for this fork's workflow and local tooling.
- Build produces universal `arm64` + `arm64e` binaries.

## License

LGPL-3.0 (see `LICENSE`).
