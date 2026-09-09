# SysIn

**SysIn 1.1.0** is a Windows system-intelligence CLI and live terminal dashboard for CPU, GPU, memory, storage, network, process, sensor, and system telemetry.

V1.1 keeps the original live dashboard and adds a public command surface, per-user installation, configuration, diagnostics, and a SHA-256-verified stable update path.

## Requirements

- Windows
- Windows PowerShell 5.1+ or PowerShell 7+
- No administrator privileges are required for the default installation

SysIn uses Windows telemetry providers available on the current machine. Some GPU, temperature, fan, power, battery, or vendor-specific values may report `N/A` or partial capability when the underlying provider is unavailable.

## Install

The default install location is:

```text
%LOCALAPPDATA%\Programs\SysIn
```

The installer adds that directory to the **current user's PATH only**.

### Public install

From PowerShell:

```powershell
$installer = Join-Path $env:TEMP 'SysIn-install.ps1'
Invoke-WebRequest 'https://raw.githubusercontent.com/doonchy16-cloud/SysIn/main/install.ps1' -OutFile $installer
& $installer
```

The bootstrap installer retrieves the stable release manifest over HTTPS, downloads the known V1.1 runtime files into staging, verifies every runtime file against its published SHA-256 hash, and only then replaces installed files. Existing SysIn-owned files are backed up transactionally and restoration is attempted if replacement fails.

The installer does **not** create a Windows service, scheduled task, machine-wide PATH entry, or permanent execution-policy change.

### Install from a local clone

```powershell
git clone https://github.com/doonchy16-cloud/SysIn.git
cd SysIn
pwsh -NoProfile -File .\install.ps1 -SourceRoot .
```

On Windows PowerShell 5.1, use `powershell.exe` instead of `pwsh`.

## Quick start

```powershell
sysin version
sysin overview
sysin cpu
sysin gpu
sysin memory
sysin snapshot
sysin doctor
```

SysIn supports both canonical commands and Windows-style convenience aliases. For example, these are equivalent:

```powershell
sysin gpu
SysIn -GPU
```

## Commands

| Command | Purpose |
| --- | --- |
| `overview` | Live system overview dashboard |
| `cpu` | CPU telemetry dashboard |
| `gpu` | GPU telemetry dashboard |
| `memory` | Memory telemetry dashboard |
| `storage` | Storage telemetry |
| `network` | Network telemetry |
| `processes` | Process telemetry dashboard |
| `sensors` | Available temperature, fan, and power telemetry |
| `system` | Static Windows and hardware information |
| `snapshot` | One non-interactive telemetry snapshot |
| `doctor` | Validate runtime, PATH, configuration, and providers |
| `capabilities` | Show which telemetry providers are available |
| `version` | Show the installed version and channel |
| `check-update` | Check the published stable manifest |
| `update` | Install a verified stable update |
| `config` | Read or change per-user configuration |
| `help` | Show CLI help |
| `about` | Show SysIn product information |

Common aliases include `-CPU`, `-GPU`, `-Memory`, `-Storage`, `-Network`, `-Processes`, `-Sensors`, `-System`, `-Snapshot`, `-Version`, `-CheckUpdate`, `-Update`, and `-Help`.

Run:

```powershell
sysin help
```

for the command summary shipped with the installed version.

## Snapshot mode

Use `snapshot` for a single overview sample:

```powershell
sysin snapshot
```

You can also request a one-shot page from a dashboard command:

```powershell
sysin cpu -Snapshot
sysin gpu -Snapshot
sysin memory -Snapshot
sysin processes -Snapshot
```

## Live dashboard controls

The dashboard uses the configured `fps` value as its launch-time render target. The default configuration is **20 FPS**.

| Key | Action |
| --- | --- |
| `1` | Overview |
| `2` | CPU |
| `3` | GPU |
| `4` | Memory |
| `5` | Processes |
| `F` | Cycle render target: 20 → 10 → 5 → 1 FPS |
| `P` | Pause/resume sampling |
| `R` | Reset tracked min/peak values |
| `Q` or `Esc` | Exit |

An explicit launch-time render target from 1 through 20 can be requested with `-FPS`; it overrides the configured `fps` value for that launch:

```powershell
sysin overview -FPS 10
```

## Diagnostics

```powershell
sysin doctor
sysin capabilities
```

`doctor` checks:

- Windows runtime
- PowerShell version
- Required SysIn runtime files
- current-user PATH registration
- configuration validity
- telemetry-provider availability

A machine can legitimately receive a `PARTIAL` provider result when optional GPU or sensor providers are unavailable. SysIn does not fabricate missing telemetry.

## Configuration

Per-user configuration is stored under:

```text
%LOCALAPPDATA%\SysIn\config.json
```

Commands:

```powershell
sysin config show
sysin config get fps
sysin config set fps 10
sysin config set updateChannel stable
sysin config set updateCheck manual
sysin config reset
sysin config path
```

V1.1 accepts these keys:

- `fps`: integer from `1` through `20`; used as the dashboard launch-time FPS when no explicit `-FPS` override is supplied
- `updateChannel`: `stable`
- `updateCheck`: `manual` or `daily`

`updateCheck` is a configuration preference only in V1.1. SysIn does not install a background service or scheduled task to perform update checks.

## Updates

Check the stable channel:

```powershell
sysin check-update
```

Install a newer stable version:

```powershell
sysin update
```

The updater:

1. retrieves the stable manifest over HTTPS;
2. validates manifest structure, target paths, URLs, and hashes;
3. stages all runtime files;
4. verifies every staged SHA-256 before touching the installation;
5. backs up existing target files;
6. replaces the verified targets; and
7. attempts rollback if replacement fails.

The published manifest is `release/manifest.json`.

## Uninstall

Default uninstall removes SysIn-owned runtime files and the current-user PATH entry while preserving per-user configuration:

```powershell
& "$env:LOCALAPPDATA\Programs\SysIn\uninstall.ps1"
```

To remove the per-user configuration as well:

```powershell
& "$env:LOCALAPPDATA\Programs\SysIn\uninstall.ps1" -PurgeConfig
```

Unknown files in the install directory are preserved; the uninstaller does not recursively delete arbitrary contents.

## Privacy and safety model

SysIn V1.1 is read-only by default for system inspection. It does not install a service, background agent, or scheduled task, and it does not silently change machine-wide environment settings or execution policy.

Telemetry displayed by SysIn is collected locally from Windows and available hardware/provider interfaces. Network access is used when you explicitly install, check for updates, or update from the GitHub-hosted release source.

## Development and verification

The repository includes a zero-dependency PowerShell test harness and Windows GitHub Actions CI. The suite checks PowerShell parsing, CLI behavior, configuration validation, live telemetry command paths, installer/uninstaller safety, updater verification/rollback behavior, doctor diagnostics, and release-manifest hashes.

CI execution validates behavior on the hosted Windows runner; it is not a claim that every optional hardware sensor or vendor provider exists on every Windows machine.

## Version

```powershell
sysin version
```

Current stable version: **1.1.0**