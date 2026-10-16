# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `onTap` on `vstack` and `hstack`, so a whole row can be tapped. With an `accessibilityLabel`, VoiceOver reads the stack as one button.
- `fallback` on any node: a node shown instead when the app does not know the node's type, such as a component of a later release.
- `DocumentVersion.minor`, and `minor` in the manifest: which additions to version 1 of the format a release reads, for the app to send with its requests. This release reads 1.

### Fixed

- `ActionContext.update` called after the handler returned, such as when a request finishes, changes the item the action ran for. It used to change the item that the cell showed by then, and to undo the changes made to the item in between.

## [0.1.0] - 2026-10-16

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
