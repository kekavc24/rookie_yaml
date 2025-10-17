# rookie_yaml

![pub_version][dart_pub_version]
![pub_downloads][dart_pub_downloads]
![Coverage Status][coverage]
![test_suite](https://img.shields.io/badge/YAML_Test_Suite-75.0%25-green)

> [!WARNING]
> The parser is still in active development and has missing features/intermediate functionalities. Until a stable `1.0.0` is released, package API may have breaking changes on each version.

A (rookie) `Dart` YAML 1.2+ parser.

## What's Included

- A fail-fast YAML parser.
- Opinionated YAML dumper functions that prioritize compatibility and portability.

## Supported Schema Tags

The secondary tag handle `!!` is limited to tags below which all resolve to the YAML global tag prefix, `tag:yaml.org,2002`.

- `YAML` schema tags
  - `!!map` - `Map`
  - `!!seq` - `List`
  - `!!str` - `String`

- `JSON` schema tags
  - `!!null` - `null`
  - `!!bool` - Boolean.
  - `!!int` - Integer. `hex`, `octal` and `base 10` should use this.
  - `!!float` - double.

> [!WARNING]
> The Dart-specific secondary tags may be moved to a custom global tag prefix.

## Documentation & Examples

Visit the [pub guide][guide] or examples folder.

[coverage]: https://coveralls.io/repos/github/kekavc24/rookie_yaml/badge.svg?branch=main
[dart_pub_version]: https://img.shields.io/pub/v/rookie_yaml.svg
[dart_pub_downloads]: https://img.shields.io/pub/dm/rookie_yaml.svg
[guide]: https://pub.dev/documentation/rookie_yaml/latest/
