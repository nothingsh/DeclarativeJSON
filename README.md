<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/declarative-json-dark.svg">
    <img src="docs/images/declarative-json-light.svg" alt="DeclarativeJSON — Server-driven lists for UIKit, built from JSON." width="850">
  </picture>
</p>

# DeclarativeJSON

**English** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

Server-driven lists for UIKit. A JSON document names the cell templates, the items and what a tap does; the library builds the cells with [DeclarativeUIKit](https://github.com/nothingsh/DeclarativeUIKit) stacks, binds them with [DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) and shows them in a collection view.

```json
{
  "v": 1,
  "templates": {
    "product": {
      "type": "hstack", "spacing": 12, "alignment": "center", "padding": 16,
      "children": [
        { "type": "image", "url": "$image", "width": 56, "height": 56, "cornerRadius": 8, "clipsToBounds": true },
        { "type": "vstack", "alignment": "leading", "spacing": 4, "children": [
          { "type": "label", "text": "$title", "font": "headline" },
          { "type": "label", "text": "$subtitle", "font": "footnote", "textColor": "secondaryLabel", "numberOfLines": 2 }
        ]},
        { "type": "spacer" },
        { "type": "button", "title": "$price", "onTap": { "action": "navigate", "url": "$detailURL" } }
      ]
    }
  },
  "sections": [
    { "id": "today", "layout": "list", "items": [
      { "id": "p1", "template": "product", "data": { "title": "Keyboard", "subtitle": "Low profile", "price": "$99", "image": "https://…", "detailURL": "app://product/1" } }
    ]}
  ]
}
```

```swift
let document = try DocumentDecoder().decode(data)

var actions = ActionRegistry.standard
actions.register(.navigate) { context in
    if let url = context.url("url") { router.open(url) }
}

let controller = DocumentViewController(document: document, actions: actions)
controller.onIssue = { print($0) }
```

A `$` value refers to a key of the item's `data`; everything else is a constant. Actions run in the app: `navigate` and `openURL` hand a URL to closures you register, `set` and `toggle` change the item's data on the device, and you can register actions and components of your own. A manifest lists every component, property and action, for the backend that generates the documents.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Documents](#documents)
- [References](#references)
- [Components](#components)
- [Values](#values)
- [Events and actions](#events-and-actions)
- [The page](#the-page)
- [Your own components](#your-own-components)
- [Images](#images)
- [Problems in a document](#problems-in-a-document)
- [Versions](#versions)
- [The manifest](#the-manifest)
- [Example app](#example-app)

## Requirements

- iOS 15+
- Swift 5.9+

## Installation

Swift Package Manager. In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", .upToNextMinor(from: "0.5.0"))
]
```

Before 1.0, a minor release such as 0.6.0 can include breaking changes, listed in the [changelog](CHANGELOG.md), so this takes only the patch releases of 0.5. DeclarativeUIKit and DeclarativeCombine come with it.

## Documents

A document has three keys:

- `v`, the version of the format. This release reads version 1; a document of another version fails to decode with `DocumentError.unsupportedVersion`. [Versions](#versions) lists what later releases add to version 1.
- `templates`, from a name to the view tree of a cell or a header.
- `sections`, in order. A section has an `id`, a `layout`, an optional `header`, its `items` and, when it has more to [load](#loading-more), `more`.

```json
{ "id": "featured", "layout": "carousel",
  "header": { "template": "title", "data": { "text": "Featured" } },
  "items": [ { "id": "f1", "template": "card", "data": { "name": "Keyboard" } } ] }
```

`layout` is `list`, one column of full-width cells as tall as their content, `carousel`, one row that scrolls sideways, or `grid`, rows of cells of equal width; `list` is the default. A `grid` takes `columns`, the cells in a row, 2 by default, and `spacing`, the space between cells across and down, 0 by default. A row is as tall as its tallest cell, and each cell keeps its own height at the top of the row. An item has an `id`, unique in the page, the name of its `template` and its `data`, a JSON object. A header has a `template` and `data` too.

A node of a template is an object with a `type`, its properties, for a stack its `children`, and optionally a [`fallback`](#versions):

```json
{ "type": "vstack", "spacing": 4, "children": [
  { "type": "label", "text": "$title", "font": "headline" }
]}
```

## References

A property whose value is a string starting with `$` takes the value of that key in the item's data: `"text": "$title"`. The reference is the whole value; there is no concatenation, arithmetic or condition, so the backend puts formatted text, prices and URLs in `data` ready to show. `$$` writes a dollar sign: `"$$5 off"` is the text `$5 off`. A string in `data` is never a reference.

When the referenced key is missing or `null`, or its value has the wrong type, the property is treated as not set and the view shows its default. A wrong type is also reported.

There is no `not`, so visibility has two properties. Of two views that share a reference, one says `isHidden` and the other `isVisible`:

```json
{ "type": "button", "image": "heart", "isHidden": "$liked", "onTap": { "action": "toggle", "path": "liked" } },
{ "type": "button", "image": "heart.fill", "isVisible": "$liked", "onTap": { "action": "toggle", "path": "liked" } }
```

Send `false` rather than leaving the key out: a missing value leaves both views shown.

## Components

The property names are those of the DeclarativeUIKit modifiers that set them. A modifier with labeled arguments takes an object with those labels, such as `"border": { "color": "separator", "width": 1 }`.

| Type | Properties | Events |
| --- | --- | --- |
| `vstack` | `alignment` (`leading`, `center`, `trailing`, `fill`), `spacing`, `highlight` | `onTap` |
| `hstack` | `alignment` (`top`, `center`, `bottom`, `firstTextBaseline`, `lastTextBaseline`, `fill`), `spacing`, `highlight` | `onTap` |
| `vscroll`, `hscroll` | `alignment` and `spacing` as on `vstack` and `hstack`, and `showsIndicators`, `bounces` | |
| `spacer` | `minLength`, constant only | |
| `label` | `text`, `font`, `textColor`, `numberOfLines`, `textAlignment`, `adjustsFontSizeToFitWidth` | |
| `image` | `url`, `image`, `contentMode` (`scaleToFill`, `scaleAspectFit`, `scaleAspectFill`, `center`) | |
| `button` | `title`, `titleColor`, `image`, `isEnabled` | `onTap` |
| `textfield` | `text`, `placeholder`, `font`, `textColor`, `textAlignment`, `keyboardType`, `returnKeyType`, `isSecureTextEntry`, `isEnabled` | `onChange`, `onReturn` |
| `switch` | `isOn`, `onTintColor`, `isEnabled` | `onChange` |
| `slider` | `value`, `minimumValue`, `maximumValue`, `minimumTrackTintColor`, `maximumTrackTintColor`, `isEnabled` | `onChange` |
| `progress` | `progress`, `progressTintColor`, `trackTintColor` | |
| `activity` | `isAnimating`, `hidesWhenStopped`, `color` | |

Every component also takes `width`, `height`, `aspectRatio`, `padding`, `background`, `cornerRadius`, `clipsToBounds`, `border`, `alpha`, `tintColor`, `overlay`, `isHidden`, `isVisible`, `accessibilityLabel` and `accessibilityIdentifier`.

- `image` on an `image` or a `button` names an image in the app's asset catalog, or else an SF Symbol. On an `image` with a `url`, it shows until the URL's image has loaded.
- `padding` on a view that is not a stack or a scroll view puts it in a stack with that padding. The other common properties, except the accessibility ones, then apply to that stack, so a background covers the padding.
- A tap anywhere in a `vstack` or `hstack` with `onTap` runs its actions, so a whole row can be tapped, and the stack is highlighted while it is pressed; `"highlight": false` turns that off. A control inside it, such as a button or a switch, keeps its own taps and does not highlight the stack. Give the stack an `accessibilityLabel` and VoiceOver reads it as one button.
- `overlay` puts a node in front of the view, or an array of them, later ones further front. Each is `{ "alignment": ..., "offset": { "x": ..., "y": ... }, "content": node }`. `alignment` is `fill`, the default, `center`, `top`, `bottom`, `leading`, `trailing`, `topLeading`, `topTrailing`, `bottomLeading` or `bottomTrailing`. `offset` moves the content, x toward the trailing edge and y down; `fill` takes none. The view decides the size, and `clipsToBounds` clips the overlay too. References in `content` read the item's data. Touches go through an overlay to the view behind it unless a node in the overlay sets an event. `overlay` takes only a constant.
  ```json
  { "type": "image", "url": "$cover", "width": 120, "height": 120,
    "overlay": { "alignment": "topTrailing", "offset": { "x": -6, "y": 6 },
                 "content": { "type": "label", "text": "$badge", "font": "caption2", "padding": 4,
                              "background": "systemRed", "textColor": "white", "cornerRadius": 4 } } }
  ```
- A `textfield` has a rounded border. `label` and `textfield` follow Dynamic Type.

## Values

- **Colors**: a system color name, such as `label`, `secondaryLabel`, `systemBackground`, `separator` or `systemBlue`; `#RRGGBB` or `#RRGGBBAA`; or `{ "light": "#000000", "dark": "#FFFFFF" }`. A border's color is read once and does not follow a later change between light and dark mode.
- **Fonts**: a text style, `largeTitle`, `title1` to `title3`, `headline`, `subheadline`, `body`, `callout`, `footnote`, `caption1` or `caption2`; or `{ "size": 15, "weight": "semibold" }`, with a weight from `ultraLight` to `black`. The size is that at the default text size and grows and shrinks with the user's text size, as body text does.
- **Insets**, for `padding`: one number for every edge, or an object with any of `top`, `leading`, `bottom`, `trailing`, `horizontal` and `vertical`. An edge wins over its axis, and edges not given are 0.
- **Lengths**, such as `width` and `minLength`, are finite and not negative; `aspectRatio` is greater than 0.

## Events and actions

`onTap`, `onChange` and `onReturn` take an action, or a list of actions that run in order:

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "track", "event": "like", "liked": "$liked" }
]
```

Parameters can be references. They are read when the action runs, so the second action above sees the data as the first one left it.

| Action | Parameters | Does |
| --- | --- | --- |
| `navigate` | `url` | Hands the URL to the closure you register, such as your router. |
| `openURL` | `url` | Hands the URL to the closure you register, such as `UIApplication.shared.open`. |
| `set` | `path`, `value` | Sets the item's data at `path` to `value`. |
| `toggle` | `path` | Flips the Bool at `path`; a missing one becomes `true`. |

`navigate` and `openURL` do nothing, and report that, until you register them. `path` is a key of the item's data, written as a constant.

`onChange` carries a value: the text of a `textfield`, the state of a `switch`, the value of a `slider`. A `set` without `value` stores it, which keeps the data in step with the control:

```json
{ "type": "switch", "isOn": "$enabled", "onChange": { "action": "set", "path": "enabled" } }
```

Nothing is sent to the server. To do that, or anything else, register an action:

```swift
var actions = ActionRegistry.standard
actions.register(ActionSpec("track", parameters: ["event": PropertySpec(.string), "liked": PropertySpec(.bool)])) { context in
    analytics.track(context.string("event"), liked: context.bool("liked"))
}
```

`ActionContext` reads parameters with `string`, `url`, `bool` and `number`, which report a value of the wrong type, or gives them all in `parameters`. `event` is the event's value, `data` the item's data, and `update { $0["key"] = … }` changes the data as `set` does.

`item` tells which item the action runs for: its `id`, its `section` and its `template`, or, for a section's header, `isHeader` and no `id`. `sourceView` is the view that sent the event and `page` the `DocumentViewController`, for presenting from them:

```swift
actions.register(ActionSpec("share", parameters: ["url": PropertySpec(.url)])) { context in
    guard let url = context.url("url"), let page = context.page else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = context.sourceView
    page.present(sheet, animated: true)
}
```

An action can wait, for a request for example. A handler that uses `await` or `try` is asynchronous: it fails when it throws. An asynchronous action takes `onSuccess` and `onFailure`, an action or a list of actions that run when the handler returns or throws, and the actions after it in the list run once it and its `onSuccess` or `onFailure` are done. Change the data first and undo the change when the request fails:

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "like", "id": "$id", "onFailure": { "action": "toggle", "path": "liked" } }
]
```

```swift
actions.register(ActionSpec("like", parameters: ["id": PropertySpec(.string)])) { context in
    // Throwing runs onFailure.
    let count = try await api.like(context.string("id"))
    context.update { $0["likes"] = .number(Double(count)) }
}
```

`update` works while the handler waits, and after it returns. The change goes to the item the action ran for, even when its cell shows another item by then, and applies to the item's data as it is at that time; the actions that run after a wait read that data too. When the page no longer has the item, after `setDocument` for example, nothing changes and those actions do not run. When the page goes away, the handler's task is cancelled.

Other actions report `onSuccess` and `onFailure` as unknown properties, and so do releases before 0.4.0. The manifest marks asynchronous actions with `async`.

## The page

`DocumentViewController` shows a document in a collection view. The page is the collection view's delegate and data source; the rest of `collectionView` is yours to configure, for example its content insets. Set `scrollViewDelegate` to get the scroll view's callbacks.

Each cell builds its template's views the first time it is shown and keeps them; showing another item only sends that item's data to the bindings. `set` and `toggle` change the page's copy of the item's data, so the change stays when the cell scrolls away and back, and the cell resizes to its new content.

```swift
controller.setDocument(newDocument)
```

`setDocument` shows a newer document. Sections and items are matched by `id` and animated, and the new document's data replaces the changes made on the device.

To change part of the page, such as an item whose price changed, apply a patch:

```json
{ "v": 1,
  "templates": { "notice": { "type": "label", "text": "$text", "padding": 12 } },
  "operations": [
    { "op": "replaceItems", "items": [ { "id": "p1", "template": "product", "data": { "title": "Keyboard", "price": "89.00" } } ] },
    { "op": "insertItems", "section": "today", "after": "p1", "items": [ { "id": "n1", "template": "notice", "data": { "text": "Back in stock" } } ] },
    { "op": "removeItems", "ids": ["p3"] }
  ] }
```

```swift
let patch = try DocumentDecoder().decodePatch(data)
controller.apply(patch)
```

`replaceItems` and `replaceSections` replace the items and sections of the same `id`, in their place. `insertItems` inserts items into `section` after the item `after`, and `insertSections` inserts sections after the section `after`; without `after`, they go first. `removeItems` and `removeSections` remove those of the `ids`, a section with its items. `templates` is optional: it adds templates, and replaces those of the same name, whose cells are built again.

The operations run in order, and the page animates them together. Replaced and inserted items and sections show the patch's data; unlike with `setDocument`, the other items keep the changes made on the device. A patch that refers to an `id` the page does not have, or inserts one it has, is applied without that item, section or operation. The library sends no requests: a patch comes from your own request, or from the response in an asynchronous action, applied with `context.page?.apply(patch)`. Releases before 0.4.0 do not apply patches.

### Loading more

A section with more items than the document carries says so with `more`, whatever the backend needs to send the next ones, such as a cursor. The library hands it back without reading it:

```json
{ "id": "feed", "more": { "cursor": "c2" }, "items": [ … ] }
```

When the user scrolls to within five items of the end of such a section, the page calls `onLoadMore` with the section's `id` and its `more`. Load the next items and append them with a patch, with the `more` after them, or without `more` at the end:

```json
{ "v": 1, "operations": [ { "op": "appendItems", "section": "feed", "items": [ … ], "more": { "cursor": "c3" } } ] }
```

```swift
controller.onLoadMore = { [weak controller] section, more in
    Task {
        do {
            let data = try await api.nextPage(section: section, after: more)
            controller?.apply(try DocumentDecoder().decodePatch(data))
        } catch {
            controller?.showLoadMoreFailure(in: section)
        }
    }
}
```

Until then, a list or grid section shows a spinner below its items, and the page does not ask for that section again. After `showLoadMoreFailure(in:)` it shows a button that tries again, and scrolling back to the end of the section tries again too. A carousel shows neither and asks when it is scrolled near its end. A patch that appends to, replaces or inserts the section, or `setDocument`, ends the loading.

The spinner and the button, whose VoiceOver label is in English, are the default. To show your own, such as localized text, set `makeLoadMoreView` to make a `UIView` that adopts `LoadMoreView`: the page calls its `showLoading()`, and its `showFailure(retry:)` with a closure for your button to call. It sizes itself with Auto Layout, and the page reuses it for other sections.

```swift
controller.makeLoadMoreView = { MyLoadMoreView() }
```

Releases before 0.5.0 ignore `more` and skip `appendItems`.

### Loading, failure and refreshing

A page created without a document shows `loadingView` until `setDocument`. `showLoading()` shows it again in place of the sections, and `showFailure(retry:)` shows `failureView`, whose button calls `retry()`: that shows `loadingView` again and calls your closure. `setDocument` and `apply` show the sections again. A page without items, none of whose sections has `more`, shows `emptyView`.

Setting `onRefresh` adds a refresh control. The page calls it when the user pulls down, with a closure to call when you are done:

```swift
let controller = DocumentViewController(actions: actions)   // shows loadingView
func load() {
    Task {
        do {
            controller.setDocument(try DocumentDecoder().decode(try await api.page()))
        } catch {
            controller.showFailure { load() }
        }
    }
}
load()

controller.onRefresh = { done in
    Task {
        if let data = try? await api.page(), let document = try? DocumentDecoder().decode(data) {
            controller.setDocument(document)
        }
        done()
    }
}
```

The views are shown behind the sections, filling the collection view, so an empty or failed page can still be pulled. The default ones are a spinner and English messages; set `loadingView`, `failureView` and `emptyView` to your own, such as a skeleton of the page or localized text, and have your failure view call `retry()`. A refresh that fails needs no `showFailure`: call `done`, and the page keeps what it shows.

## Your own components

Register a type with what it accepts and how it builds its view:

```swift
var components = ComponentRegistry<UIView>.standard
components.register(ComponentSpec("rating", properties: ["value": PropertySpec(.number)])) { context in
    RatingView().onValue(context.number("value")) { view, value in
        view.rating = value ?? 0
    }
}
let controller = DocumentViewController(document: document, components: components, actions: actions)
```

`BuildContext` reads each property as a publisher, or returns nil when the node does not set it. A constant emits once; a reference emits each value of the item's data. `number`, `length`, `integer`, `bool`, `string`, `url`, `color`, `font` and `insets` read the types above, `choice` one of a set of strings, and `value` anything else. `onValue` applies a property to a view, and `onEvent` runs `context.action(.onTap)` on one of the view's publishers, with the view as the actions' `sourceView`. To run the actions yourself, call what `context.action` returns with the event's value and the view: `action(.bool(isOn), source: view)`. Children are built for you, in `context.children`, when the spec says `acceptsChildren: true`. The common properties are applied to the view you return.

Registering a type that exists replaces it.

## Images

The `url` of an `image` is loaded by `ImageLoader.urlSession`, which keeps the images in memory. To use your own image pipeline:

```swift
let loader = ImageLoader { url, completion in
    let request = imagePipeline.load(url) { image in completion(image) }
    return AnyCancellable { request.cancel() }
}
let components = ComponentRegistry<UIView>.standard(imageLoader: loader)
```

When the URL changes, the view cancels the earlier load and ignores its result.

## Problems in a document

A document fails to decode only when it is not JSON, has another version, or gets its outline wrong: `v`, `templates`, `sections`, the `id` of each section and item, and the `template` of each item and header. Everything else is shown as well as it can be, and the problem is reported to `onIssue`, once per document:

- an unknown component type is shown as the node's `fallback`, or else as an empty view;
- an unknown property or event, or a reference where only a constant is accepted, is ignored;
- a value of the wrong type is treated as missing;
- a node that is not an object with a `type`, an unknown or malformed action, a duplicate `id`, and an item or header with an unknown template are left out;
- an unknown `layout` is a list;
- in a patch, an unknown operation, and an `id` the page does not have, or has already where the patch inserts it, are skipped.

Each `Issue` says where it is, as in `templates.product.children[2]`, or `operations[1].items[0]` for a patch. The issues of a patch are reported each time it is applied.

## Versions

An app stays at the release it was built with, so a backend writes documents that older releases read too. Version 1 of the format grows only by additions, and a release reports what it does not know and leaves it out. `DocumentVersion.minor` tells which additions a release reads:

| `minor` | Release | Adds |
| --- | --- | --- |
| 0 | 0.1.0 | Version 1 |
| 1 | 0.2.0 | `onTap` on `vstack` and `hstack`; `fallback` |
| 2 | 0.3.0 | `overlay`; the `grid` layout; `highlight` on `vstack` and `hstack` |
| 3 | 0.4.0 | `onSuccess` and `onFailure` on asynchronous actions; patches |
| 4 | 0.5.0 | `more` on a section; `appendItems`; the colors `systemMint`, `systemCyan` and `systemBrown` |

Send it with your requests, so that the backend writes what the app reads:

```swift
request.setValue("\(DocumentVersion.current).\(DocumentVersion.minor)", forHTTPHeaderField: "Document-Version")
```

A node can also carry a `fallback`, a node shown instead when the app does not know the node's type, such as a component added in a later release. A fallback can have a fallback of its own. Releases before 0.2.0 do not read `fallback`.

```json
{ "type": "rating", "value": "$score", "fallback": { "type": "label", "text": "$scoreText" } }
```

## The manifest

[`manifest.json`](manifest.json) lists the built-in components with their properties, the type of each and whether it takes a reference, the properties every component takes, and the built-in actions with their parameters and whether each is asynchronous, the operations of a patch, and the version it describes, `v` and `minor`. A code generator on the backend can read it to type-check the documents it writes. With your own components and actions:

```swift
let manifest = try Manifest(components: components, actions: actions).encoded()
```

[`protocol/`](protocol/README.md) describes the format itself, without iOS terms, for the backend and for renderers on other platforms, with [cases](protocol/cases/README.md) that every renderer runs.

## Example app

`Example/Example.xcodeproj` is an iOS app that uses this package as a local package. Open it in Xcode and run the `Example` scheme on an iOS Simulator. Every screen, the menu included, is a JSON document in `Example/Example/Documents`; a `navigate` to `example://store` opens `store.json`. `Pages.swift` registers the router, `openURL`, `addToCart` and `showProduct` actions and a `rating` component. The Feed screen loads as from a server, a second late: it shows the loading and failure views, loads its next pages from `feed-2.json` and `feed-3.json`, patches named by `more`, and loads again when pulled down.

<img src="docs/images/example-store.png" width="300" alt="Store screen"> <img src="docs/images/example-settings.png" width="300" alt="Settings screen">

## License

MIT. See [LICENSE](LICENSE).
