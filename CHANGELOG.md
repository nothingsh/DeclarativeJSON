# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-15

First release.

### Added

- Version 1 of the document format: templates, sections in a `list` or `carousel` layout, headers, and items with their data.
- `$` references to an item's data, with `$$` for a dollar sign.
- Thirteen built-in components, named after the DeclarativeUIKit modifiers, and properties common to every component.
- `onTap`, `onChange` and `onReturn` events, with the `navigate`, `openURL`, `set` and `toggle` actions.
- `ComponentRegistry` and `ActionRegistry`, for an app's own components and actions.
- `DocumentViewController`, which builds each cell once and keeps local changes across cell reuse.
- `ImageLoader`, with a `URLSession` loader by default.
- Problems in a document are reported to `onIssue` and do not stop the page from showing.
- `manifest.json` and `Manifest`, describing the components and actions for a backend.
- Example app.

[Unreleased]: https://github.com/nothingsh/DeclarativeJSON/compare/0.1.0...HEAD
[0.1.0]: https://github.com/nothingsh/DeclarativeJSON/releases/tag/0.1.0
