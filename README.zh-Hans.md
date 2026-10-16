<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/declarative-json-dark.svg">
    <img src="docs/images/declarative-json-light.svg" alt="DeclarativeJSON — 由 JSON 搭建的 UIKit 服务端驱动列表。" width="850">
  </picture>
</p>

# DeclarativeJSON

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md)

UIKit 的服务端驱动列表。一份 JSON 文档写明 cell 模板、条目和点按后做什么；库用 [DeclarativeUIKit](https://github.com/nothingsh/DeclarativeUIKit) 的 stack 搭出 cell，用 [DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) 绑定数据，放进 collection view 显示。

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

以 `$` 开头的值引用条目 `data` 里的键，其余都是常量。动作在 App 里执行：`navigate` 与 `openURL` 把 URL 交给你注册的闭包，`set` 与 `toggle` 在设备上修改条目的数据，你也可以注册自己的动作和组件。清单（manifest）列出所有组件、属性和动作，供生成文档的后端使用。

## 目录

- [要求](#要求)
- [安装](#安装)
- [文档](#文档)
- [引用](#引用)
- [组件](#组件)
- [取值](#取值)
- [事件与动作](#事件与动作)
- [页面](#页面)
- [自定义组件](#自定义组件)
- [图片](#图片)
- [文档里的问题](#文档里的问题)
- [版本](#版本)
- [清单](#清单)
- [示例 App](#示例-app)

## 要求

- iOS 15+
- Swift 5.9+

## 安装

使用 Swift Package Manager。在 `Package.swift` 中：

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", from: "0.1.0")
]
```

DeclarativeUIKit 和 DeclarativeCombine 会一并引入。

## 文档

文档有三个键：

- `v`，格式的版本。本版本读取第 1 版；其他版本的文档解码失败，抛出 `DocumentError.unsupportedVersion`。后来的版本在第 1 版上新增了什么，见[版本](#版本)。
- `templates`，从名字到 cell 或 header 的视图树。
- `sections`，按顺序排列。section 有 `id`、`layout`、可选的 `header` 和它的 `items`。

```json
{ "id": "featured", "layout": "carousel",
  "header": { "template": "title", "data": { "text": "Featured" } },
  "items": [ { "id": "f1", "template": "card", "data": { "name": "Keyboard" } } ] }
```

`layout` 取 `list`，一列占满宽度、高度随内容的 cell；或取 `carousel`，一行横向滚动。默认是 `list`。条目有在整页唯一的 `id`、所用 `template` 的名字和它的 `data`（一个 JSON 对象）。header 同样有 `template` 和 `data`。

模板里的节点是一个对象，带 `type`、它的属性，stack 还带 `children`，还可以带 [`fallback`](#版本)：

```json
{ "type": "vstack", "spacing": 4, "children": [
  { "type": "label", "text": "$title", "font": "headline" }
]}
```

## 引用

属性值是以 `$` 开头的字符串时，取条目数据里该键的值：`"text": "$title"`。引用就是整个值，不拼接、不运算、不做条件判断，所以格式化好的文字、价格和 URL 由后端放进 `data`，拿来就能显示。`$$` 表示美元符号：`"$$5 off"` 是文字 `$5 off`。`data` 里的字符串永远不是引用。

引用的键不存在或为 `null`，或者值的类型不对，该属性按未设置处理，视图显示默认值。类型不对还会上报。

没有 `not`，所以可见性有两个属性。共用一个引用的两个视图，一个写 `isHidden`，一个写 `isVisible`：

```json
{ "type": "button", "image": "heart", "isHidden": "$liked", "onTap": { "action": "toggle", "path": "liked" } },
{ "type": "button", "image": "heart.fill", "isVisible": "$liked", "onTap": { "action": "toggle", "path": "liked" } }
```

请发送 `false`，不要省略这个键：值缺失时两个视图都会显示。

## 组件

属性名就是设置它的 DeclarativeUIKit modifier 的名字。带标签参数的 modifier 取以这些标签为键的对象，例如 `"border": { "color": "separator", "width": 1 }`。

| 类型 | 属性 | 事件 |
| --- | --- | --- |
| `vstack` | `alignment`（`leading`、`center`、`trailing`、`fill`）、`spacing` | `onTap` |
| `hstack` | `alignment`（`top`、`center`、`bottom`、`firstTextBaseline`、`lastTextBaseline`、`fill`）、`spacing` | `onTap` |
| `vscroll`、`hscroll` | `vstack` 和 `hstack` 的属性，另有 `showsIndicators`、`bounces` | |
| `spacer` | `minLength`，只接受常量 | |
| `label` | `text`、`font`、`textColor`、`numberOfLines`、`textAlignment`、`adjustsFontSizeToFitWidth` | |
| `image` | `url`、`image`、`contentMode`（`scaleToFill`、`scaleAspectFit`、`scaleAspectFill`、`center`） | |
| `button` | `title`、`titleColor`、`image`、`isEnabled` | `onTap` |
| `textfield` | `text`、`placeholder`、`font`、`textColor`、`textAlignment`、`keyboardType`、`returnKeyType`、`isSecureTextEntry`、`isEnabled` | `onChange`、`onReturn` |
| `switch` | `isOn`、`onTintColor`、`isEnabled` | `onChange` |
| `slider` | `value`、`minimumValue`、`maximumValue`、`minimumTrackTintColor`、`maximumTrackTintColor`、`isEnabled` | `onChange` |
| `progress` | `progress`、`progressTintColor`、`trackTintColor` | |
| `activity` | `isAnimating`、`hidesWhenStopped`、`color` | |

每个组件还接受 `width`、`height`、`aspectRatio`、`padding`、`background`、`cornerRadius`、`clipsToBounds`、`border`、`alpha`、`tintColor`、`isHidden`、`isVisible`、`accessibilityLabel` 和 `accessibilityIdentifier`。

- `image` 与 `button` 的 `image` 是 App asset catalog 里的图片名，找不到时按 SF Symbol 处理。`image` 同时有 `url` 时，它一直显示到 URL 的图片加载完成。
- 不是 stack 也不是滚动视图的视图设了 `padding`，会被放进一个带该内边距的 stack。除无障碍属性外，其余通用属性都作用在这个 stack 上，所以背景会覆盖内边距。
- 设了 `onTap` 的 `vstack` 或 `hstack`，点按其中任意位置都会执行它的动作，因此可以点按整行。其中的控件，如按钮或开关，仍处理自己的点按。给这个 stack 设 `accessibilityLabel`，VoiceOver 会把它读作一个按钮。
- `textfield` 带圆角边框。字体是 text style 时，`label` 与 `textfield` 跟随动态字体。

## 取值

- **颜色**：系统颜色名，如 `label`、`secondaryLabel`、`systemBackground`、`separator`、`systemBlue`；`#RRGGBB` 或 `#RRGGBBAA`；或 `{ "light": "#000000", "dark": "#FFFFFF" }`。边框颜色只读取一次，之后在浅色与深色模式间切换时不会跟着变。
- **字体**：text style，即 `largeTitle`、`title1` 到 `title3`、`headline`、`subheadline`、`body`、`callout`、`footnote`、`caption1` 或 `caption2`；或 `{ "size": 15, "weight": "semibold" }`，字重从 `ultraLight` 到 `black`。
- **内边距**（`padding`）：一个数字表示四边相同，或一个对象，含 `top`、`leading`、`bottom`、`trailing`、`horizontal`、`vertical` 中任意几个。单边优先于所在的轴，没写的边为 0。
- **长度**，如 `width` 和 `minLength`，必须是有限且非负的数；`aspectRatio` 必须大于 0。

## 事件与动作

`onTap`、`onChange` 和 `onReturn` 接受一个动作，或按顺序执行的动作数组：

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "track", "event": "like", "liked": "$liked" }
]
```

参数可以是引用，在动作执行时才读取，所以上面第二个动作看到的是第一个动作改过的数据。

| 动作 | 参数 | 作用 |
| --- | --- | --- |
| `navigate` | `url` | 把 URL 交给你注册的闭包，例如你的 router。 |
| `openURL` | `url` | 把 URL 交给你注册的闭包，例如 `UIApplication.shared.open`。 |
| `set` | `path`、`value` | 把条目数据中 `path` 处设为 `value`。 |
| `toggle` | `path` | 翻转 `path` 处的 Bool；不存在时变为 `true`。 |

注册之前，`navigate` 和 `openURL` 什么也不做，并上报这一点。`path` 是条目数据的键，只能写常量。

`onChange` 带一个值：`textfield` 的文字、`switch` 的开关状态、`slider` 的值。不写 `value` 的 `set` 保存这个值，让数据与控件保持一致：

```json
{ "type": "switch", "isOn": "$enabled", "onChange": { "action": "set", "path": "enabled" } }
```

不会向服务器发送任何东西。要发送，或者做别的事，就注册一个动作：

```swift
var actions = ActionRegistry.standard
actions.register(ActionSpec("track", parameters: ["event": PropertySpec(.string), "liked": PropertySpec(.bool)])) { context in
    analytics.track(context.string("event"), liked: context.bool("liked"))
}
```

`ActionContext` 用 `string`、`url`、`bool` 和 `number` 读取参数，类型不对时会上报；`parameters` 给出全部参数。`event` 是事件的值，`data` 是条目的数据，`update { $0["key"] = … }` 像 `set` 一样修改数据。

`update` 也可以在处理闭包返回之后调用，比如请求完成时。改动仍然落到触发动作的那个条目上，即使它的 cell 此时已经在显示别的条目；改动作用在条目当时的数据上。页面里已经没有这个条目时（比如 `setDocument` 之后），什么也不改。

```swift
actions.register(ActionSpec("like", parameters: ["id": PropertySpec(.string)])) { context in
    Task {
        let liked = await api.like(context.string("id"))
        context.update { $0["liked"] = .bool(liked) }
    }
}
```

## 页面

`DocumentViewController` 在 collection view 里显示文档。它的 `collectionView` 可以由你配置，例如加上下拉刷新。

每个 cell 第一次显示时按模板建出视图并保留；显示另一个条目时只把该条目的数据发给绑定。`set` 和 `toggle` 修改的是页面持有的条目数据，所以 cell 滚出再滚回时改动仍在，cell 也会按新内容调整高度。

```swift
controller.setDocument(newDocument)
```

`setDocument` 显示更新后的文档。section 与条目按 `id` 对应并带动画，新文档的数据替换设备上做过的改动。

## 自定义组件

注册一个类型，写明它接受什么、怎样建出视图：

```swift
var components = ComponentRegistry<UIView>.standard
components.register(ComponentSpec("rating", properties: ["value": PropertySpec(.number)])) { context in
    RatingView().onValue(context.number("value")) { view, value in
        view.rating = value ?? 0
    }
}
let controller = DocumentViewController(document: document, components: components, actions: actions)
```

`BuildContext` 把每个属性读成 publisher，节点没设该属性时返回 nil。常量发出一次；引用随条目数据的每个值发出。`number`、`length`、`integer`、`bool`、`string`、`url`、`color`、`font` 和 `insets` 读取上文的各种类型，`choice` 读取一组字符串之一，`value` 读取其他任何东西。`onValue` 把属性应用到视图，`onEvent` 在视图的某个 publisher 上执行 `context.action(.onTap)`。spec 写了 `acceptsChildren: true` 时，子节点已替你建好，放在 `context.children`。通用属性会作用在你返回的视图上。

注册已有的类型会替换它。

## 图片

`image` 的 `url` 由 `ImageLoader.urlSession` 加载，图片缓存在内存里。要用自己的图片加载方案：

```swift
let loader = ImageLoader { url, completion in
    let request = imagePipeline.load(url) { image in completion(image) }
    return AnyCancellable { request.cancel() }
}
let components = ComponentRegistry<UIView>.standard(imageLoader: loader)
```

URL 变化时，视图取消之前的加载并忽略它的结果。

## 文档里的问题

只有在不是 JSON、版本不同，或骨架写错时，文档才会解码失败。骨架指 `v`、`templates`、`sections`、每个 section 和条目的 `id`，以及每个条目和 header 的 `template`。其余问题都尽量显示，并上报给 `onIssue`，每份文档同一问题只报一次：

- 未知的组件类型显示为节点的 `fallback`，没有时显示为空视图；
- 未知的属性或事件，以及在只接受常量处写的引用，会被忽略；
- 类型不对的值按缺失处理；
- 不是带 `type` 的对象的节点、未知或写错的动作、重复的 `id`、模板不存在的条目或 header 会被去掉；
- 未知的 `layout` 按列表显示。

每个 `Issue` 都写明位置，例如 `templates.product.children[2]`。

## 版本

App 停留在构建它时的版本，所以后端写的文档也要让旧版本读得懂。格式第 1 版只做增量，一个版本遇到不认识的内容会上报并跳过。`DocumentVersion.minor` 表示一个版本读得懂哪些新增：

| `minor` | 库版本 | 新增 |
| --- | --- | --- |
| 0 | 0.1.0 | 第 1 版 |
| 1 | 0.2.0 | `vstack` 和 `hstack` 的 `onTap`；`fallback` |

请求时带上它，后端就只写 App 读得懂的内容：

```swift
request.setValue("\(DocumentVersion.current).\(DocumentVersion.minor)", forHTTPHeaderField: "Document-Version")
```

节点还可以带一个 `fallback`：App 不认识这个节点的类型时（比如后来的版本才加的组件），改为显示它。`fallback` 自己也可以再带 `fallback`。0.2.0 之前的版本不读 `fallback`。

```json
{ "type": "rating", "value": "$score", "fallback": { "type": "label", "text": "$scoreText" } }
```

## 清单

[`manifest.json`](manifest.json) 列出内置组件及其属性、每个属性的类型和是否接受引用、所有组件共有的属性，以及内置动作和它们的参数，还有它描述的版本 `v` 与 `minor`。后端的代码生成器可以读取它，检查自己写出的文档。加上你自己的组件和动作：

```swift
let manifest = try Manifest(components: components, actions: actions).encoded()
```

## 示例 App

`Example/Example.xcodeproj` 是一个以本地 package 方式使用本库的 iOS App。用 Xcode 打开，在 iOS 模拟器上运行 `Example` scheme。每个画面，包括菜单，都是 `Example/Example/Documents` 里的一份 JSON 文档；`navigate` 到 `example://store` 会打开 `store.json`。`Pages.swift` 注册了 router、`openURL`、一个 `addToCart` 动作和一个 `rating` 组件。

<img src="docs/images/example-store.png" width="300" alt="商店画面"> <img src="docs/images/example-settings.png" width="300" alt="设置画面">

## 许可证

MIT。见 [LICENSE](LICENSE)。
