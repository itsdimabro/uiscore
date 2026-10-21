# UIScore

Press a key after a screenshot and get a UI design score.

UIScore is a small Mac menu-bar app. Take a screenshot or copy any image, press **Command + Shift + V**, and a few seconds later you see how the screen looks and reads.

![Welcome](docs/images/step1.png)

## What it scores

| Group | Meters |
| --- | --- |
| Visual | Contrast, Grouping, Balance, Hierarchy |
| Visual + Copy | Familiarity, Ease, Clarity, Trust |
| Copy | Reading grade, 1 to 12 |
| Feeling | Valence, Intensity |

All meters roll up into one **Score** from 0 to 100.

## Requirements
- macOS 13 or newer.
- A [TypeSafe Jev](https://console.typesafe.ai/keys) key.
- An [Anthropic Claude API](https://console.anthropic.com/settings/keys) key.

Screenshots you score are sent to Anthropic and TypeSafe for analysis. Your keys stay in the Mac Keychain.

## Install
Download **UIScore.zip** from the [latest release](https://github.com/itsdimachka/uiscore/releases/latest), unzip it, and drag **UIScore** into Applications. The first time, macOS asks you to confirm opening it; the steps are in [docs/INSTALL.md](docs/INSTALL.md).

Or paste this into Terminal. It downloads, unzips, installs and opens the app, and skips the Gatekeeper warning:

```sh
curl -L -o ~/Downloads/UIScore.zip https://github.com/itsdimachka/uiscore/releases/latest/download/UIScore.zip && unzip -o ~/Downloads/UIScore.zip -d ~/Downloads && rm -rf /Applications/UIScore.app && mv ~/Downloads/UIScore.app /Applications/ && open /Applications/UIScore.app
```

## Use
1. Take a screenshot, or copy any image.
2. Press **Command + Shift + V**. UIScore scores the newest of the two.
3. Press **esc** to close the card.

Change the shortcut in Settings, from the menu-bar icon.

## Build from source
Needs Xcode.

```sh
swift build
swift test
scripts/make-app.sh   # builds dist/UIScore.app and dist/UIScore.zip
```

Command line: `swift run screencheck-cli shot.png` with `ANTHROPIC_API_KEY` and `JEV_API_KEY` set.

## How scoring works
Each meter is a set of yes/no checks drawn from design research. UIScore detects the page type first (for example SaaS app, store, landing page) so checks that do not apply are skipped. Code measures such as contrast ratios, spacing and text size run locally on the image. Ease also checks that a screen uses at most two typefaces and one or two accent colours (NN/g, Pairing Typefaces and Using Color to Enhance Your Design). Text size is measured from the text's real height by letter shape, so small navigation text is no longer read as too small.

Score tracks human appeal ratings at ρ ≈ 0.40 on 60 sites (95% interval 0.15 to 0.62) from Reinecke & Gajos, "Quantifying Visual Preferences Around the World" (2014).

## License
[MIT](LICENSE)
