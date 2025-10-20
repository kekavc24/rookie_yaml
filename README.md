# rookie_yaml

![pub_version][dart_pub_version]
![pub_downloads][dart_pub_downloads]
![Coverage Status][coverage]
![test_suite](https://img.shields.io/badge/YAML_Test_Suite-76.0%25-green)

> [!WARNING]
> The parser is still in active development and has missing features/intermediate functionalities. Until a stable `1.0.0` is released, package API may have breaking changes in each minor/patch version.

A (rookie) `Dart` [YAML][yaml] 1.2+ parser.

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

## Documentation & Examples (Still in progress 🏗️)

- The `docs` folder in the repository.
- Visit [pub guide][guide] which provides an automatic guided order for the docs above.
- The `example` folder.

## Contribution

See [guide][contribute] on how to make contributions to this repository.

[yaml]: https://yaml.org/spec/1.2.2/
[coverage]: https://coveralls.io/repos/github/kekavc24/rookie_yaml/badge.svg?branch=main
[dart_pub_version]: https://img.shields.io/pub/v/rookie_yaml.svg
[dart_pub_downloads]: https://img.shields.io/pub/dm/rookie_yaml.svg
[guide]: https://pub.dev/documentation/rookie_yaml/latest/
[contribute]: CONTRIBUTING.md
