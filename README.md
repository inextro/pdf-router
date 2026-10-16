# PDFRouter

macOS lets you pick only one default app per file type. PDFRouter sits in that slot and forwards each PDF to an app chosen by **where the file lives**:

- PDFs inside your Zotero attachment folders, or any folder you choose → [PaperMark](https://github.com/inextro/pdf-reader)
- every other PDF → Preview

This matters for launchers like Raycast or Alfred, which always open files with the system default app. Inside Zotero itself, set *Settings → General → File Handling → Open PDFs using* instead.

## How it works

PDFRouter is a tiny AppKit app with no Dock icon. When macOS hands it a PDF, it resolves symlinks in the path, checks the path against your Zotero attachment folders and your own folders, passes the file to the target app, and quits.

The Zotero folders are read from your Zotero profile's `prefs.js` every time PDFRouter launches, so nothing is hard-coded:

- `extensions.zotero.baseAttachmentPath`: the base directory for linked attachments (e.g. a folder in Google Drive)
- `<extensions.zotero.dataDir>/storage`: attachments stored by Zotero itself (defaults to `~/Zotero/storage`)

PaperMark is looked up at `~/Applications/PaperMark.app`, then `/Applications/PaperMark.app`. If it is missing, every PDF goes to Preview.

## Choosing your own folders

To send PDFs from other folders to PaperMark too, open PDFRouter itself (double-click it in `~/Applications`, or launch it from Spotlight or Raycast). Opened without a PDF, it shows a settings window instead of quitting:

- **Add Folder…** picks one or more folders. **Remove** (or `Delete`) drops the selected ones.
- The Zotero folders it found are listed below for reference. They are always included.

Your folders are added to the Zotero folders, so this also works without Zotero. Changes are saved right away and apply to the next PDF you open.

## Requirements

- macOS 14 or later, Apple Silicon
- Xcode Command Line Tools (`swiftc`)

## Install

```sh
./scripts/build-app.sh --install
```

This builds `build/PDFRouter.app`, copies it to `~/Applications`, and makes it the default app for PDFs.

## Uninstall

```sh
swift scripts/set-default.swift /System/Applications/Preview.app
rm -rf ~/Applications/PDFRouter.app
```

## Notes

- `duti` (and the `LSSetDefaultRoleHandlerForContentType` API it uses) silently does nothing on recent macOS. `scripts/set-default.swift` uses `NSWorkspace.setDefaultApplication(at:toOpen:)` instead.
- To route to different apps, edit `paperMarkCandidates` or `fallbackApp` in `Sources/main.swift`.

## License

MIT
