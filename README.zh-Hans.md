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
    .package(url: "https://github.com/nothingsh/DeclarativeJSON.git", .upToNextMinor(from: "0.5.0"))
]
```

1.0 之前，0.6.0 这样的次版本可能有破坏性变化（见 [CHANGELOG](CHANGELOG.md)），所以这里只接受 0.5 的修订版本。DeclarativeUIKit 和 DeclarativeCombine 会一并引入。

## 文档

文档有三个键：

- `v`，格式的版本。本版本读取第 1 版；其他版本的文档解码失败，抛出 `DocumentError.unsupportedVersion`。后来的版本在第 1 版上新增了什么，见[版本](#版本)。
- `templates`，从名字到 cell 或 header 的视图树。
- `sections`，按顺序排列。section 有 `id`、`layout`、可选的 `header`、它的 `items`，还有[后续条目](#加载更多)时有 `more`。

```json
{ "id": "featured", "layout": "carousel",
  "header": { "template": "title", "data": { "text": "Featured" } },
  "items": [ { "id": "f1", "template": "card", "data": { "name": "Keyboard" } } ] }
```

`layout` 取 `list`，一列占满宽度、高度随内容的 cell；取 `carousel`，一行横向滚动；或取 `grid`，每行若干等宽的 cell。默认是 `list`。`grid` 另有 `columns`（每行几个 cell，默认 2）和 `spacing`（cell 之间的横向与纵向间距，默认 0）。一行的高度取这一行里最高的 cell，每个 cell 保持自己的高度，靠这一行的顶部。条目有在整页唯一的 `id`、所用 `template` 的名字、它的 `data`（一个 JSON 对象），以及可选的 [`tracking`](#曝光)。header 同样有 `template` 和 `data`。

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
| `vstack` | `alignment`（`leading`、`center`、`trailing`、`fill`）、`spacing`、`highlight` | `onTap` |
| `hstack` | `alignment`（`top`、`center`、`bottom`、`firstTextBaseline`、`lastTextBaseline`、`fill`）、`spacing`、`highlight` | `onTap` |
| `vscroll`、`hscroll` | 与 `vstack`、`hstack` 相同的 `alignment` 和 `spacing`，另有 `showsIndicators`、`bounces` | |
| `spacer` | `minLength`，只接受常量 | |
| `label` | `text`、`markdown`、`font`、`textColor`、`numberOfLines`、`textAlignment`、`lineHeight`、`adjustsFontSizeToFitWidth` | |
| `image` | `url`、`image`、`contentMode`（`scaleToFill`、`scaleAspectFit`、`scaleAspectFill`、`center`） | |
| `button` | `title`、`titleColor`、`image`、`isEnabled` | `onTap` |
| `textfield` | `text`、`placeholder`、`font`、`textColor`、`textAlignment`、`keyboardType`、`returnKeyType`、`isSecureTextEntry`、`isEnabled` | `onChange`、`onReturn` |
| `switch` | `isOn`、`onTintColor`、`isEnabled` | `onChange` |
| `slider` | `value`、`minimumValue`、`maximumValue`、`minimumTrackTintColor`、`maximumTrackTintColor`、`isEnabled` | `onChange` |
| `progress` | `progress`、`progressTintColor`、`trackTintColor` | |
| `activity` | `isAnimating`、`hidesWhenStopped`、`color` | |

每个组件还接受 `width`、`height`、`aspectRatio`、`padding`、`background`、`cornerRadius`、`clipsToBounds`、`border`、`alpha`、`tintColor`、`overlay`、`isHidden`、`isVisible`、`accessibilityLabel` 和 `accessibilityIdentifier`。

- `image` 与 `button` 的 `image` 是 App asset catalog 里的图片名，找不到时按 SF Symbol 处理。`image` 同时有 `url` 时，它一直显示到 URL 的图片加载完成。
- 不是 stack 也不是滚动视图的视图设了 `padding`，会被放进一个带该内边距的 stack。除无障碍属性外，其余通用属性都作用在这个 stack 上，所以背景会覆盖内边距。
- 设了 `onTap` 的 `vstack` 或 `hstack`，点按其中任意位置都会执行它的动作，因此可以点按整行；按住时 stack 显示高亮，`"highlight": false` 关闭高亮。其中的控件，如按钮或开关，仍处理自己的点按，也不让 stack 高亮。给这个 stack 设 `accessibilityLabel`，VoiceOver 会把它读作一个按钮。
- `overlay` 在视图前面放一个节点，或一组节点，后面的在上层。每个是 `{ "alignment": ..., "offset": { "x": ..., "y": ... }, "content": 节点 }`。`alignment` 取 `fill`（默认）、`center`、`top`、`bottom`、`leading`、`trailing`、`topLeading`、`topTrailing`、`bottomLeading` 或 `bottomTrailing`。`offset` 移动内容，x 朝 trailing 边、y 朝下；`fill` 不接受 `offset`。尺寸由视图决定，`clipsToBounds` 也会裁掉叠放内容。`content` 里的引用读条目数据。除非叠放里有节点设了事件，触摸会穿过它交给后面的视图。`overlay` 只接受常量。
  ```json
  { "type": "image", "url": "$cover", "width": 120, "height": 120,
    "overlay": { "alignment": "topTrailing", "offset": { "x": -6, "y": 6 },
                 "content": { "type": "label", "text": "$badge", "font": "caption2", "padding": 4,
                              "background": "systemRed", "textColor": "white", "cornerRadius": 4 } } }
  ```
- `repeat` 放在 `vstack`、`hstack`、`vscroll` 或 `hscroll` 里，按 `items`（数组或指向数组的引用）的每个元素，把 `template` 复制一份放进容器的子节点之间，所以各份跟着容器的间距与对齐：
  ```json
  { "type": "hstack", "spacing": 4, "children": [
    { "type": "label", "text": "Tags:" },
    { "type": "repeat", "items": "$tags",
      "template": { "type": "label", "text": "$value", "padding": 4, "background": "secondarySystemFill", "cornerRadius": 4 } }
  ]}
  ```
  条目数据里有 `"tags": ["New", "Free shipping"]` 时显示两个标签，数组变了就显示相应的个数。模板里的 `$` 引用读元素而不是条目：元素是对象时读它的键，其他元素用 `$value`。模板需要的条目数据，请放进元素里。模板里的动作照常执行，参数从元素读取，但 `set` 与 `toggle` 不能修改元素，会被移除。`repeat` 只接受 `items` 和常量 `template`；0.6.0 之前的版本改为显示它的 `fallback`。
- `label` 的 `markdown` 用行内 Markdown 代替 `text` 显示：`**粗体**`、`*斜体*`、`~~删除线~~` 和 `` `代码` ``，用 label 自己的字体与颜色。链接和图片只显示文字，不能点；标题、列表等块语法和换行按原样显示。为 0.6.0 之前的版本保留纯文本的 `text`，它们会忽略 `markdown`：
  ```json
  { "type": "label", "text": "Now ¥99, was ¥129", "markdown": "**Now ¥99** ~~¥129~~" }
  ```
- `label` 的 `lineHeight` 设定每行的高度，文字在行内垂直居中。它和字体一样随系统字号缩放。
- `textfield` 带圆角边框。`label` 与 `textfield` 跟随动态字体。

## 取值

- **颜色**：系统颜色名，如 `label`、`secondaryLabel`、`systemBackground`、`separator`、`systemBlue`；`#RRGGBB` 或 `#RRGGBBAA`；或 `{ "light": "#000000", "dark": "#FFFFFF" }`。边框颜色只读取一次，之后在浅色与深色模式间切换时不会跟着变。
- **字体**：text style，即 `largeTitle`、`title1` 到 `title3`、`headline`、`subheadline`、`body`、`callout`、`footnote`、`caption1` 或 `caption2`；或 `{ "size": 15, "weight": "semibold" }`，字重从 `ultraLight` 到 `black`。这个字号是默认文字大小下的字号，随用户设置的文字大小放大缩小，与正文相同。
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

