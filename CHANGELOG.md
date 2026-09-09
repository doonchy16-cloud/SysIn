# Changelog

All notable SysIn changes are recorded here.

## 1.1.0 — 2026-09-08

### Added

- Public hybrid CLI with canonical commands such as `sysin gpu` and Windows-style aliases such as `SysIn -GPU`.
- Version, help, and about commands.
- One-shot `snapshot` mode and snapshot support for CPU, GPU, memory, and process views.
- Static `system`, `storage`, `network`, `sensors`, and `capabilities` views.
- Per-user configuration with strict validation for FPS and stable update preferences.
- `doctor` diagnostics covering Windows runtime, PowerShell version, required runtime files, current-user PATH registration, configuration validity, and provider availability.
- Safe per-user installer using `%LOCALAPPDATA%\Programs\SysIn` by default.
- Safe uninstaller that removes known SysIn runtime files and preserves unknown files and configuration by default.
- Stable-channel `check-update` and `update` commands.
- HTTPS-only release-manifest validation and SHA-256 verification before runtime replacement.
- Staged updater with backups and rollback behavior on replacement failure.
- Published `release/manifest.json` with exact SHA-256 hashes for the V1.1 runtime.
- Zero-dependency PowerShell parser and behavior test harness running on Windows GitHub Actions.

### Preserved

- Original live terminal dashboard behavior with Overview, CPU, GPU, Memory, and Processes pages.
- 20 FPS default render target with lower FPS modes available from the dashboard.
- Pause, reset, page-navigation, and quit controls.
- Graceful `N/A`/partial reporting when optional GPU or sensor providers are unavailable.

### Safety

- Default installation requires no administrator privileges.
- Installer and uninstaller modify only the current-user PATH when PATH changes are enabled.
- No Windows service or scheduled task is installed.
- No permanent execution-policy change is made.
- Update files are fully staged and hash-verified before installed runtime files are replaced.
- Unknown files in the install directory are not recursively deleted during uninstall.

### Verification notes

- Windows CI exercises parsing, CLI/config behavior, telemetry command paths, diagnostics, installer/uninstaller safety, updater validation and rollback, and release-manifest integrity.
- Optional hardware telemetry remains dependent on providers actually exposed by the target Windows system; CI coverage is not a claim of universal sensor availability.
