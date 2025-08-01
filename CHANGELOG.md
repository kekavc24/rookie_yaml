# Changelog

## 0.0.3

- `feat(experimental)`: Richer offset information that uses `SourceLocation` from `package:source_span`
- `breaking(experimental)`: Block styles (`ScalarStyle.literal` & `ScalarStyle.folded`) now have their non-printable characters "broken" up into a printable state
  - Escaped characters are broken up into `\` and whatever ascii character is escaped to elevate it into a control character.
  - Other non-printable characters are encoded as utf characters preceded by `\u`
  - This change is experimental and attempts to be inline with the spec where these non-printable characters cannot be escaped. Ideally, the parser could throw an error and restrict the block styles to only printable characters. [Reference here](https://yaml.org/spec/1.2.2/#chapter-8-block-style-productions:~:text=There%20is%20no%20way%20to%20escape%20characters%20inside%20literal%20scalars.%20This%20restricts%20them%20to%20printable%20characters.%20In%20addition%2C%20there%20is%20no%20way%20to%20break%20a%20long%20literal%20line.)
- `fix`: document markers are now accurately bubbled up (tracked).
- `fix`: characters consumed when checking for the directive end marker `---` are handed off correctly when parsing `ScalarStyle.plain`

> [!WARNING]
> This version is (somewhat stable and) usable but misses some core APIs that need to be implemented.

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
