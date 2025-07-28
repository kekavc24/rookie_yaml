# Changelog

## 0.0.2

- `refactor`: update API
  - Replaces `Node` with `YamlNode`. This class allow for external implementations to provide a custom `Dart` object to be dumped directly to YAML.
  - Introduces a `ParsedYamlNode`. Inherits from `YamlNode` but its implementation restricted to internal APIs. External objects cannot have resolved
    `tag`-s and/or `anchor`s / `alias`-es
  - Removes `NonSpecificTag` implementation which is now incorporated into the `LocalTag` implementation. A non-specific tag is just a local tag that has not yet been resolved to an existing YAML tag

- `feat(experimental)`: add support for parsing node properties
  - The parser assigns `anchor`, `tag` and `alias` based on context and layout to the nearest `ParsableNode`. Currently, explicit keys in both `flow` and `block` nodes cannot have any node properties before the `?` indicator. Key properties must be declared after the `?` indicator before the actual key is parsed if present. Explicit block entries can have only node properties if all conditions below are met:
    1. At least one node property is declared on its own line before the `?` indicator is seen
    2. The explicit key is the first key of the map. This specific condition allows the node properties to be assigned to the entire block map.

  - This implementation is experimental and parsed properties are assigned on a "best effort" basis. Check docs once available for rationale.
  - Add tests

> [!WARNING]
> This version is (somewhat stable and) usable but misses some core APIs that need to be implemented.

## 0.0.1

- `feat`: add support for parsing `YAML` documents and nodes

> [!WARNING]
> This version doesn't support `YAML` node properties. Anchors (`&`), local tags (`!`) and aliases (`*`) are not parsed.
