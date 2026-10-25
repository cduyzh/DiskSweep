# DiskSweep

A native macOS disk and file cleanup tool: find large files, byte-identical duplicates and app leftovers — and delete them safely through the Trash.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-2EA44F?style=flat-square)
[![Author](https://img.shields.io/badge/Author-cduyzh-3B82F6?style=flat-square)](https://github.com/cduyzh)

**English** · [简体中文](README.zh-CN.md)

DiskSweep scans the real file metadata on your Mac, aggregates directory sizes, groups byte-identical duplicate files, and surfaces your biggest space hogs. Every everyday action deletes through the system Trash — recoverable, confirmed, never silent. It is a native SwiftUI/AppKit app for macOS 14 or later with zero third-party dependencies.

![Disk overview](docs/screenshots/v0.3.0-overview.png)

![Large files](docs/screenshots/v0.3.0-large-files.png)

## Features

- **Disk overview** — capacity and used space per volume; after scanning your home directory, top-level folder sizes and shares are aggregated from real file data.
- **Directory organizer** — an expandable directory tree showing each folder's aggregated size, file count, folder count and share, with subfolders sorted largest first.
- **Large files** — files above a threshold (default 100 MB, adjustable) sorted by real size; nine file-type categories with count and size totals, combined category and path-search filtering, three sort orders (size / modified time / name), checkbox selection, and CSV export of the currently filtered results.
- **Duplicate detection** — a three-tier pipeline of size grouping → sampled hashing (file header skipped; three-point sampling for large files) → full SHA-256; only byte-identical files are grouped. A SQLite hash cache keyed by path, size and modification time persists digests, so rescans of unchanged files read zero bytes from disk; stale keys are pruned after each scan.
- **Hard-link accounting** — files with multiple hard links are counted exactly once per inode during scanning; duplicate-group paths that share an inode are annotated "deleting this will not free space", and reclaimable space is computed from the number of distinct inodes.
- **Safe deletion** — every everyday action moves files to the Trash (recoverable) with a confirmation step; a failed move never falls back to permanent deletion. The core API defaults to `.trash`, keeping explicit permanent deletion only for compatibility; before acting it re-stats the uncached inode, size and modification time and skips any file that no longer matches the scan snapshot; system locations and the app itself are protected. Uninstall and orphan cleanup share the same deletion channel and confirmation semantics.
- **App uninstaller** — lists every app in /Applications, ~/Applications and system locations; an identifier cache plus two sensitivity levels (precise / enhanced) search the Library for leftovers (preferences, caches, app data, logs, launch items, helpers); Containers are attributed precisely through container metadata; uninstallation moves the app bundle and the selected leftovers to the Trash together, and if the bundle itself fails, its associated leftovers are left untouched.
- **Orphan cleanup** — reverse-enumerates top-level entries of the user Library and compares them against the identifiers of every installed app; ownerless entries (orphan caches, preferences, containers, launch items) are listed as candidates, with system prefixes excluded automatically.
- **Software update checks** — on-demand checks against two kinds of real sources: Sparkle appcasts (RSS) and the public App Store lookup; apps without an update source are honestly labeled "no update source" instead of pretending to be up to date.
- **Space view** — a squarified treemap with cushion highlighting, where area is proportional to real directory size; click to drill down, breadcrumbs to go back, hover for details.
- **APFS snapshot hints** — parses real `tmutil` output to list local APFS snapshots and estimate reclaimable space; deleting snapshots requires administrator rights, which this app never requests — it points you to Disk Utility instead.
- **Detail panel** — logical size, real on-disk usage, creation and modification times, hard-link count, resource identifiers and full path for the selected file.
- **CSV export** — large-file and duplicate lists export as CSV with UTF-8 BOM and protection against spreadsheet formula injection.
- **Settings** — appearance (system / light / dark), large-file threshold, duplicate-detection minimum size, and hidden-file skipping.
- **Version and history** — current version, build number, build time, source summary and formal install status, plus the full local update history.

## Safety Model

A cleanup tool must never surprise you — safety is the core design goal of DiskSweep.

- **Trash first, always.** Every deletion offered in the interface moves files to the system Trash after an explicit confirmation. If the move fails, the file stays exactly where it was — the app never converts a failed move into permanent deletion. Trashed items remain recoverable from Finder.
- **Re-stat before acting.** Immediately before a file is handled, the app re-reads its uncached inode, size and modification time and compares them against the scan snapshot; anything that changed in the meantime is skipped and reported, never silently processed.
- **Protected locations.** System locations and DiskSweep itself are protected from deletion. The app never escalates to administrator privileges; paths blocked by SIP or TCC are reported as unreadable rather than pretended to be empty, and whole-disk locations require Full Disk Access granted in System Settings.

## Download and Install

1. Download the latest DMG from [Releases](https://github.com/cduyzh/DiskSweep/releases).
2. Open the DMG and drag **DiskSweep** into the Applications folder.
3. On first launch, right-click the app and choose **Open** (required only once for apps without Developer ID notarization).
4. For whole-disk scans, grant **Full Disk Access** under System Settings → Privacy & Security.

## Build from Source

Requires Xcode or the Command Line Tools (Swift 5.9+) on macOS 14 or later.

```bash
git clone https://github.com/cduyzh/DiskSweep.git
cd DiskSweep
./build_app.sh
```

The script builds the app bundle for this project only and does not install anything automatically. `swift build` and `swift test` also work directly from the repository root.

## Version History

Current version: **0.3.0** (build 3). See [CHANGELOG.md](CHANGELOG.md) for the complete history.

## Privacy

Scanning is local and read-only: DiskSweep reads file metadata on your Mac only, and nothing is uploaded anywhere. The only network requests are the software-update checks you trigger yourself (a Sparkle appcast or the public App Store lookup).

## License

Released under the [MIT License](https://opensource.org/license/mit).

## Author

**cduyzh**

- GitHub: <https://github.com/cduyzh>
- Website: <https://www.cduyzh.top>
- Goal: <https://www.cduyzh.top/goal>