`item` 说明动作是为哪个条目执行的：它的 `id`、`section`、`template` 和 `tracking`；section 的 header 则 `isHeader` 为 true、没有 `id`。`sourceView` 是发出事件的视图，`page` 是 `DocumentViewController`，用来从它们弹出界面：

```swift
actions.register(ActionSpec("share", parameters: ["url": PropertySpec(.url)])) { context in
    guard let url = context.url("url"), let page = context.page else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = context.sourceView
    page.present(sheet, animated: true)
}
```

动作可以等待，比如等一个请求。用了 `await` 或 `try` 的处理闭包是异步的：抛错即失败。异步动作接受 `onSuccess` 与 `onFailure`，值是一个动作或动作数组，在处理闭包返回或抛错时执行；数组里排在它后面的动作，等它和它的 `onSuccess` 或 `onFailure` 执行完才执行。先改数据，请求失败再改回来：

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "like", "id": "$id", "onFailure": { "action": "toggle", "path": "liked" } }
]
```

```swift
actions.register(ActionSpec("like", parameters: ["id": PropertySpec(.string)])) { context in
    // 抛错时执行 onFailure。
    let count = try await api.like(context.string("id"))
    context.update { $0["likes"] = .number(Double(count)) }
}
```

`update` 在处理闭包等待期间和返回之后都可以调用。改动仍然落到触发动作的那个条目上，即使它的 cell 此时已经在显示别的条目；改动作用在条目当时的数据上，等待之后执行的动作读的也是这份数据。页面里已经没有这个条目时（比如 `setDocument` 之后），什么也不改，这些动作也不执行。页面释放时，处理闭包的任务会被取消。

其他动作把 `onSuccess` 与 `onFailure` 当作未知属性上报，0.4.0 之前的版本也是如此。manifest 用 `async` 标出异步动作。

## 页面

`DocumentViewController` 在 collection view 里显示文档。页面是 collection view 的 delegate 和 data source；`collectionView` 的其余部分可以由你配置，例如内容的 inset。要收到滚动回调，设置 `scrollViewDelegate`。

每个 cell 第一次显示时按模板建出视图并保留；显示另一个条目时只把该条目的数据发给绑定。`set` 和 `toggle` 修改的是页面持有的条目数据，所以 cell 滚出再滚回时改动仍在，cell 也会按新内容调整高度。

```swift
controller.setDocument(newDocument)
```

`setDocument` 显示更新后的文档。section 与条目按 `id` 对应并带动画，新文档的数据替换设备上做过的改动。

只改页面的一部分时（比如某个条目的价格变了），应用一个 patch：

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

`replaceItems` 和 `replaceSections` 原地替换 `id` 相同的条目和 section。`insertItems` 把条目插到 `section` 里条目 `after` 的后面，`insertSections` 把 section 插到 section `after` 的后面；不写 `after` 时插在最前面。`removeItems` 和 `removeSections` 删除 `ids` 里的条目和 section，section 连同它的条目一起删除。`templates` 可选：加入新模板，替换同名的模板，用到它的 cell 会重建。

操作按顺序执行，页面一起做动画。被替换或新插入的条目和 section 显示 patch 的数据；其余条目保留设备上做过的改动，这一点和 `setDocument` 不同。patch 引用了页面没有的 `id`，或插入页面已有的 `id` 时，跳过那个条目、section 或操作，其余照常应用。库本身不发请求：patch 来自你自己的请求，或来自异步动作里收到的响应，用 `context.page?.apply(patch)` 应用。0.4.0 之前的版本不能应用 patch。

### 加载更多

section 的条目比文档里带的多时，用 `more` 表示，值是后端发送后续条目需要的任何东西，比如游标。库不读它，原样交回：

```json
{ "id": "feed", "more": { "cursor": "c2" }, "items": [ … ] }
```

用户滚到离这种 section 末尾不到五个条目时，页面调用 `onLoadMore`，传入 section 的 `id` 和它的 `more`。加载后续条目，用 patch 追加，同时带上再往后的 `more`；到底了就不写 `more`：

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

在此之前，list 或 grid 的 section 在条目下方显示转圈，页面也不再为这个 section 发起加载。调用 `showLoadMoreFailure(in:)` 后改为显示重试按钮，滚回 section 末尾也会重试。carousel 两者都不显示，滚到接近末尾时发起加载。追加、替换或插入这个 section 的 patch，以及 `setDocument`，结束加载。

转圈和重试按钮（VoiceOver 标签是英文）是默认视图。要显示你自己的视图，比如本地化的文字，把 `makeLoadMoreView` 设为创建一个遵循 `LoadMoreView` 的 `UIView`：页面调用它的 `showLoading()`，以及 `showFailure(retry:)` 并传入一个闭包，供你的按钮调用。它用 Auto Layout 决定自己的大小，页面会把它复用到其他 section。

```swift
controller.makeLoadMoreView = { MyLoadMoreView() }
```

0.5.0 之前的版本忽略 `more`，跳过 `appendItems`。

### 加载中、失败与刷新

不带文档创建的页面显示 `loadingView`，直到 `setDocument`。`showLoading()` 再次用它代替 section 显示；`showFailure(retry:)` 显示 `failureView`，其中的按钮调用 `retry()`：它重新显示 `loadingView` 并调用你的闭包。`setDocument` 和 `apply` 重新显示 section。页面没有条目、也没有带 `more` 的 section 时，显示 `emptyView`。

设置 `onRefresh` 会加上下拉刷新控件。用户下拉时页面调用它，并传入一个闭包，做完后调用：

```swift
let controller = DocumentViewController(actions: actions)   // 显示 loadingView
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

