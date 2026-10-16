# Shared cases

Every renderer of the format runs these cases, so that the same document gives the same result on each platform. The iOS library runs them in `Tests/DeclarativeJSONTests/ProtocolCaseTests.swift`. A change to the protocol comes with cases here, in the same change as the renderers.

Each file holds `{ "cases": [ … ] }`. A case has a `name`, which a failing test shows, and what its kind needs:

| File | Checks |
| --- | --- |
| [`decoding.json`](decoding.json) | whether a document or a patch decodes, and why not |
| [`issues.json`](issues.json) | the issues of showing a document |
| [`actions.json`](actions.json) | the item data and issues after events run their actions |
| [`patches.json`](patches.json) | the sections and issues after patches are applied |

The cases do not check how anything looks: fonts, system controls and colors differ between platforms on purpose.

## Issues

An issue is written as an object with its `kind`, where it is, `at`, and the value its kind carries:

| `kind` | Carries |
| --- | --- |
| `invalidNode`, `invalidChildren`, `unexpectedChildren`, `invalidAction` | — |
| `unknownLayout` | `layout` |
| `unknownType` | `type` |
| `unknownProperty`, `referenceNotAccepted` | `property` |
| `typeMismatch` | `property`, and `expected`, the type as the manifest writes it, without `reference` |
| `unknownAction`, `unhandledAction` | `action` |
| `missingParameter` | `parameter` |
| `duplicateID`, `unknownID` | `id` |
| `unknownTemplate` | `template` |
| `unknownOperation` | `operation` |

```json
{ "kind": "typeMismatch", "property": "numberOfLines", "expected": { "type": "integer" }, "at": "templates.row" }
```

Issues compare as sets: neither the order a renderer reports them in nor how often counts. `issues` is the whole set, so `[]` means none.

## Decoding

```json
{ "name": "…", "input": { "v": 2, "templates": {}, "sections": [] }, "expect": "unsupportedVersion" }
```

- `input` is the document, or the patch when `"patch": true`. `text`, in its place, is raw text, for input that is not JSON.
- `expect` is `decodes`, `unsupportedVersion` for another `v`, or `invalid` for anything else that fails.

## Issues of a document

```json
{ "name": "…", "document": { … }, "issues": [ … ] }
```

The harness shows `document` so that every item and header is built with its own data, as a page tall and wide enough for all of them, and collects what is reported while decoding and showing it.

## Actions

```json
{ "name": "…",
  "handlers": ["navigate"],
  "document": { … },
  "steps": [ { "item": "a", "node": "templates.row.children[1]", "event": "onChange", "value": true } ],
  "expect": { "data": { "a": { … } }, "headers": { "s": { … } }, "handed": [ … ], "issues": [ … ] } }
```

- Each step runs the actions of `event` on the node at `node`, for the item `item`, or for the header of the section `header`, with `value` as the event's value; without `value` the event has none. The node is found in the document as written, by its path: the path names keys of the JSON and indexes of its arrays, so `children[1]` counts every child written, nodes or not, and `overlay.content` reaches the content of an overlay. The node must be in the template of the item or header.
- The harness keeps every item's and header's data, as a page does, and runs the steps in order on it, waiting after each until its asynchronous actions are done.
- Besides the built-in actions, the harness registers two asynchronous actions without parameters: `succeed`, which returns, and `fail`, which throws. They exist only in the cases.
- `handlers` lists the built-in actions the app handles, out of `navigate` and `openURL`. Their handler records `{ "action": name, "url": resolved url }`, and `handed` is the list of what they recorded, in order. Without a handler they report `unhandledAction`.
- `data` and `headers` give the whole data of the items and headers they name; the others are not checked. `issues` is the set reported while the steps ran, including those of reading the actions.

## Patches

```json
{ "name": "…", "document": { … }, "patches": [ { "v": 1, "operations": [ … ] } ],
  "expect": { "sections": [ { "id": "s", "items": ["a", "b"], "more": "s2", "header": "title" } ], "issues": [ … ] } }
```

- The harness shows `document`, then applies each patch in order.
- `sections` is every section of the page afterwards, in order, with the `id`s of its items. `more` and `header`, the name of the header's template, are checked only when written; `null` means none.
- `issues` is the set reported by showing the document and applying the patches.
