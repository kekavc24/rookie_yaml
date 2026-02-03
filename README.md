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

- ✅ - Supported
- 🔁 - Supported but read `Notes` column for more context.
- ❌ - Not supported. May be implemented if package users express interest/need.

### YAML parser

The package implements the full YAML 1.2+ spec. See the table below for more information and any teething issues the parser has.

> [!TIP]
> For enthusiasts, the underlying `DocumentParser` is now exported by this package (but with guard-rails). You can build a fine-grained parser on top of the low-level internal parser functions it uses. See the [external resolvers](https://pub.dev/documentation/rookie_yaml/latest/topics/custom_resolvers_intro-topic.html) section and consider extending the `CustomTriggers` class.

<table>
  <thead>
    <tr>
      <th scope="col">Feature</th>
      <th scope="col" style="white-space: nowrap">Secondary Features</th>
      <th scope="col">Notes</th>
    </tr>
  </thead>

  <tbody>
    <tr>
      <th scope="row">Input</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ Strings</li>
          <li>❌ Async Input Stream</li>
          <li>✅ Sync UTF input</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Uniform API provided via the <code>YamlSource</code> extension type.</li>
          <li>A raw UTF-8, UTF-16 and UTF-32 input stream can be parsed without allocating a string.</li>
        </ul>
      </td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Directives</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ YAML Directive</li>
          <li>✅ Global Tags</li>
          <li>🔁 Reserved Directives</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>API for directives-as-code available.</li>
          <li>Reserved directives can be parsed but cannot be constructed.</li>
        </ul>
      </td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Tag Handles</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ Primary</li>
          <li>✅ Secondary</li>
          <li>✅ Named</li>
        </ul>
      </td>
      <td>API for tag-handles-as-code available</td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Tags</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ Local tags</li>
          <li>✅ Verbatim tags</li>
          <li>✅ Custom tags</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Local-to-global tag handle resolution is required for all tag types (even custom tags).</li>
          <li>API for tags-as-code available.</li>
        </ul>
      </td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Tag Resolution</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ YAML Schema</li>
          <li>✅ External Resolvers</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Built-in Dart types supported in YAML are inferred out-of-the-box even without tags.</li>
          <li>External resolvers are restricted to tags. See/extend <code>CustomTriggers</code> for all other usecases.</li>
        </ul>
      </td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Other node properties</th>
      <td>
        <ul style="list-style: none; text-align: left; padding-left: 0">
          <li>✅ Anchors</li>
          <li>✅ Aliases</li>
          <li>❌ Recursive aliases</li>
        </ul>
      </td>
      <td>
        You can configure whether list and map aliases should be dereferenced (deep copied) when using the loader for built-in Dart types. Dereferencing isn't the default behaviour.
      </td>
    </tr>
    <!--  -->
    <tr>
      <th scope="row">Nodes</th>
      <td align="center">🔁</td>
      <td>
        <ul>
          <li>Any valid YAML 1.2 and below syntax can be parsed using YAML 1.2 grammar rules.</li>
          <li>Implicit keys for maps are not restricted to at most 1024 unicode characters (for now).</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

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
[contribute]: CONTRIBUTING.md
[test_suite]: ./test/yaml_test_suite/README.md
