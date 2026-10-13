# Desktop Translator

A macOS desktop dictionary and translator. Pin the window on your desktop, type English or Chinese (direction is detected automatically), and look up definitions, examples, pronunciation, and recent queries.

**Download (recommended)** → [GitHub Releases (latest)](https://github.com/yxwvwxy/desktop-translator/releases/latest)

## Requirements

- macOS **14.0** or later
- Network access (lookups use Youdao, Google, and related online services)

## Install

1. Open [Releases](https://github.com/yxwvwxy/desktop-translator/releases/latest).
2. Download **`Desktop-Translator-*-macOS.zip`**.
3. Unzip and drag **`Desktop Translator.app`** into **Applications**.
4. If macOS says the app “cannot be verified” on first launch:
   - In Finder, **Control-click** the app → **Open** → **Open** again; or
   - **System Settings** → **Privacy & Security** → allow the app.

The build is ad-hoc signed and not notarized by Apple. That is expected for this project.

## Usage

**This app puts lookup and your word history on one screen. Keep the window pinned on the desktop so recent words stay in view—seeing them again and again helps them stick.**

- **Auto**: Detects English/Chinese (and other supported languages) and translates.
- **Entry**: Type a word or phrase; misspelled English shows a red underline—right-click for suggestions.
- **Translation**: Definitions and translation; use the speaker icon for pronunciation.
- **Recent**: Recent lookups; **×** in the right column deletes a row.
- Menu bar **Aa** icon: pin to desktop, open as a normal window, or quit.

Optional: add the **Desktop Translator** widget from **Edit Widgets** on the desktop for quick lookups.

## Build from source

You need **Xcode** with the macOS SDK:

```bash
git clone https://github.com/yxwvwxy/desktop-translator.git
cd desktop-translator
chmod +x package-app.sh
./package-app.sh
```

This creates `Desktop Translator.app` in the project folder and installs it to Applications when possible.

Release zip only (same as CI, no install):

```bash
chmod +x scripts/release-build.sh
./scripts/release-build.sh
# Output: dist/Desktop-Translator-<version>-macOS.zip
```

## Releases (maintainers)

Push a version tag to build and upload assets automatically:

```bash
git tag v1.0.1
git push origin v1.0.1
```

## License

If no license file is present in the repository, confirm terms before use. Issues and pull requests are welcome.
