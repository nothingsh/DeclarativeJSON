# The DeclarativeJSON format

This is the protocol between a backend that writes pages as JSON and the libraries that show them in an app. It is written for the people who generate documents and for those who write a renderer. It says what a document means, not how a platform draws it.

- **Renderers.** The iOS library in this repository shows documents with UIKit. An Android renderer with Jetpack Compose and Material 3 is planned; where a platform differs, this document says so.
- **The same on every platform:** how a document is read, references and what happens to wrong values, what actions do, which issues are reported and where, and the structure and spacing of the layout.
- **Not the same:** fonts, the look of system controls, and colors and text styles, which follow each platform's design. A renderer is not expected to match another pixel for pixel.
- **The contract** is this document, the [manifest](#the-manifest), which lists every component, property and action a renderer accepts, and the [shared cases](cases/README.md), which every renderer runs.

## Contents

- [Documents](#documents)
- [Nodes](#nodes)
- [References](#references)
- [Values](#values)
- [Components](#components)
- [Common properties](#common-properties)
- [Layout](#layout)
- [Events and actions](#events-and-actions)
- [The page](#the-page)
- [Patches](#patches)
- [Problems](#problems)
- [Versions](#versions)
- [The manifest](#the-manifest)

## Documents

A document is a JSON object with three keys:

```json
{
  "v": 1,
  "templates": { "row": { "type": "label", "text": "$title", "padding": 12 } },
  "sections": [
    { "id": "today", "layout": "list",
      "header": { "template": "title", "data": { "text": "Today" } },
      "items": [ { "id": "p1", "template": "row", "data": { "title": "Keyboard" } } ],
      "more": { "cursor": "c2" } }
  ]
}
```

- `v`, an integer, the major version of the format: `1`. A renderer reads `v` first and rejects a document of another version.
- `templates`, an object from a template name to a [node](#nodes), the view tree of a cell or a header.
- `sections`, an array of sections, shown in order.

A **section** has:

- `id`, a string, unique among the sections of the page.
- `layout`: `list`, one column of cells as wide as the page, each as tall as its content; `carousel`, one row that scrolls sideways, each cell as wide and as tall as its content; or `grid`, rows of `columns` cells of equal width. `list` is the default.
- For a `grid`: `columns`, an integer of at least 1, the cells in a row, 2 by default; and `spacing`, a length, the space between cells across and down, 0 by default. A row is as tall as its tallest cell; each cell keeps its own height at the top of the row. The other layouts ignore both.
- `header`, optional: `{ "template": name, "data": object }`, shown above the items, as wide as the page.
- `items`, an array, empty by default.
- `more`, optional: any JSON value, such as a cursor or a URL, that the backend needs to send the items after these. The renderer does not read it; see [loading more](#loading-more). `null` is the same as leaving it out.

An **item** has an `id`, a string unique among the items of the page; `template`, the name of a template; `data`, an object, `{}` by default, whose keys the template's [references](#references) read; and optionally `tracking`, any JSON value, which the renderer hands to the app's analytics without reading it (see [impressions](#impressions)). A header's `data` works the same way.

Keys the format does not have are ignored in a document, a section, an item, a header, a patch and an operation. In a node, every key besides `type`, `children` and `fallback` is a property, and one the component does not take is reported.

### What has to be right

A document fails to decode only when it is not JSON, has another `v`, or gets its outline wrong: `v` is not an integer; `templates` is not an object; `sections` is not an array; a section without a string `id`; an item without a string `id` or `template`; a header without a string `template`; `data` that is not an object; `items` that is not an array. Everything else is shown as well as it can be, and the problem is reported as an [issue](#problems).

## Nodes

A node is an object with a string `type`, its properties, and, for a container, its `children`:

```json
{ "type": "hstack", "spacing": 8, "children": [
  { "type": "image", "image": "star", "width": 16, "height": 16 },
  { "type": "label", "text": "$rating", "fallback": { "type": "label", "text": "–" } }
]}
```

- Every key besides `type`, `children` and `fallback` is a property or an event of the component.
- `children` is an array of nodes. A child that is not a node is left out and reported; `children` that is not an array gives no children.
- `fallback` is a node shown instead when the renderer does not know `type`, such as a component of a later release. A fallback can have its own fallback. It is not used when the type is known, even when a property is not.

### Repeat

A `repeat` is a node that is not a view: a child of a `vstack`, `hstack`, `vscroll` or `hscroll` that puts a copy of its `template` among the container's children, in its place, for each element of `items`. The copies take the container's spacing and alignment, and sit between the children before and after it.

```json
{ "type": "hstack", "spacing": 4, "children": [
  { "type": "label", "text": "Tags:" },
  { "type": "repeat", "items": "$tags",
    "template": { "type": "label", "text": "$value", "padding": 4, "background": "secondarySystemFill", "cornerRadius": 4 } }
]}
```

- `items` is an array, or a reference to one. A value that is not an array is one element; missing or `null` is none. When the data changes, the copies follow the array.
- `template` is a node, written as a constant. In it, a reference reads the element, never the item: a key of an element that is an object, or `value` for an element that is not. A template needs from the item what the backend puts into the elements.
- Actions in the template run for the item, with parameters read from the element. `set` and `toggle` cannot change an element: they are left out and reported as `unsupportedAction`. An app action's change to the data does nothing.
- A `repeat` takes no other property, event or children; they are reported as for any node. A `repeat` anywhere else, including as a template or a fallback, is left out and reported as `unexpectedRepeat`.
- A `repeat` can contain another, which reads an array of the element.
- A renderer of an earlier minor version shows the `repeat`'s `fallback`, as for an unknown type.
- Issues in the template are at its path, such as `templates.row.children[1].template.children[0]`, whichever element they come from.

A **path** names a place in the document, for issues and for the shared cases: keys joined by `.`, and array indexes in brackets, counting every element as written. `templates.row.children[2].fallback` is the fallback of the third child of the template `row`; `sections[1].items[0]` is the first item of the second section.

## References

A property whose value is a string starting with `$` takes the value of that key in the data of the item or header the template shows: `"text": "$title"`.

- The reference is the whole value. There is no concatenation, arithmetic or condition, so the backend puts formatted text, prices and URLs in `data` ready to show.
- `$$` writes a dollar sign: `"$$5 off"` is the text `$5 off`. A lone `$` is the text `$`.
- A string in `data`, and a string inside an array or object value, is never a reference.
- When the key is missing or `null`, the property is treated as not set and the view shows its default. When the value has the wrong type, the same happens and a `typeMismatch` is reported.
- When the data changes, by an [action](#events-and-actions) or a [patch](#patches), every property that refers to a changed key shows the new value.
- Some properties take only a constant (the manifest marks them `"reference": false`); a reference there is ignored and reported as `referenceNotAccepted`. Events take only constants.

There is no `not`. Visibility has two properties, so that two views can share one reference: one says `isHidden`, the other `isVisible`. Send `false` rather than leaving the key out, since a missing value leaves both shown.

## Values

The manifest names the type of every property:

| Type | Written as |
| --- | --- |
| `number` | a finite number |
| `integer` | a number without a fractional part |
| `bool` | `true` or `false` |
| `string` | a string |
| `url` | a string that is a URL |
| `color` | a color, below |
| `font` | a font, below |
| `insets` | insets, below |
| `oneOf` | one of the strings in `values` |
| `object` | an object with the keys in `properties`, each of its type |
| `node` | a node |
| `list` | one value of the type `element`, or an array of them |
| `any` | any JSON value |

A **length**, such as `width` or `spacing`, is a `number` that is not negative. It is a point on iOS and a dp on Android.

A **color** is one of:

- A name in the app's **theme**. The standard theme has the iOS system colors: `label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`, `placeholderText`, `link`, `separator`, `opaqueSeparator`; `systemBackground`, `secondarySystemBackground`, `tertiarySystemBackground`, `systemGroupedBackground`, `secondarySystemGroupedBackground`, `tertiarySystemGroupedBackground`; `systemFill`, `secondarySystemFill`, `tertiarySystemFill`, `quaternarySystemFill`; `systemRed`, `systemOrange`, `systemYellow`, `systemGreen`, `systemMint`, `systemTeal`, `systemCyan`, `systemBlue`, `systemIndigo`, `systemPurple`, `systemPink`, `systemBrown`; `systemGray` to `systemGray6`; `clear`, `black`, `white`. They mean roles, such as "secondary text", and follow light and dark mode. On Android they will map to the app's Material 3 color scheme where Material has the role, and otherwise take the iOS values. An app can replace these and add names of its own, such as `brand.primary`.
- `#RRGGBB` or `#RRGGBBAA`, in hexadecimal.
- `{ "light": color, "dark": color }`, each a name or a hexadecimal color.

A **font** is one of:

- A name in the app's theme. The standard theme has the text styles `largeTitle`, `title1`, `title2`, `title3`, `headline`, `subheadline`, `body`, `callout`, `footnote`, `caption1`, `caption2`. On Android they will map to the app's Material 3 typography. An app can replace these and add names of its own, such as `price`.
- `{ "size": number, "weight": weight }`, with `size` greater than 0, in points or sp, and an optional weight: `ultraLight`, `thin`, `light`, `regular` (the default), `medium`, `semibold`, `bold`, `heavy`, `black`, from 100 to 900.

Both kinds grow and shrink with the user's text size; `size` is the size at the default text size.

An **image name**, the `image` of `image` and `button`, is a name in the app's theme. The standard theme has no images, so the apps on each platform register the same names for their own images. On iOS, a name the theme does not have is looked up in the app's assets, then among the SF Symbols, which documents written for iOS alone may rely on. A name that is not found shows no image and is reported as `unknownImage`.

The manifest lists the theme's names of colors, fonts and images.

**Insets**, for `padding`, are a length for every edge, or an object with any of `top`, `leading`, `bottom`, `trailing`, `horizontal` and `vertical`. An edge wins over its axis, and edges not given are 0. `leading` and `trailing` follow the layout direction.

A value of the wrong type, or out of range, is treated as missing and reported as `typeMismatch`.

## Components

A renderer has these components. An app can register more, which its manifest lists, but not one named `repeat`, which is always a [repeat](#repeat).

| Type | Properties | Events |
| --- | --- | --- |
| `vstack` | `alignment` (`leading`, `center`, `trailing`, `fill`), `spacing`, `highlight` | `onTap` |
| `hstack` | `alignment` (`top`, `center`, `bottom`, `firstTextBaseline`, `lastTextBaseline`, `fill`), `spacing`, `highlight` | `onTap` |
| `vscroll`, `hscroll` | `alignment` and `spacing` as on `vstack` and `hstack`; `showsIndicators`, `bounces` | |
| `spacer` | `minLength`, constant only | |
| `label` | `text`, `markdown`, `font`, `textColor`, `numberOfLines`, `textAlignment` (`natural`, `left`, `center`, `right`, `justified`), `lineHeight`, `adjustsFontSizeToFitWidth` | |
| `image` | `url`, `image`, `contentMode` (`scaleToFill`, `scaleAspectFit`, `scaleAspectFill`, `center`) | |
| `button` | `title`, `titleColor`, `image`, `isEnabled` | `onTap` |
| `textfield` | `text`, `placeholder`, `font`, `textColor`, `textAlignment`, `keyboardType` (`default`, `emailAddress`, `numberPad`, `decimalPad`, `phonePad`, `URL`), `returnKeyType` (`default`, `go`, `next`, `done`, `search`, `send`), `isSecureTextEntry`, `isEnabled` | `onChange`, `onReturn` |
| `switch` | `isOn`, `onTintColor`, `isEnabled` | `onChange` |
| `slider` | `value`, `minimumValue`, `maximumValue`, `minimumTrackTintColor`, `maximumTrackTintColor`, `isEnabled` | `onChange` |
| `progress` | `progress`, from 0 to 1, `progressTintColor`, `trackTintColor` | |
| `activity` | `isAnimating`, `hidesWhenStopped`, `color` | |

- The containers are `vstack`, `hstack`, `vscroll` and `hscroll`. Children of another component are ignored and reported as `unexpectedChildren`.
- `label` shows at most `numberOfLines` lines, 0 for no limit, and ends the last one with an ellipsis when the text does not fit.
- `markdown` on a `label` is shown instead of `text`, which a renderer of an earlier minor version shows instead. It is inline Markdown as CommonMark with the GitHub strikethrough reads it: `*` or `_` for italic, `**` or `__` for bold, `~~` or `~` for strikethrough, `` ` `` for code, which is monospaced and not parsed further, and `\` to escape a marker. HTML entities are decoded. A link or an image shows its text, and cannot be tapped. Everything else stays as written: headings, lists, quotes and other block syntax, line breaks and spaces, HTML tags and bare URLs. The text takes the label's font and color; bold and italic are those of its font, and code a monospaced font of its size. The [shared cases](cases/markdown.json) pin the edge cases.
- `lineHeight` on a `label` is the height of every line, a length, with the text centered in it. It grows with the text size, as fonts do.
- `image` shows the image at `url`, downloaded by the app's image loader, and `image`, an [image name](#values), until the URL's image has loaded.
- `button` is a borderless system button with a title, an image, or both.
- `textfield` has a rounded border; `isSecureTextEntry` hides what is typed.
- The names are those of the iOS properties they set. A renderer on another platform keeps the names and translates them:

| Protocol | Compose |
| --- | --- |
| `vstack` / `hstack` | `Column` / `Row` |
| `repeat` | a `for` loop over the elements in the `Column` or `Row`, keyed by index |
| `vscroll` / `hscroll` | `Column` with `verticalScroll` / `Row` with `horizontalScroll` |
| `spacer`, `minLength` | `Spacer` with `weight`; `widthIn` / `heightIn` for the minimum |
| `label`, `numberOfLines` | `Text`, `maxLines` (0 for no limit), ellipsis on overflow |
| `markdown` | an `AnnotatedString` with `SpanStyle`s (`FontWeight.Bold`, `FontStyle.Italic`, `TextDecoration.LineThrough`, `FontFamily.Monospace`) from an inline parser of the renderer's own |
| `lineHeight` | `TextStyle.lineHeight` in sp, with `LineHeightStyle(Alignment.Center, Trim.None)` |
| `image`, `contentMode` | `Image`; `scaleToFill` / `scaleAspectFit` / `scaleAspectFill` / `center` → `ContentScale.FillBounds` / `Fit` / `Crop` / `None` |
| `button` | `TextButton`, with an `Icon` for `image` |
| `textfield`, `isSecureTextEntry` | `OutlinedTextField`, `PasswordVisualTransformation` |
| `keyboardType` | `KeyboardType.Text` / `Email` / `Number` / `Decimal` / `Phone` / `Uri` |
| `returnKeyType` | the `ImeAction` of the same name; `default` → `ImeAction.Default` |
| `switch`, `slider`, `progress`, `activity` | `Switch`, `Slider`, `LinearProgressIndicator`, an indeterminate `CircularProgressIndicator` |
| `textAlignment` | `natural` / `left` / `center` / `right` / `justified` → `TextAlign.Start` / `Left` / `Center` / `Right` / `Justify` |
| `firstTextBaseline` / `lastTextBaseline` | `alignByBaseline()` / `alignBy(LastBaseline)` |
| font weights | `FontWeight.W100` to `W900` |
| `accessibilityLabel` / `accessibilityIdentifier` | `contentDescription` / `testTag` |

These properties are accepted on Android but have no effect, and report nothing: `showsIndicators` (Compose scroll containers have no indicators), `bounces` (as far as the Compose version allows turning off overscroll), and `adjustsFontSizeToFitWidth` (as far as the Compose version can shrink text to fit).

## Common properties

Every component takes `width`, `height`, `aspectRatio` (width over height, greater than 0), `padding`, `background`, `cornerRadius`, `clipsToBounds`, `border` (`{ "color": color, "width": length }`, both required), `alpha` (0 transparent, 1 opaque), `tintColor`, `overlay`, `isHidden`, `isVisible`, `accessibilityLabel` and `accessibilityIdentifier`.

- **`padding`** is inside the background, the corners, the border, `width` and `height`. The accessibility properties apply to the content.
- **`tintColor`** passes down to the descendants that do not set their own.
- **`isHidden`** and **`isVisible`**: the view is hidden when `isHidden` is `true` or `isVisible` is `false`. A hidden view takes no space in a stack.
- **`overlay`** puts a node in front of the view, or an array of them, later ones further front. It takes only a constant.

  ```json
  { "type": "image", "url": "$cover", "width": 120, "height": 120,
    "overlay": { "alignment": "topTrailing", "offset": { "x": -6, "y": 6 },
                 "content": { "type": "label", "text": "$badge", "font": "caption2", "padding": 4,
                              "background": "systemRed", "textColor": "white", "cornerRadius": 4 } } }
  ```

  Each overlay is `{ "alignment": …, "offset": { "x": …, "y": … }, "content": node }`. `alignment` is `fill`, the default, `center`, `top`, `bottom`, `leading`, `trailing`, `topLeading`, `topTrailing`, `bottomLeading` or `bottomTrailing`. `offset` moves the content, `x` toward the trailing edge, so to the left in a right-to-left layout, and `y` down; `fill` takes no offset, and both coordinates are 0 by default. The view decides the size: the overlay does not make it larger, covers its padding, and is clipped with it by `clipsToBounds`. References in `content` read the same data. Touches pass through an overlay to the view behind it, unless a node in the overlay sets an event. An overlay that is not valid (not an object, a key it does not have, an unknown `alignment`, an `offset` with `fill`, no `content`) is left out and reported as `typeMismatch` of `overlay` at the node; a `content` that is not a node is reported as `invalidNode` at `….overlay[i].content`, or `….overlay.content` for a single overlay.
- **`onTap` on a stack** makes the whole stack a tap target, such as a row. A control inside it, such as a button or a switch, keeps its own touches. While pressed, the stack is highlighted the platform's way (iOS: `systemFill` behind its content; Android: a ripple); `"highlight": false` turns that off, and `highlight` does nothing without `onTap`. With an `accessibilityLabel`, the stack reads as one button to a screen reader.

## Layout

> **Draft.** These rules describe what the iOS renderer does today. They become binding, with relational cases in the shared cases, when the Android renderer is designed; where they leave room, iOS is the reference.

- **Main axis.** Children are laid out in order, `spacing` apart. Extra space goes to the `spacer`s, shared equally, none shorter than its `minLength`. A hidden child takes no space and no spacing.
- **Not enough space.** The `spacer`s shrink to their `minLength` first, then the other children. A child with `width` or `height` keeps it. Text that is squeezed wraps up to `numberOfLines` and then ends with an ellipsis. Which of several children gives way first will be set by a `layoutPriority` property, still to come; documents should not rely on the order until then.
- **Cross axis.** Children are placed by `alignment`; `fill` stretches them to the container's size across. A stack is as large across as its largest child.
- **Size.** A view is as large as its content unless `width`, `height` or `aspectRatio` set it. A cell in a `list` and a header are as wide as the page; a cell in a `carousel` is as wide as its content; a cell in a `grid` is as wide as its column. All are as tall as their content.
- **Scrolling containers** (`vscroll`, `hscroll`) scroll their content along their axis.

## Events and actions

`onTap`, `onChange` and `onReturn` take an action, or an array of actions that run in order:

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "track", "event": "like", "liked": "$liked" }
]
```

An action is an object with a string `action`, the name, and its parameters. Actions run in the app; nothing is sent to the backend unless an app action sends it.

- **Parameters** can be references, unless the manifest says otherwise. They are read when the action runs, so an action sees the data as the actions before it left it.
- **The event's value:** `onChange` of a `textfield` carries its text, a string; of a `switch`, its state, a Bool; of a `slider`, its value, a number. `onTap` and `onReturn` carry none.
- **The data an action changes** is that of the item or header whose view sent the event, and the change shows in every view that refers to it.

The built-in actions:

| Action | Parameters | Does |
| --- | --- | --- |
| `navigate` | `url` | Hands the URL to the app, such as to its router. |
| `openURL` | `url` | Hands the URL to the app, to open outside it. |
| `set` | `path`, constant; `value` | Sets the data's key `path` to `value`. A `value` that refers to a missing key removes the key. Without `value`, sets it to the event's value; without either, does nothing and reports `missingParameter` of `value`. |
| `toggle` | `path`, constant | Flips the Bool at `path`; a missing key becomes `true`. A value that is not a Bool stays and is reported as `typeMismatch` of the key, expecting `bool`. |

`navigate` and `openURL` do nothing, and report `unhandledAction`, until the app handles them. `path` names a key of the data, not a nested path. An action without a parameter it needs does nothing and reports `missingParameter`.

An app registers its own actions, with their parameters; the manifest lists them.

### Asynchronous actions

An app action can be asynchronous, such as one that sends a request; the manifest marks it with `"async": true`. It succeeds when it finishes and fails when it reports an error. Only an asynchronous action takes `onSuccess` and `onFailure`, an action or an array of actions that run when it succeeds or fails; on another action they are unknown parameters.

```json
"onTap": [
  { "action": "toggle", "path": "liked" },
  { "action": "like", "id": "$id", "onFailure": { "action": "toggle", "path": "liked" } }
]
```

- The actions after an asynchronous action in the array wait until it, and its `onSuccess` or `onFailure`, are done. They run whether it succeeded or failed; what should happen only on success goes in `onSuccess`.
- The actions that run after a wait read and change the data of the item the event was for, as it is at that time, even when its view shows another item by then. When the page no longer has the item, they do not run.
- When the page goes away, its running actions are cancelled and what would follow them does not run.

### Actions that cannot run

They are reported when the node is built, and the other actions of the event still run:

- a value that is not an action object or an array of them: `invalidAction` at the event's path, or at its element, as in `….onTap[1]`;
- an action name the renderer does not know: `unknownAction`;
- a parameter the action does not take: `unknownProperty`, at the action;
- a reference in a constant-only parameter: `referenceNotAccepted`, and the parameter is left out.

## The page

A renderer shows the sections of a document in a scrolling list.

- **Building.** A cell's views are built from its template, and showing another item only gives them that item's data. An item or a header whose template the document does not have is left out and reported as `unknownTemplate`; an item or a section whose `id` the page already has is left out and reported as `duplicateID`.
- **Data.** The page keeps each item's and header's data. Actions change the page's copy, so a change stays when the cell scrolls away and back, and the cell resizes to its new content.
- **A new document** replaces the page. Sections and items are matched by `id`, and the new document's data replaces the changes made on the device.

### Loading more

When a section has `more` and the user scrolls to within five items of its end, the renderer asks the app for the next items with the section's `id` and its `more`, and asks again only when that is done. The app loads them and applies a patch with [`appendItems`](#patches), whose `more` is that of the items after them; without `more`, there are no more. While the section loads, the renderer shows a spinner below a `list` or a `grid` section; when the app reports that loading failed, a button that tries again. Scrolling back to the end of the section tries again too. A patch that appends to, replaces or inserts the section, or a new document, ends the loading.

### Impressions

The renderer tells the app once for each item with `tracking` that the user has seen, with the item's `id`, section, template and `tracking`: at least half of the item on screen for half a second without a break, while the page is showing and the app is not in the background, which starts the timing again. The app can change both numbers. An item is reported once per document, again after a new document; a patch that replaces an item does not report it again. A carousel counts what shows of it, too. Actions get the item's `tracking` as well, so that an app action can count taps.

### States of the page

A page can show, in place of its sections, a loading view while the app fetches the document and a failure view with a way to try again. A page without items, none of whose sections has `more`, shows an empty view. These views are the app's to style, and are not part of documents.

## Patches

A patch changes part of a page. It is a JSON object with `v`, the same version as documents, optional `templates`, and `operations`, applied in order:

```json
{ "v": 1,
  "templates": { "notice": { "type": "label", "text": "$text", "padding": 12 } },
  "operations": [
    { "op": "replaceItems", "items": [ { "id": "p1", "template": "product", "data": { "price": "89.00" } } ] },
    { "op": "insertItems", "section": "today", "after": "p1", "items": [ { "id": "n1", "template": "notice", "data": { "text": "Back in stock" } } ] },
    { "op": "appendItems", "section": "feed", "items": [ … ], "more": { "cursor": "c3" } },
    { "op": "removeItems", "ids": ["p3"] },
    { "op": "replaceSections", "sections": [ { "id": "ads", "items": [ … ] } ] },
    { "op": "insertSections", "after": "today", "sections": [ … ] },
    { "op": "removeSections", "ids": ["promo"] }
  ] }
```

| `op` | Takes | Does |
| --- | --- | --- |
| `replaceItems` | `items` | Replaces each item of the same `id`, in its place. |
| `insertItems` | `section`, `items`, `after` optional | Inserts the items into `section` after the item `after`, or first without it. |
| `appendItems` | `section`, `items`, `more` optional | Adds the items at the end of `section` and replaces its `more`. |
| `removeItems` | `ids` | Removes the items. |
| `replaceSections` | `sections` | Replaces each section of the same `id`, in its place, with its header, items and `more`. |
| `insertSections` | `sections`, `after` optional | Inserts the sections after the section `after`, or first without it. |
| `removeSections` | `ids` | Removes the sections, with their items. |

- `templates` adds templates to the page; one with the name of a template the page has replaces it, and the cells that use it are built again.
- Replaced and inserted items and sections show the patch's data. Unlike a new document, a patch leaves the other items' data as the device changed it.
- The page animates the whole patch at once.
- What a patch refers to that the page does not have is skipped, where it is at fault: an item or a section with an unknown `id`, or the whole operation when its `section` or `after` is unknown, reported as `unknownID`; an inserted or appended item or section whose `id` the page has, `duplicateID`; an item or header with an unknown template, `unknownTemplate`, and a section whose header is skipped keeps its items. An `op` the renderer does not know is skipped and reported as `unknownOperation`. The paths are those in the patch, as in `operations[1].items[0]`, and a patch's issues are reported each time it is applied.
- A patch fails to decode, like a document, when it gets its outline wrong: `v`, `operations`, the `op` of each operation and the keys it takes.

## Problems

Problems that do not stop the page are **issues**: the part at fault is left out or replaced, the rest is shown, and the issue goes to the app, which can log it or send it to the backend. A renderer reports each distinct issue of a document once; the issues of a patch, each time it is applied.

| Kind | Means | Then |
| --- | --- | --- |
| `invalidNode` | a node that is not an object with a string `type` | left out |
| `invalidChildren` | `children` that is not an array | no children |
| `unknownLayout` | a section `layout` the renderer does not know | laid out as a `list` |
| `unknownType` | a node `type` the renderer does not know | its `fallback`, or else an empty view |
| `unknownProperty` | a property or event the component does not take, or a parameter the action does not take | ignored |
| `referenceNotAccepted` | a reference where only a constant is taken | ignored |
| `unexpectedChildren` | children of a component without any | ignored |
| `typeMismatch` | a value of the wrong type or out of range, written or referenced | treated as missing |
| `invalidAction` | an event value that is not an action or an array of them | left out |
| `unknownAction` | an action the renderer does not know | left out |
| `missingParameter` | an action without a parameter it needs | does nothing |
| `unhandledAction` | a built-in action the app does not handle | does nothing |
| `duplicateID` | a section or item `id` the page already has | left out |
| `unknownTemplate` | an item or header with a template the page does not have | left out |
| `unknownID` | an `id` in a patch that the page does not have | skipped |
| `unknownOperation` | a patch `op` the renderer does not know | skipped |
| `unexpectedRepeat` | a `repeat` that is not a child of a stack | left out |
| `unsupportedAction` | `set` or `toggle` in a `repeat` | left out |
| `unknownImage` | an image name the app does not have | no image |

An issue says where it is with a [path](#nodes): the node, as in `templates.product.children[2]`; the action, as in `templates.product.onTap[1]`; the section or item, as in `sections[0].items[3]`; or the place in a patch. The shared cases write an issue as JSON, such as `{ "kind": "unknownType", "type": "card", "at": "templates.product.children[0]" }`; see [their format](cases/README.md#issues).

## Versions

An app keeps the release of the renderer it was built with for a long time, so a backend writes documents that older renderers read too.

- `v` changes only when a document stops being readable by the renderers of the version before. That has not happened: version 1 grows by additions only.
- Each addition to version 1 raises the **minor version**, which a renderer reports (on iOS, `DocumentVersion.minor`) and the manifest carries as `minor`. The app sends it with its requests, so that the backend writes only what the app reads.
- A renderer that meets an addition it does not know reports it and leaves it out, as for any issue; a `fallback` gives a component of a later version something to show instead.

| `minor` | Adds |
| --- | --- |
| 0 | Version 1 |
| 1 | `onTap` on `vstack` and `hstack`; `fallback` |
| 2 | `overlay`; the `grid` layout; `highlight` |
| 3 | `onSuccess` and `onFailure`; patches |
| 4 | `more`; `appendItems`; the colors `systemMint`, `systemCyan` and `systemBrown` |
| 5 | `tracking`; `markdown` and `lineHeight` on `label`; `repeat` |

## The manifest

A renderer exports a manifest: every component with its properties and events, the properties every component takes, every action with its parameters and whether it is asynchronous, the operations of a patch, the properties of `repeat`, the names of colors, fonts and images in the theme, and `v` and `minor`. Each property has its [type](#values) and whether it takes a reference. The manifest of the iOS library's built-in components and actions is [`manifest.json`](../manifest.json); an app with components, actions or a theme of its own exports its own. A backend reads it to check the documents it writes. When the Android renderer comes, each platform will have its manifest, and the difference between them is what the platforms do not yet share.
