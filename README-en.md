<div align="center">

# OhGithubLost

**GitHub repository manager · Current version: see [Releases](https://github.com/OGL-Teams/OhGithubLost/releases)**

Android · Windows · Linux · Web

Browse and edit repositories, handle Issues / Pull Requests / Releases / Actions, manage Gists — without opening a browser.

[![Release](https://img.shields.io/github/v/release/OGL-Teams/OhGithubLost?label=release&color=blue)](https://github.com/OGL-Teams/OhGithubLost/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](#contributing)
[![Issues](https://img.shields.io/github/issues/OGL-Teams/OhGithubLost)](https://github.com/OGL-Teams/OhGithubLost/issues)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-informational)](#platform-support)
[![i18n](https://img.shields.io/badge/i18n-6%20languages-informational)](docs/I18N.md)

<br>

<img width="49%" alt="Star history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/star-history.png">
<img width="49%" alt="Commit history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/commit-history.png">

<sub>The `stats` branch refreshes these charts every 10 minutes and purges the jsDelivr cache afterwards.</sub>

</div>

<br>

> Screenshots pending: main interface (home / repository / code editor) as a triptych, placed mid-file.

## Contributing!

If you would like to contribute code, contact us on QQ 3449776312. We will open a dedicated branch for you, and after one week of quality review decide whether to bring you into mainline development.

We are also looking for help with outreach and with Apple-platform builds — reach out and we will add you to the acknowledgements.

> Before submitting, read [`AGENTS.md`](AGENTS.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): layering violations, non-localized strings, motion bypasses and quality anti-patterns are all blocked by CI.

## About

OhGithubLost (OGL) is a GitHub client built with Flutter. It puts repository browsing and commits, Issue and PR handling, Release and Action monitoring, and Gist management into a native app window, so day-to-day work no longer needs a browser tab. Two engineering rules anchor the project: data reliability and failures must be visible — no silent degradation, no bundled acceleration proxies, no hiding merge conflicts.

Users install from release artifacts; developers can read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the layer structure and dependency gates.

## Features

- **Full repository support**: directory browsing, file preview and README rendering; create, edit, delete, rename (including directories); commits and conflict handling.
- **Collaboration panel**: Issues / Pull Requests / Releases / Actions / Gists, including PR diffs, Action logs and manual workflow dispatch.
- **Multi-account and token safety**: switch accounts freely; tokens live only in the system keystore on-device, are masked in UI and logs, and are deleted on sign-out.
- **Downloads and drafts**: multi-connection chunked downloads with resume; the editor persists uncommitted drafts and restores them when you reopen the file.
- **Network resilience**: built-in DoH, automatic retry and rate-limit backoff; failures are reported as they are, never silently swallowed. Release-asset downloads may use a **user-supplied acceleration proxy** (off by default; the app ships no proxy of its own).
- **Internationalization and motion**: 6 interface languages (Simplified Chinese / Traditional Chinese / English / Deutsch / Français / Русский); zero hardcoded strings, enforced by CI. Motion has four levels (silent / restrained / standard / full) — lowering the level cuts cost, not effects.

## Platform support

| Platform | Status | Artifacts |
| --- | --- | --- |
| Android | Supported | 4-ABI APKs (arm64-v8a / armeabi-v7a / x86_64 / universal) + AAB |
| Windows | Supported | x64 / arm64 |
| Linux | Supported | x64 / arm64; deb / rpm / AppImage; **glibc ≥ 2.35** |
| Web | Supported | <https://oghapp.344977.xyz/> (dart2wasm primary, dart2js fallback) |
| macOS / iOS | Discontinued | Last supported release: v5.3.0 |

Not supported: 32-bit desktop, musl-libc, Windows 7 / 8.1.

## Install

Download from [**Releases**](https://github.com/OGL-Teams/OhGithubLost/releases). Every artifact ships as both `.zip` and `.7z` (max compression) — either works.

| Platform | File | Install |
| --- | --- | --- |
| Android | `OGL-<version>-Android.<abi>.zip` / `.AAB.zip` | Unzip and install the APK |
| Windows | `OGL-<version>-Windows.<arch>.zip` | Run `oghl.exe` from the unzipped folder |
| Linux | `OGL-<version>-Linux.<arch>.deb` / `.rpm` / `.AppImage` | `sudo dpkg -i *.deb` or `sudo rpm -i *.rpm`; AppImage runs directly (no FUSE needed) |
| Web | Use online | <https://oghapp.344977.xyz/> |

`<version>` looks like `v8.0.0`; `<arch>` looks like `x64` / `arm64`.

## Build from source

Requires Flutter **3.47.5** (Dart 3.13) plus the toolchain for your target platform.

```bash
flutter pub get
flutter run                    # development
flutter build apk              # Android
flutter build windows          # Windows
flutter build linux            # Linux (built on the host; glibc floor documented in CI)
flutter build web --release --wasm --no-web-resources-cdn   # Web
```

## Architecture

The codebase has five layers with strictly downward dependencies (`surface → domain → base → kernel`; `platform` depends only on `kernel`), enforced in CI by `tool/layer_audit.py --fatal`, alongside i18n, motion-level and performance anti-pattern gates. Full details in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

```
lib/
  kernel/    boot layer    boot manifest, Ed25519 signing, trust root
  base/      hardware layer  network (DoH / retry / backoff), disk (atomic writes / cache)
  domain/    logic layer     GitHub API, local deep info
  surface/   interaction layer  UI, settings, i18n
```

## Usage

First-time users: [`docs/USAGE.md`](docs/USAGE.md) covers sign-in, first-run permission setup, home / search / repository pages, the code editor (including conflict handling), download management, the notification center, settings and troubleshooting.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — task-driven usage guide with troubleshooting
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layered architecture and dependency gates
- [`docs/NETWORK.md`](docs/NETWORK.md) — network overview (egress hosts / resource fetching / Web limitations)
- [`docs/I18N.md`](docs/I18N.md) — localization maintenance manual
- [`CHANGELOG.md`](CHANGELOG.md) — full version history
- <https://oglb.344977.xyz/> — changelog site (per-version, bilingual)

## Documentation map

- [`docs/README.md`](docs/README.md) — categorized docs index (normative / design / audits / operations)
- [`AGENTS.md`](AGENTS.md) — engineering overview (layering, gates, quantified standards)
- [`docs/QUALITY_STANDARD.md`](docs/QUALITY_STANDARD.md) — quality standard: 59 principles
- [`docs/AUDIT_INDEX.md`](docs/AUDIT_INDEX.md) — audit master index
- [`docs/CI_BUILD_BASELINE.md`](docs/CI_BUILD_BASELINE.md) — measured CI build baseline
- [`release_notes/`](release_notes/) — per-version release notes (bilingual)

## License

Licensed under the [Apache License 2.0](LICENSE). Third-party dependency notices live in [`NOTICE`](NOTICE) and the in-app Licenses page.

<br>

<sub>Star and commit history are shown in the charts above; data comes from `history.json` on the `stats` branch.</sub>
