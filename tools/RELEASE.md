# Building & sharing pathology_report

Two scripts in this directory cover the whole workflow:

| Script | Purpose | When to run |
|---|---|---|
| `tools/setup_icon.sh` | Generate the desktop app icon from `tools/icon-source.svg` | Once, or whenever the icon design changes |
| `tools/build_release.sh` | Build a release `.app`, ad-hoc-sign it, ditto-zip it for sharing | Every time you want to send a build |

---

## First-time setup (do this once)

### 1. Generate the app icon

```bash
./tools/setup_icon.sh
```

The script tries, in order: `rsvg-convert`, `inkscape`, `magick`, `qlmanage`. The cleanest result comes from `rsvg-convert`:

```bash
brew install librsvg     # one-time install
./tools/setup_icon.sh
```

After it succeeds, the icon will appear in:
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (rendered into 7 PNG sizes)
- `windows/runner/resources/app_icon.ico` (256-pixel multi-resolution ICO)

### 2. Customize the icon (optional)

Open `tools/icon-source.svg` in any vector editor (Inkscape, Figma, Sketch, Affinity Designer) or even directly in a code editor — it's plain SVG. After saving, re-run `./tools/setup_icon.sh`.

---

## Build & share (do this every time)

```bash
./tools/build_release.sh
```

This produces `build/release-share/pathology_report-<version>.zip`.

Send the zip however you like (AirDrop, email, Drive, etc.). **Do not** transfer the `.app` folder directly via Finder — it'll lose its bundle metadata and arrive as a folder of files.

---

## What your friend does on their Mac

After extracting the zip, they need to bypass macOS Gatekeeper **once**, because the app is ad-hoc signed but not notarized (notarization requires a $99/yr Apple Developer Program membership, which we deliberately skip for friend-to-friend testing).

The most reliable command — works on every macOS version:

```bash
xattr -dr com.apple.quarantine /path/to/pathology_report.app
```

Then double-click the app. macOS won't bother them again.

If they're a non-terminal user, the alternative is:
1. **Right-click** the app → **Open** (not double-click).
2. The dialog shows an "Open" button — click it.
3. After this once, double-click works normally.

(Note: macOS 15 Sequoia removed the right-click bypass. On Sequoia they have to use the `xattr` command.)

---

## Compatibility matrix

| Recipient's macOS | App launches? | Voice works? |
|---|---|---|
| **macOS 13 Ventura or later** | ✓ | ✓ on-device speech |
| **macOS 12 Monterey** | ✓ | ✗ — banner explains why; tap-only mode |
| **macOS 11 Big Sur** | ✓ | ✗ — banner explains why; tap-only mode |
| **macOS 10.15 Catalina or older** | ✗ — won't launch (deployment target is 11.0) | n/a |

The voice-unavailable banner appears at the top of every voice screen with the platform-specific reason and a Retry button, so even on older Macs the app stays fully usable for tap input — your friend can complete reports normally without voice.

---

## Versioning

The script reads the version from `pubspec.yaml`'s `version:` line. Bump it before each share:

```yaml
version: 1.0.1+2     # 1.0.1 is the user-facing version, 2 is the build number
```

The zip will be named `pathology_report-1.0.1.zip` automatically.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Friend sees "app is damaged" | Zip created with `zip` instead of `ditto` | Re-run `./tools/build_release.sh` (it uses `ditto`) |
| Friend sees "cannot be opened — unidentified developer" | Quarantine xattr still on the file | `xattr -dr com.apple.quarantine /path/to/.app` |
| App opens but mic doesn't work | macOS hasn't been granted Microphone + Speech Recognition permissions | Friend opens System Settings → Privacy & Security → Microphone, enable for `pathology_report` |
| App crashes immediately on first speech-recognition attempt with `Namespace TCC` in the report | TCC has a poisoned cache from a prior build that didn't have the speech-recognition usage-description key. Even after we add the key, TCC won't re-evaluate. | `tccutil reset All com.bulbultech.pathologyReport` then re-launch. macOS will read the Info.plist fresh and prompt the user. |
| Listening pill says "Voice off" forever | macOS 11/12 doesn't support on-device speech | Banner explains; use tap-only. Or upgrade to macOS 13+. |
| Build fails with "no signing certificate" | Trying to use Automatic signing without an Apple ID | Open `macos/Runner.xcodeproj` in Xcode → Signing & Capabilities → set Team to "None" or sign in with your Apple ID |

---

## Going further: notarized builds (optional, $99/yr)

If you join the Apple Developer Program, you can ship without the `xattr` step:

1. Get a Developer ID Application certificate from developer.apple.com
2. Configure signing in `macos/Runner.xcodeproj`:
   - Signing & Capabilities → Team → your team
   - Code Sign Identity → Developer ID Application
3. Build with Xcode → Archive → Distribute App → Developer ID
4. Notarize:
   ```bash
   xcrun notarytool submit pathology_report.zip \
     --apple-id you@example.com --team-id TEAMID \
     --password "@keychain:AC_PASSWORD" --wait
   xcrun stapler staple pathology_report.app
   ```

After stapling, recipients can double-click without any dialogs.