这些视图显示在 section 后面、铺满 collection view，所以空页面或失败的页面也能下拉。默认的视图是转圈和英文提示；把 `loadingView`、`failureView`、`emptyView` 换成你自己的，例如页面的骨架屏或本地化的文字，你的失败视图要调用 `retry()`。下拉刷新失败时不需要 `showFailure`：调用 `done`，页面保留当前显示的内容。

### 曝光

条目可以带 `tracking`，值是你的埋点统计需要的任何东西，比如广告 id；库不读它，原样交给你：

```json
{ "id": "p1", "template": "product", "data": { … }, "tracking": { "slot": 3, "campaign": "fall" } }
```

```swift
controller.onImpression = { item in
    analytics.impression(item.tracking)
}
```

用户看到一个带 `tracking` 的条目时，页面调用一次 `onImpression`：页面在 window 里、且所在 scene 不在后台时，条目至少一半在屏幕上、连续半秒；进入后台会让计时重新开始。要换口径，设置 `impressionFraction` 和 `impressionDuration`。同一份文档里每个条目只报一次；`setDocument` 之后重新计，替换条目的 patch 不会让它再报一次。动作也能在 `context.item` 里读到 `tracking`，可以用你自己的动作统计点击。0.6.0 之前的版本忽略 `tracking`。

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

