# UIScore

A Mac menu-bar app that scores the design of any screenshot.

Take a screenshot or copy an image, press **Command + Shift + V**, and a few seconds later the card shows how the screen looks and reads.

![Welcome](docs/images/step1.png)

## What it scores

- **Contrast**: text colour, size, weight and spacing set the important things apart.
- **Grouping**: related items sit together and look alike.
- **Balance**: visual weight is spread evenly.
- **Hierarchy**: the eye knows where to land first.
- **Familiarity**: the screen follows patterns people already know.
- **Ease**: the screen is easy to take in.
- **Clarity**: the next step is obvious.
- **Trust**: the screen looks credible.
- **Feeling**: Valence and Intensity, shown as positions rather than scores.
- **Reading level**: the school grade, 1 to 12, that reads the copy easily.

The eight meters roll up into one Score from 0 to 100.

## Install

macOS 13 or newer. Download **UIScore.zip** from the [latest release](https://github.com/itsdimachka/uiscore/releases/latest), or follow [docs/INSTALL.md](docs/INSTALL.md) for the step-by-step guide and the one-line Terminal install.

## Keys

UIScore needs two keys. Add them on first launch, or later from the menu-bar icon, then Settings.

- **Jev key**: from [console.typesafe.ai/keys](https://console.typesafe.ai/keys).
- **Claude API key**: from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys). You can add spares; UIScore moves to the next key when one runs out of credit.

## Privacy and keys

- The screenshot you score is sent to Anthropic (Claude) and to TypeSafe (Jev) for analysis. Nothing else leaves your machine.
- Both keys are stored in the macOS Keychain and are never shown in full.
- UIScore has no telemetry.
- It reads your newest screenshot from the screenshot folder (Desktop by default) and the clipboard, only when you press the shortcut. macOS asks for Desktop access the first time.
- Results are stored on your Mac (Caches and `~/Library/Application Support/ScreenCheck/runs`), so scoring the same image again makes no calls. Deleting a run from History removes it.

## How scoring works

Each meter is a set of yes/no checks drawn from design research. Code answers what it can measure from the image: contrast ratios, spacing, text size, colour and layout. A model answers the rest. A designer rating, the mean of five Claude votes per meter, is blended with the checklist score. UIScore detects the page type first, so checks that do not apply are skipped.

Validated on 52 public sites: praised-versus-poor AUC 0.983 (praised mean 91.5, poor 67.2).

## Build from source

Needs Xcode.

```sh
swift build
swift test
scripts/make-app.sh   # builds dist/UIScore.app and dist/UIScore.zip
```

Command line: `swift run screencheck-cli shot.png` with `ANTHROPIC_API_KEY` and `JEV_API_KEY` set. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for signing local builds.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
