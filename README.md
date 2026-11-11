# WSUS Offline Update - Community Edition (12.7 fork, US English)

Download Microsoft updates once on a computer with internet access, then install them on
computers that have no (or limited) internet access.

This repository is a fork of **WSUS Offline Update - Community Edition 12.7 (b82, beta)**.
Upstream development stopped in early 2025. This fork keeps it working for current
Windows 11 releases, is English-only, and depends only on Microsoft and on tools bundled in
this repository (see [Security and third-party code](#security-and-third-party-code)).

## What this fork changes

| Change | Where |
| --- | --- |
| Windows 11 23H2, 24H2, 25H2 and 26H2 as download targets, grouped like Windows 10 "2004/.../22H2": one checkbox per servicing base, "22H2/23H2" (build 22621) and "24H2/25H2/26H2" (build 26100) | Generator, download script, Linux scripts |
| Feature upgrade 24H2 -> 25H2 via enablement package KB5054156 | `client/static/StaticUpdateIds-BuildUpgrades.txt`, `client/UpdateInstaller.au3` |
| Feature upgrade 24H2/25H2 -> 26H2 via enablement package KB5121794 (needs revision 9278 or later, i.e. KB5120998) | same files |
| Microsoft Defender platform update (KB4052623) is downloaded with the definitions and installed before them when newer than the installed platform | `static/StaticDownloadLink-wddefs-*.txt`, `cmd/DownloadUpdates.cmd`, `client/cmd/DoUpdate.cmd`, `client/cmd/DetermineSystemProperties.vbs` |
| Fix: Defender files were saved as `mpam-fe.exe@packageType=...` (Microsoft's links now redirect to URLs with a query string), so the installer never found them; they are now renamed to `mpam-fe.exe` / `updateplatform.exe` | `cmd/DownloadUpdates.cmd` |
| Hash check is skipped with a warning when the integrity database has no entry for a file (fixes a hang on newer Edge installers) | `client/cmd/InstallOSUpdate.cmd` |
| Feature-upgrade "tried" markers are cleared at the start of each run | `client/cmd/DoUpdate.cmd` (see [Known issues](#known-issues)) |
| **English only**: the German interface, German documents and German comments were removed; German language packages were removed from the default download lists | `UpdateGenerator.au3`, `client/UpdateInstaller.au3`, `static/`, `doc/` |
| **No community repository**: no online version check, no self-update, no definition updates ("SDD") and no `mkisofs.exe` download from the WSUS Offline GitLab | `UpdateGenerator.au3`, `cmd/DownloadUpdates.cmd` |
| **Built-in Windows tools instead of third-party ones**: ISO images via IMAPI2 (`cmd/BuildIsoWithImapi.ps1`), zip handling via `tar.exe` / .NET, admin check via `fltmc.exe`; `unzip.exe`, `upx.exe`, `IfAdmin.exe` and the optional aria2 downloader were removed | `cmd/`, `client/cmd/`, `bin/`, `client/bin/` |
| `MakeRelease.cmd` builds the ready-to-run folder and the zip in one step, needs nothing installed, can be double-clicked | repo root |

## Supported targets

| Platform code | Covers |
| --- | --- |
| `w62-x64` | Windows Server 2012 |
| `w63`, `w63-x64` | Windows 8.1, Windows Server 2012 R2 |
| `w100`, `w100-x64` | Windows 10 (1507-22H2), Windows 11 (21H2-26H2), Windows Server 2016/2019/2022 |
| `o2k13` | Office 2013 (per language) |
| `o2k16` | Office 2016 |

The installer refuses to run on XP, Vista, 7, Windows 8 (client) and Server 2003/2008/2008 R2.

**Download / build computer:** Windows 10 version 1803 or later, or Windows Server 2019 or later
(uses Windows' built-in `tar.exe`, PowerShell and IMAPI2).

## How it works

```
 DOWNLOAD SIDE (internet)                         TARGET COMPUTER (offline)
 ------------------------                         -------------------------
 UpdateGenerator.exe  (settings window)            client\UpdateInstaller.exe  (settings window)
        |                                                 |
        v                                                 v
 cmd\DownloadUpdates.cmd <platform> <lang> [opts]   client\Update.cmd -> client\cmd\DoUpdate.cmd
   1. download Microsoft catalog wsusscn2.cab          1. detect OS, build, WUA, .NET, Edge
   2. extract package.xml, filter with xslt\*.xsl      2. servicing stack
   3. drop superseded + excluded updates (exclude\)    3. feature upgrade (enablement package)
   4. download with wget into client\<platform>\...    4. Windows Update agent, Edge, .NET, ...
   5. optional: check signatures, build hash lists     5. offline WUA scan against wsusscn2.cab
        |                                              6. install missing updates (wusa / DISM)
        +---- copy client\ to USB / share / ISO ---->  7. "reboot and run again" until done
```

Both settings windows are AutoIt scripts (`.au3`); the actual work is done by batch files,
VBScript and PowerShell. Everything the target computer needs lives under `client\`.

## Quick start

1. **Build**: double-click `MakeRelease.cmd` (or run `MakeRelease.cmd [version]`). It compiles
   the two `.exe` files and creates, next to the repo folder:

   ```
   ..\wsusoffline-release\               ready to run: UpdateGenerator.exe is in here
   ..\wsusofflineCE12.7.zip              the same release as a zip, for handing out
   ..\wsusofflineCE12.7_hashes.txt       hashes of the zip
   ```

   Without a version it uses the one in `static\SelfUpdateVersion-this.txt`. The ready-to-run
   folder is updated in place, so updates you have downloaded into it are kept (files of
   removed features are deleted from it). Close UpdateGenerator/UpdateInstaller from that
   folder before rebuilding, or the copy fails.

2. **Download** updates in the built copy: run `UpdateGenerator.exe`, or from its `cmd` folder:

   ```
   DownloadUpdates.cmd w100-x64 glb /verify
   ```

   Windows 10/11 x64 alone needs tens of GB. Progress is logged to `log\download.log`.

3. **Transfer** the `client\` folder to the target (USB drive, network share, or an ISO made with
   `cmd\CreateISOImage.cmd`; `cmd\CopyToTarget.cmd` copies only what one platform needs).
   ISO images use the UDF file system, so files larger than 4 GB are fine.

4. **Install**: on the target, run `client\UpdateInstaller.exe` as administrator. When it asks
   for a reboot, reboot and run it again. Repeat until it reports nothing left to install.
   The log is `%SystemRoot%\wsusofflineupdate.log`.

## Command-line reference

### Download: `cmd\DownloadUpdates.cmd`

```
DownloadUpdates.cmd {w62-x64 | w63 | w63-x64 | w100 | w100-x64 | o2k16} glb [options]
DownloadUpdates.cmd o2k13 {enu | fra | ...} [options]
```

| Option | Effect |
| --- | --- |
| `/verify` | Check digital signatures (Sysinternals sigcheck) and build hash lists for the client |
| `/includedotnet` | Include .NET Framework installers and updates |
| `/includewddefs` | Include Microsoft Defender definitions and the Defender platform update |
| `/seconly` | Security-only updates where Microsoft offers them |
| `/excludestatics` | Skip the hand-maintained static download lists |
| `/excludewinglb` | Skip downloads shared by all Windows versions (`client\win\glb`) |
| `/skipdynamic` | Only static lists; no catalog-based update selection |
| `/skipdownload` | Work out the links but download nothing; links are saved to `static\custom\` |
| `/nocleanup` | Keep files that are no longer needed |
| `/skipsdd` | Accepted for compatibility; has no effect (definition updates are always off) |
| `/skiptz` | Don't detect the time zone |
| `/exitonerror` | Stop at the first error |
| `/proxy http://[user:pass@]host:port` | Download through a proxy |
| `/wsus http://server`, `/wsusonly`, `/wsusbyproxy` | Download from a local WSUS server |

Which Windows 10/11 builds are downloaded is controlled by `Windows10Versions.ini`, which the
generator writes.

### Install: `client\Update.cmd` / `client\cmd\DoUpdate.cmd`

`client\UpdateInstaller.ini` holds the defaults for the settings window.

| Option | Effect |
| --- | --- |
| `/upgradebuilds` | Feature upgrade via enablement package (24H2 -> 25H2 or 26H2, 25H2 -> 26H2) |
| `/updatercerts` | Update root certificates |
| `/updatecpp` | Update Visual C++ runtimes |
| `/instdotnet35`, `/instdotnet4` | Install .NET Framework 3.5 / 4.x |
| `/updatedotnet5` | Update .NET 5+ runtimes |
| `/instwmf` | Install Windows Management Framework |
| `/instmsi` | Install the MSI packages selected in the settings window |
| `/skipieinst`, `/skipdefs` | Skip Internet Explorer / Defender definitions and platform |
| `/skipdynamic` | Install only statically listed updates; skip the catalog scan |
| `/excludestatics` | Ignore the static update lists |
| `/seconly` | Hide non-security updates where applicable |
| `/all` | List every applicable update, including installed and hidden ones |
| `/verify` | Check each file against its hash before installing |
| `/autoreboot` | Reboot and continue automatically (**not** supported on Windows 10/11) |
| `/shutdown` | Shut down when finished |
| `/showlog`, `/showdismprogress`, `/monitoron` | Show log at the end / show DISM progress / keep the screen on |

## Security and third-party code

**Where downloads come from.** Updates, the update catalog, Defender definitions and platform,
Edge, .NET, Visual C++ runtimes and the Sysinternals tools (sigcheck, streams, Autologon) are all
downloaded from Microsoft servers. Nothing is sent about your computers; the download side only
downloads, and the install side never goes online. The WSUS Offline community GitLab is no
longer contacted by the Windows tools.

**Bundled programs.** Each was compared byte-for-byte with the official release (November 2026):

| File | What | Official source | Signed |
| --- | --- | --- | --- |
| `bin\Aut2Exe.exe`, `bin\Aut2exe_x64.exe` | AutoIt 3.3.16.1 compiler (build only, not shipped) | autoitscript.com | AutoIt Consulting Ltd |
| `bin\wget.exe`, `bin\wget64.exe` | GNU Wget 1.21.3 | eternallybored.org (identical) | Jernej Simoncic |
| `bin\gsort.exe`, `bin\join.exe`, `bin\cut.exe` | GNU textutils 2.0 (`gsort` = `sort.exe`) | UnxUtils on SourceForge (identical) | no |
| `client\bin\hashdeep.exe`, `client\bin\hashdeep64.exe` | hashdeep 4.4 | github.com/jessek/hashdeep v4.4 (identical) | no |

**Built into Windows (used instead of third-party tools):** `tar.exe` (zip archives),
IMAPI2 via PowerShell (ISO images), .NET `ZipFile` (the rare `.zip` update package on the
target), `fltmc.exe` (administrator check).

**Not covered:** the Linux/FreeBSD scripts in `sh\` are a separate implementation that the
Windows tools never use. They still contain the original online version check, self-update and
definition updates from the community GitLab. Don't use them, or remove the folder.

## Repository layout

| Path | Contents |
| --- | --- |
| `UpdateGenerator.au3` | Download-side settings window |
| `cmd\` | Download scripts (`DownloadUpdates.cmd` is the main one; `BuildIsoWithImapi.ps1` builds ISOs) |
| `static\` | Static download link lists (`StaticDownloadLinks-*.txt`) |
| `exclude\` | Download exclude lists, including per-build `ExcludeList-w100-<build>.txt` |
| `xslt\` | Filters that pick updates out of the Microsoft catalog by product ID |
| `bin\` | Bundled tools (see the table above) |
| `Include\` | AutoIt standard library (used only when compiling) |
| `client\` | Everything copied to the target computer |
| `client\cmd\` | Install scripts (`DoUpdate.cmd`, `InstallOSUpdate.cmd`, ...) |
| `client\static\` | Update ID lists per OS build, including `StaticUpdateIds-BuildUpgrades.txt` |
| `client\exclude\`, `client\opt\` | Install-side exclude and option lists |
| `sh\` | Linux/FreeBSD download scripts (not maintained in this fork, see above) |
| `doc\` | Upstream FAQ, history, license |
| `MakeRelease.cmd` | The only build script: copies, compiles and packages a release |
| `repo-tools\` | Maintainer tools for analysing the Microsoft catalog (`ExtractDownloadLinks-all.cmd`, `ExtractSupersededUpdates.cmd`); not needed to build, not part of a release |

### Customising without editing tracked files

- `static\custom\`, `exclude\custom\`, `client\static\custom\`, `client\exclude\custom\`:
  extra link, exclude and ID lists that are merged with the built-in ones.
- `cmd\custom\*.cmdt`, `client\cmd\custom\*.cmdt`, `client\software\custom\*.cmdt`: hook templates.
  Rename to `.cmd` to enable (e.g. run your own steps before/after download or install).
- `cmd\AddCustomLanguageSupport.cmd <lang>` adds .NET language packs for another language.

## Maintaining the fork

### Adding a new Windows 11 release

First check whether the release is an enablement package on an existing servicing base
(like 23H2 on 22H2, or 25H2/26H2 on 24H2). It is if its kernel build stays the same:
26H2 is build 26300 but its kernel is 26100. Such releases share monthly updates with their base.

**Enablement-package release** (no new download target):

1. `UpdateGenerator.au3`: append it to the base's entry in `$win11_displayversions`
   (e.g. `24H2/25H2/26H2`).
2. `sh\update-generator-tasks\10-show-selection-dialogs-with-dialog.bash`: same for the base's
   label in `w100_labels`.
3. Create (empty is fine) `client\static\StaticUpdateIds-{servicing-w100-B,w100-B,w100-B-x64,w100-B-dotnet,wupre-w100-B}.txt`,
   where `B` is the new build number. The installer looks these up by the machine's real build.
4. Add the upgrade as described in the next section.

**New servicing base** (new kernel build, e.g. 24H2 was for 22H2):

1. `UpdateGenerator.au3`: extend `$win11_vmax`, `$win11_versions`, `$win11_displayversions`,
   `$win11_defaults`.
2. `cmd\DownloadUpdates.cmd`: add the build to `TMP_BUILDS_ALL_WIN11`.
3. `sh\download-updates-tasks\60-main-updates.bash`: add it to `w100_x64_all_versions`.
4. `sh\update-generator-tasks\10-show-selection-dialogs-with-dialog.bash`: add it to `w100_keys`,
   `w100_labels`, `w100_values`.
5. Create the `client\static\` files as above, plus `exclude\ExcludeList-w100-B.txt`.

### Adding a feature upgrade via enablement package

Follow commit `50983f4`:

1. Add a line to `client\static\StaticUpdateIds-BuildUpgrades.txt`:

   ```
   <old build>,<min revision>,<prerequisite KB>,<new build>,<enablement package KB>
   26100,5074,kb5064081,26200,kb5054156
   ```

   `DoUpdate.cmd` uses the line only when the enablement package file is in
   `client\w100-x64\glb\` (or its `\<internal build>\` subfolder). If the OS revision is at
   least `<min revision>`, it installs the enablement package. If not, it installs the
   prerequisite KB (when that file is present) and asks for a reboot first; if the prerequisite
   file is missing too, the upgrade is skipped.
2. Add the enablement package URL (from the Microsoft Update Catalog) to
   `static\StaticDownloadLinks-w100-x64-glb.txt`.
3. In `client\UpdateInstaller.au3`, add `$path_rel_*` constants for the file and a `Case` in
   `BuildUpgradeAvailable()` so the "Feature Update via Enablement Package" box is enabled.

"Internal build" is the kernel build, so 22631 uses `22621` and 26200/26300 use `26100`.

### Building and editing

- `MakeRelease.cmd` compiles with the bundled AutoIt 3.3.16.1 (`bin\Aut2exe*.exe`) and zips with
  Windows' `tar.exe`, so nothing needs to be installed. It used to be split into
  `PrepareReleaseTree.cmd` and `CompileAutoItScripts.cmd`; both are now part of it.
  `exclude\ExcludeList-ReleaseTree.txt` lists what is left out of a release (entries are
  matched as text against relative paths, e.g. `repo-tools\`).
- **Keep the scripts plain ASCII with CRLF line endings.** All `.au3`, `.cmd` and `.vbs` files
  are ASCII now. Batch files need CRLF; some tools (e.g. Git Bash `sed -i`) silently convert
  to LF.

## Known issues

- **The 24H2/25H2/26H2 cumulative update may not be matched on the target (needs testing).**
  For the November 2026 cumulative update (KB5132061), the catalog-based selection downloads
  the "baseless" `windows11.0-kb5132060-...cab`, which belongs to a different catalog entry
  than the one Windows reports as missing. The installer matches by update ID, so on an
  out-of-date 24H2/25H2/26H2 computer it may not find the file. This selection logic is
  unchanged from upstream. Test on such a computer and check `%SystemRoot%\wsusofflineupdate.log`
  for "Update file ... not found".
- **Failed feature upgrades are retried on every run.** Since commit `9156123`, `DoUpdate.cmd`
  deletes `%SystemRoot%\Temp\wou_buildupgrade_prep_tried.txt` and `wou_buildupgrade_tried.txt`
  right before checking them, so the guard never triggers. The upgrade runs with
  `/ignoreerrors` and always ends with "reboot and run again". If the enablement package doesn't
  apply, every run stops at that step and regular updates are never installed. Workaround:
  untick "Feature Update via Enablement Package". A fix would store the build and revision in the
  marker and skip only if they haven't changed since the last attempt.
- **The Defender platform installer has not been run end to end.** `updateplatform.exe` is
  started without arguments (it is built for silent use by Windows Update). Check the log for
  "Installed Microsoft Defender platform ..." after a run on a computer with an older platform.
- **KB5121794 (26H2) is not listed in the Microsoft Update Catalog.** Its download link points
  at Microsoft's catalog file server (the file is Microsoft-signed and its SHA-1 matches the
  hash in its name), but Microsoft could remove it. If the download fails, the 26H2 upgrade is
  simply not offered.
- **Unticking a Windows 11 box saves little or nothing.** A box only excludes the KBs listed in
  its `exclude\ExcludeList-w100-<build>.txt`. The 24H2/25H2/26H2 list (`26100`) is empty and the
  22H2/23H2 list (`22621`) still holds 2022-era KBs, so most updates for those versions are
  downloaded whichever boxes are ticked.
- **The 24H2 -> 25H2 upgrade can take an extra round.** KB5064081 has been superseded, so it is no
  longer downloaded. A 24H2 machine below revision 5074 skips the upgrade until a regular
  monthly update has raised its revision; the next run then upgrades it.
- **No automatic reboot-and-continue on Windows 10/11.** Re-run the installer by hand after
  each reboot.

## Credits and license

WSUS Offline Update was created by T. Wittrock. The Community Edition was maintained by aker,
with the Linux scripts by H. Buhrmester and many contributors (see `doc\history.txt`).

Licensed under the GNU General Public License v3; see `doc\license.txt`.
