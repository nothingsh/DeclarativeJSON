# DeclarativeJSON

**English** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

Server-driven lists for UIKit. A JSON document names the cell templates, the items and what a tap does; the library builds the cells with [DeclarativeUIKit](https://github.com/nothingsh/DeclarativeUIKit) stacks, binds them with [DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) and shows them in a collection view.

> The first version is being built. The document format can still change before 0.1.0.

```json
{
  "v": 1,
  "templates": {
    "product": {
      "type": "hstack", "spacing": 12, "alignment": "center", "padding": 16,
      "children": [
        { "type": "image", "url": "$image", "width": 56, "height": 56, "cornerRadius": 8 },
        { "type": "vstack", "spacing": 4, "children": [
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

let actions = ActionRegistry.standard
actions.register("navigate") { params, _ in router.open(params.url("url")) }

let controller = DocumentViewController(document: document, components: .standard, actions: actions)
```

A `$` value refers to a key of the item's `data`. Everything else is a constant. Actions run in the app: `navigate` and `openURL` hand a URL to closures you register, `set` and `toggle` change the item's data on the device, and an app can register actions of its own. The registry can print a manifest of every component, property and action it accepts, for the backend that generates the documents.

## Requirements

- iOS 13+
- Swift 5.9+

## Installation

Swift Package Manager. In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", branch: "main")
]
```

DeclarativeUIKit and DeclarativeCombine come with it.

## License

MIT. See [LICENSE](LICENSE).
