# Changelog

All notable changes to UIScore are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.3.5] - 2026-10-29

### Fixed
- The app no longer crashes at the shortcut step of onboarding, or in Settings, on a Mac other than the one that built it. The build now ships the shortcut library's resource bundle inside the app.

## [0.3.4] - 2026-10-22

### Changed
- Code reorganised into smaller single-purpose files; scores are unchanged.
- Tests named by the behaviour they cover, plus offline snapshot and end-to-end tests.
- README rewritten; version history moved here.

### Fixed
- A failed History save or a failed reason write now shows the error and retry state instead of failing silently.

## [0.3.3] - 2026-10-22

### Changed
- Hierarchy counts repeated same-style titles as one level.
- Grouping is judged on closeness, similarity, shared background and meaning; alignment is a minor cue.
- Contrast has four sub-rubrics (colour, size, weight, spacing) and always explains itself.
- Ease uses relative text sizes and line length, never absolute px. Product demo text does not count as reading.
- Trust counts customer logos and product demonstration.
- Cookie banners and chat bubbles are ignored for layout.
- The designer judge follows one set of design principles, and each meter's reason is its own.
- The headline-clarity check passes homepages that demonstrate the product.
- The footer check applies only when a footer is visible.

### Fixed
- Only clicks in other apps close the card, so it no longer closes on its own.
- Reasons name only elements that are visible.

## [0.3.2] - 2026-10-21

### Changed
- Dark screens are judged on their palette, not on how dark they are.
- Grouping checks alignment within each group.
- The designer rating is the mean of five votes.
- Fix lines come only from vetted checklist advice, and reasons match the score.
- History shows a new run at once, tooltips sit on top, and the image viewer is a floating window.
- Undo lasts 3 seconds.

### Fixed
- Forms get no advice about the fold.
- Clicking outside the card closes it.

## [0.3.1] - 2026-10-21

### Changed
- The designer rating uses five parallel votes to reduce run-to-run variation.
- Local builds are signed with a fixed designated requirement.

## [0.3.0] - 2026-10-21

### Added
- Per-meter designer ratings: one Claude Sonnet call, asked as a senior product designer, rates all eight meters from 1 to 9 with the measured facts as evidence. Each rating is blended with its checklist score; with fewer than two valid votes the checklist alone is used. Results are cached per image.

## [0.2.2] - 2026-10-21

### Added
- Spacing, icon and consistency detectors, measured but not scored.

## [0.2.1] - 2026-10-21

### Added
- Font-size detection from letter shape; Ease checks typeface and accent-colour count.

### Fixed
- Text size and contrast measurement.

## [0.2.0] - 2026-10-21

### Changed
- Grouping replaces Alignment: proximity, alignment, common region and similarity.

### Removed
- Duplicate gap checks.

## [0.1.0] - 2026-10-20

### Added
- Menu-bar app scoring a screenshot on Contrast, Balance, Hierarchy, Familiarity, Ease, Clarity and Trust, with an overall Score, Feeling and Reading level.
- Text boxes from Apple Vision, an image-hash result cache, History, and a command-line tool.
