# DeclarativeJSON

[English](README.md) | [简体中文](README.zh-Hans.md) | **繁體中文**

UIKit 的伺服端驅動列表。一份 JSON 文件寫明 cell 的範本、項目和點擊後做什麼；函式庫用 [DeclarativeUIKit](https://github.com/nothingsh/DeclarativeUIKit) 的 stack 搭出 cell，用 [DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) 繫結，再放進 collection view 顯示。

> 第一個版本正在開發中。0.1.0 之前文件格式仍可能變動。

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
          { "type": "label", "text": "$subtitle", "font": "footnote", "color": "secondaryLabel", "lines": 2 }
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

以 `$` 開頭的值引用項目 `data` 裡的一個鍵，其餘都是常數。動作在 App 本機執行：`navigate` 和 `openURL` 把 URL 交給你註冊的閉包，`set` 和 `toggle` 在裝置上修改項目的資料，App 也可以註冊自己的動作。註冊表能輸出一份清單，列出它接受的全部元件、屬性和動作，給產生文件的後端使用。

## 需求

- iOS 13+
- Swift 5.9+

## 安裝

Swift Package Manager。在 `Package.swift` 裡：

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", branch: "main")
]
```

DeclarativeUIKit 和 DeclarativeCombine 會一併引入。

## 授權

MIT，見 [LICENSE](LICENSE)。
