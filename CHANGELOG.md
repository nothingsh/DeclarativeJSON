# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Impressions: an item's `tracking`, which the library hands to `DocumentViewController.onImpression` once the user has seen the item, at least half of it for half a second by default; `impressionFraction` and `impressionDuration` change that. An item is reported once per document.
- `ItemInfo.tracking`, so that an action can read the item's `tracking`.
- `DocumentVersion.minor` 5, for `tracking`.

## [0.5.0] - 2026-10-16

### Added

- Loading more: a section's `more`, which the library hands to `DocumentViewController.onLoadMore` when the user nears the end of the section, and the patch operation `appendItems`, which adds the next items and replaces `more`. A list or grid section shows a spinner while it loads, and a button that tries again after `showLoadMoreFailure(in:)`; `makeLoadMoreView` replaces them with a `LoadMoreView` of the app's.
- `DocumentViewController.scrollViewDelegate`, which gets the collection view's scroll view callbacks.
- Page states: `DocumentViewController` can be created without a document and shows `loadingView` until `setDocument`; `showLoading()` and `showFailure(retry:)` show `loadingView` and `failureView` in place of the sections, and `retry()` tries again. A page without items or `more` shows `emptyView`. Each of the three views can be replaced.
- `DocumentViewController.onRefresh`, which adds a refresh control and calls the app when the user pulls down.
- The colors `systemMint`, `systemCyan` and `systemBrown`. Releases before 0.5.0 treat them as missing.
- `DocumentVersion.minor` 4, for `more`, `appendItems` and the three colors.

### Changed

- The page is its collection view's delegate. An app that set `collectionView.delegate` replaced it, which stops loading more; set `scrollViewDelegate` instead.
- `Patch.Operation` has the case `appendItems`. A `switch` over it has to handle it.

## [0.4.0] - 2026-10-16

### Added

- Asynchronous actions: `ActionRegistry.register` with an `async throws` handler, such as one that sends a request. Such an action takes `onSuccess` and `onFailure`, which run when the handler returns or throws, and the actions after it wait until it is done. The actions after a wait read and change the item the action ran for, and do not run when the page no longer has it. The task is cancelled when the page goes away.
- `ActionSpec.isAsync`, and `async` for each action in the manifest.
- Patches, which change part of a page: `DocumentDecoder.decodePatch` reads one, and `DocumentViewController.apply(_:)` replaces, inserts and removes the items and sections it names, by `id`, and adds its templates. Replaced and inserted items show the patch's data; the other items keep the changes made on the device.
- `operations` in the manifest, the operations of a patch.
- `DocumentVersion.minor` 3, for `onSuccess` and `onFailure` and for patches.

### Changed

- `Issue.Kind` has the cases `unknownID` and `unknownOperation`, for a patch. A `switch` over it has to handle them.

## [0.3.0] - 2026-10-16

### Added

- `overlay` on any node: nodes in front of the view, at an alignment and an offset, such as a badge on an image. Touches go through an overlay unless a node in it sets an event.
- The `grid` layout for a section, with `columns` and `spacing`.
- `highlight` on `vstack` and `hstack`: `false` turns off the highlight of a stack with `onTap`.
- `DocumentVersion.minor` 2, for `overlay`, `grid` and `highlight`, and the types `node` and `list` in the manifest.

### Changed

- A font written as `{ "size": ..., "weight": ... }` follows Dynamic Type, scaled as body text is, as a text style does and as an Android `sp` does. At the default text size it looks as before; at other sizes text is larger or smaller than before.
- A `vstack` or `hstack` with `onTap` is highlighted with `systemFill` behind its content while it is pressed, as a list row is. Set `"highlight": false` to keep the old look.
- `PropertyType` has the cases `node` and `list`, and `Document.Layout` the case `grid`. A `switch` over them has to handle the new cases.

## [0.2.0] - 2026-10-16

### Added

- `onTap` on `vstack` and `hstack`, so a whole row can be tapped. With an `accessibilityLabel`, VoiceOver reads the stack as one button.
- `fallback` on any node: a node shown instead when the app does not know the node's type, such as a component of a later release.
- `ActionContext.item`, `sourceView` and `page`: which item or header an action runs for, the view that sent the event, and the page, for presenting a share sheet or a popover from an action.
- `DocumentVersion.minor`, and `minor` in the manifest: which additions to version 1 of the format a release reads, for the app to send with its requests. This release reads 1.

### Changed

- `BuildContext.action(_:)` returns an `EventAction`, which takes the view that sent the event as `source`. Calling it as before, `action(value)`, and passing it to `onEvent` still compile; code that stores it as a `(JSONValue?) -> Void` closure has to store an `EventAction` instead.
- Requires iOS 15, the earliest version Xcode 26 builds for and has simulators of. iOS 15 runs on every iPhone that runs iOS 14.

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

[Unreleased]: https://github.com/nothingsh/DeclarativeJSON/compare/0.5.0...HEAD
[0.5.0]: https://github.com/nothingsh/DeclarativeJSON/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/nothingsh/DeclarativeJSON/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/nothingsh/DeclarativeJSON/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/nothingsh/DeclarativeJSON/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/nothingsh/DeclarativeJSON/releases/tag/0.1.0
