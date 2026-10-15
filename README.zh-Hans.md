# DeclarativeJSON

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md)

UIKit 的服务端驱动列表。一份 JSON 文档写明 cell 的模板、条目和点击后做什么；库用 [DeclarativeUIKit](https://github.com/nothingsh/DeclarativeUIKit) 的 stack 搭出 cell，用 [DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) 绑定，再放进 collection view 显示。

> 第一个版本正在开发中。0.1.0 之前文档格式仍可能变化。

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

以 `$` 开头的值引用条目 `data` 里的一个键，其余都是常量。动作在 App 本地执行：`navigate` 和 `openURL` 把 URL 交给你注册的闭包，`set` 和 `toggle` 在设备上修改条目的数据，App 也可以注册自己的动作。注册表能输出一份清单，列出它接受的全部组件、属性和动作，给生成文档的后端使用。

## 要求

- iOS 13+
- Swift 5.9+

## 安装

Swift Package Manager。在 `Package.swift` 里：

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", branch: "main")
]
```

DeclarativeUIKit 和 DeclarativeCombine 会一并引入。

## 许可

MIT，见 [LICENSE](LICENSE)。
