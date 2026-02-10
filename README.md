# rookie_yaml

![pub_version][dart_pub_version]
![pub_downloads][dart_pub_downloads]
![Coverage Status][coverage]
![test_suite](https://img.shields.io/badge/YAML_Test_Suite-89.05%25-green)

> [!NOTE]
> The package is in a "ready-for-use" state. However, until a `v1.0.0` is released, the package API may have (minor) breaking changes in each minor release.

A (rookie) `Dart` [YAML][yaml] 1.2+ parser.

## What's Included

Earlier YAML versions are parsed with YAML 1.2+ grammar rules. The parser will warn you if an explicit YAML version directive which is not supported is present.

- ✅ - Supported. See `Notes` for any additional information.
- ☑️ - Supported. Expand `Notes` for more context.
- ❌ - Not supported. May be implemented if package users express interest/need.

### YAML parser

The package implements the full YAML 1.2+ spec. See the table below for more information and any teething issues the parser has.

> [!TIP]
> The underlying `DocumentParser` is now exported by this package (but with guard-rails). You can build a fine-grained parser on top of the low-level internal parser functions it uses. See the [external resolvers](https://pub.dev/documentation/rookie_yaml/latest/topics/custom_resolvers_intro-topic.html) section and consider extending the `CustomTriggers` class.

<table>
  <thead>
    <tr>
      <th scope="col">Feature</th>
      <th scope="col" style="white-space: nowrap">YAML Features</th>
      <th scope="col"></th>
    </tr>
  </thead>

  <tbody>
    <tr>
      <th scope="row" rowspan="4">Input</th>
      <td>Strings</td>
      <td>✅</td>
    </tr>
    <tr><td>Async Input Stream</td><td>❌</td><tr>
    <tr><td>Sync UTF input</td><td>✅</td><tr>
    <!--  -->
    <tr>
      <th scope="row" rowspan="4">Directives</th>
      <td>YAML Directive</td>
      <td>✅</td>
    </tr>
    <tr><td>Global Tags</td><td>✅</td><tr>
    <tr><td>Reserved Directives</td><td>☑️</td><tr>
    <!--  -->
    <tr>
      <th scope="row" rowspan="4">Tag Handles</th>
      <td>Primary</td>
      <td>✅</td>
    </tr>
    <tr><td>Secondary</td><td>✅</td><tr>
    <tr><td>Named</td><td>✅</td><tr>
    <!--  -->
    <tr>
      <th scope="row" rowspan="4">Tags</th>
      <td>Local tags</td>
      <td>✅</td>
    </tr>
    <tr><td>Verbatim tags</td><td>✅</td><tr>
    <tr><td>Custom tags</td><td>✅</td><tr>
    <!--  -->
    <tr>
      <th scope="row" rowspan="2">Tag Resolution</th>
      <td>YAML Schema</td>
      <td>✅</td>
    </tr>
    <tr><td>External Resolvers</td><td>✅</td><tr>
    <!--  -->
    <tr>
      <th scope="row" rowspan="4">Other node properties</th>
      <td>Anchors</td>
      <td>✅</td>
    </tr>
    <tr><td>Aliases</td><td>✅</td><tr>
    <tr><td>Recursive aliases</td><td>❌</td><tr>
    <!--  -->
    <tr>
      <th scope="row">Nodes</th>
      <td>YAML 1.2.* and below grammar</td>
      <td align="center">☑️</td>
    </tr>
  </tbody>
</table>

<details>
<summary>Notes</summary>

#### Input

1. Uniform API provided via the `YamlSource` extension type.
2. A raw UTF-8, UTF-16 and UTF-32 input stream can be parsed without allocating a string.

#### Directives

1. API for directives-as-code available.
2. Reserved directives can be parsed but cannot be constructed.

#### Tag Handles

- API for tag-handles-as-code available

#### Tags

1. Local-to-global tag handle resolution is required for all tag types (even custom tags).
2. API for tags-as-code available.

#### Tag Resolution

1. Built-in Dart types supported in YAML are inferred out-of-the-box even without tags.
2. External resolvers are restricted to tags. See/extend `CustomTriggers` for all other usecases.

#### Other Node Properties

- You can configure whether list and map aliases should be dereferenced (deep copied) when using the loader for built-in Dart types. Dereferencing isn't the default behaviour.

#### Nodes

- Any valid YAML 1.2 and below syntax can be parsed using YAML 1.2 grammar rules.
- Implicit keys for maps are not restricted to at most 1024 unicode characters (for now).

</details>

### YAML Dumper

The package also exports some APIs that can dump objects back to YAML. The dumped object formatting will always match the current YAML version supported by the parser.

Start [here](https://pub.dev/documentation/rookie_yaml/latest/topics/dump_scalar-topic.html) for more information.

## Documentation & Examples (Still in progress 🏗️)

- The `docs` folder in the repository. Use the [table of contents](https://github.com/kekavc24/rookie_yaml/blob/main/doc/_contents.md) as a guide.
- Visit [pub guide][guide] which provides an automatic guided order for the docs above.
- The `example` folder.

## Contribution

- See [guide][contribute] on how to make contributions to this repository.
- Run [test suite guide][test_suite] and look for bugs to fix.

[yaml]: https://yaml.org/spec/1.2.2/
[coverage]: https://coveralls.io/repos/github/kekavc24/rookie_yaml/badge.svg?branch=main
[dart_pub_version]: https://img.shields.io/pub/v/rookie_yaml.svg
[dart_pub_downloads]: https://img.shields.io/pub/dm/rookie_yaml.svg
[guide]: https://pub.dev/documentation/rookie_yaml/latest/topics/intro-topic.html
[contribute]: https://github.com/kekavc24/rookie_yaml/blob/main/CONTRIBUTING.md
[test_suite]: https://github.com/kekavc24/rookie_yaml/blob/main/test/yaml_test_suite/README.md