`BuildContext` 把每个属性读成 publisher，节点没设该属性时返回 nil。常量发出一次；引用随条目数据的每个值发出。`number`、`length`、`integer`、`bool`、`string`、`url`、`color`、`font` 和 `insets` 读取上文的各种类型，`choice` 读取一组字符串之一，`value` 读取其他任何东西。`onValue` 把属性应用到视图，`onEvent` 在视图的某个 publisher 上执行 `context.action(.onTap)`，并把这个视图作为动作的 `sourceView`。要自己执行动作，就用事件的值和视图调用 `context.action` 返回的值：`action(.bool(isOn), source: view)`。spec 写了 `acceptsChildren: true` 时，子节点已替你建好，放在 `context.children`。通用属性会作用在你返回的视图上。

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
- 未知的 `layout` 按列表显示；
- stack 之外的 `repeat`，以及 `repeat` 里的 `set` 与 `toggle`，会被移除；
- patch 里未知的操作、页面没有的 `id`，以及插入处页面已有的 `id`，会被跳过。

每个 `Issue` 都写明位置，例如 `templates.product.children[2]`；patch 的问题写 patch 里的位置，例如 `operations[1].items[0]`。patch 的问题每次应用都会上报。

## 版本

App 停留在构建它时的版本，所以后端写的文档也要让旧版本读得懂。格式第 1 版只做增量，一个版本遇到不认识的内容会上报并跳过。`DocumentVersion.minor` 表示一个版本读得懂哪些新增：

