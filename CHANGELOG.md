# Changelog

## 0.1.1

- `docs`:
  - Fix typo in package usage docs.
  - Update README.

## 0.1.0

This is the first minor release. It introduces a custom (experimental) error reporting style that focuses on providing a contextual and fairly accurate visual aid on the location of an error within the source string.

- `BREAKING`:
  - Non-specific tags are resolved to `!!map`, `!!seq` or `!!str` based on its kind. No type inference for scalars.
  - `TagShorthand`s that are non-specific ( `!`) cannot be used to declare a custom type `Resolver`.
  - Drop support for `!!uri` tag.

- `feat`:
  - Added a rich error reporting style.
  - `YamlParser` can now parse based on the source string location using the `ofString` and `ofFilePath` constructors.

- `fix`:
  - Document and directive end marker are now checked even in quoted scalar styles, `ScalarStyle.doubleQuoted` and `ScalarStyle.singleQuoted`.
  - Fixes an issue where ` :` and `: ` combination was handled incorrectly when parsing plain scalars.
  - Fixes an issue where block sequence entries not declared using YAML's `compact-inline notation` were parsed incorrectly.
  - Always update the end offset of an explicit block key with no value before exiting.
  - Flow map nodes in flow sequence declared using YAML's `compact-inline notation` cannot have properties.
  - Alias/anchors are no longer restricted to URI characters. Any non-space character can be used.
  - Leading and trailing line breaks are now trimmed in plain scalars.
  - Parser exits gracefully when block scalar styles (`ScalarStyle.literal` and `ScalarStyle.folded`) only declare the header.
  - Parser exits gracefully when a block sequence entry is empty but present.
  - Parser exits gracefully when flow indicators are encountered while parsing tags/anchors/aliases.

## 0.0.6

This is a packed patch release. The main highlight of this release is the support for dumping objects back to YAML. Some of the changes introduced in this release were blocking the implementation of this functionality. A baseline was required. Our dumping strategy needed to be inline with parser functionality.

- `BREAKING`:
  - Block scalar styles, `ScalarStyle.literal` and `ScalarStyle.folded`, are now restricted to the printable character set.
  - Renamed `PreResolver` to `Resolver`.
  - Removed `JsonNodeToYaml` and `DirectToYaml`. Prefer calling the dumping functions added in this release.

- `feat`:
  - `YamlParser` can be configured to ignore duplicate map entries. This is a backwards-compatibility feature for YAML 1.1 and below. Explicitly pass in `throwOnMapDuplicates` as `true`. Duplicate entries are ignored and do not overwrite the existing entry.
  - `YamlParser` now accepts a logger callback. Register this callback if you have custom logging behaviour.
  - Added `dumpScalar`, `dumpSequence` and `dumpMapping` for dumping objects without properties back to YAML.
  - Added `CompactYamlNode` interface. External objects can provide custom properties by implementing this interface.
  - Added `dumpYamlNode`, `dumpCompactNode` and `dumpYamlDocuments` for dumping `CompactYamlNode` subtypes.

- `fix`:
  - Tabs are treated as separation space in `ScalarStyle.plain` when checking if the plain scalar is a key to flow/block map.
  - Escaped slashes `\` are not ignored in `ScalarStyle.doubleQuoted`.
  - Comments in YAML directives are now skipped correctly and do not trigger a premature exit/error.
  - Escaped line breaks in `ScalarStyle.doubleQuoted` are handled correctly.
  - Prevent trailing aliases in flow sequences from being ignored.
  - Prevent key aliases for compact mappings in block sequences from being treated as a normal sequence.

- `docs`:
  - Added guide for contributors who want to run the official YAML test suite to test the parser.
  - Added topic-like docs for pub.
  - Added examples.

## 0.0.5

- `feat`:
  - Add `DynamicMapping` extension type that allow `Dart` values to be used as keys.
  - Allow `block` and `flow` key anchors to be used as aliases before the entire entry is parsed.

- `fix`: Ensure the end offset in an alias used as a sequence entry is updated.

## 0.0.4

The parser is (fairly) stable and in a "black box" state (lexing and parsing are currently merged). You provide a source string and the parser just spits a `YamlDocument` or `YamlSourceNode` or `FormatException`. The parser cannot provide the event tree (or more contextual errors) at this time.

- `refactor`: update API
  - Make `PreScalar` a record. Type inference is now done when instantiating a `Scalar`.
  - Rename `ParsedTag` to `NodeTag`. Some nodes get the default tags from the parser if they don't have any. The naming was confusing.
  - Rename `LocalTag` to `TagShorthand`. This change brings the API closer to the spec. [See here](https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand)
  - Rename `ParsedYamlNode` to `YamlSourceNode`.
  - Rename `NativeResolverTag` to `TypeResolverTag`.
  - Expose the `TagShorthand` suffix present in the `NodeTag`. This allows a `TypeResolverTag` to bind itself to the suffix and resolve all `YamlSourceNode` that have the suffix.
  - Enable parser to associate a suffix with a `TypeResolverTag`
  - Rename `ChunkScanner` to `GraphemeScanner`

- `feat`: Extended support for type inference
  - Add a `ScalarValue` object that infers a `Scalar`'s type only when it is instantiated.
  - Add a `uri` tag for `Dart` and infer `Uri` with schemes from the parsed content.
  - Add `ContentResolver` as a subtype of a `TypeResolverTag` that can infer a type on behalf of the `Scalar`. The type is embedded within the scalar as a `ScalarValue`
  - Add `NodeResolver` as a subtype of a `TypeResolverTag` that can resolve a parsed `YamlSourceNode` via its `asCustomType<T>` method.

- `fix`:
  - Trim only whitespace for plain scalars. Intentionally avoid trimming line breaks.
  - Strip hex before parsing integers when using `int.tryParse` in Dart with a non-null radix
  - Flow nodes with explicit indicators now return indent information to the parent block node after they have been parsed completely. Block map nodes can now eagerly throw an error when parsing implicit keys.
  - Accurately track if a linebreak ended up in a scalar's content to ensure we can infer the type in one pass without scanning the source string once again.
  - Ensure verbatim tags are formatted correctly when instantiating them for `Dart`

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