| `minor` | 库版本 | 新增 |
| --- | --- | --- |
| 0 | 0.1.0 | 第 1 版 |
| 1 | 0.2.0 | `vstack` 和 `hstack` 的 `onTap`；`fallback` |
| 2 | 0.3.0 | `overlay`；`grid` 布局；`vstack` 与 `hstack` 的 `highlight` |
| 3 | 0.4.0 | 异步动作的 `onSuccess` 与 `onFailure`；patch |
| 4 | 0.5.0 | section 的 `more`；`appendItems`；颜色 `systemMint`、`systemCyan`、`systemBrown` |
| 5 | 0.6.0 | 条目的 `tracking`；`label` 的 `markdown` 与 `lineHeight`；`repeat` |

请求时带上它，后端就只写 App 读得懂的内容：

```swift
request.setValue("\(DocumentVersion.current).\(DocumentVersion.minor)", forHTTPHeaderField: "Document-Version")
```

节点还可以带一个 `fallback`：App 不认识这个节点的类型时（比如后来的版本才加的组件），改为显示它。`fallback` 自己也可以再带 `fallback`。0.2.0 之前的版本不读 `fallback`。

```json
{ "type": "rating", "value": "$score", "fallback": { "type": "label", "text": "$scoreText" } }
```

## 清单

[`manifest.json`](manifest.json) 列出内置组件及其属性、每个属性的类型和是否接受引用、所有组件共有的属性，以及内置动作、它们的参数和是否异步，patch 的操作、`repeat` 的属性，还有它描述的版本 `v` 与 `minor`。后端的代码生成器可以读取它，检查自己写出的文档。加上你自己的组件和动作：

```swift
let manifest = try Manifest(components: components, actions: actions).encoded()
```

[`protocol/`](protocol/README.md) 用不依赖 iOS 的说法描述格式本身，写给后端和其他平台的渲染器，并附有每个渲染器都要跑的[共用用例](protocol/cases/README.md)。

## 示例 App

`Example/Example.xcodeproj` 是一个以本地 package 方式使用本库的 iOS App。用 Xcode 打开，在 iOS 模拟器上运行 `Example` scheme。每个画面，包括菜单，都是 `Example/Example/Documents` 里的一份 JSON 文档；`navigate` 到 `example://store` 会打开 `store.json`。`Pages.swift` 注册了 router、`openURL`、`addToCart` 与 `showProduct` 两个动作和一个 `rating` 组件。Feed 画面模拟从服务器加载、延迟一秒：显示加载中与失败视图，从 `more` 指名的 patch `feed-2.json`、`feed-3.json` 加载后续页，下拉时重新加载。

<img src="docs/images/example-store.png" width="300" alt="商店画面"> <img src="docs/images/example-settings.png" width="300" alt="设置画面">

## 许可证

MIT。见 [LICENSE](LICENSE)。
