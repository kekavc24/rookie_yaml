# dump_yaml

The dumper is spec-compliant and prioritizes clean YAML documents as its default configuration.

It supports all features implemented in `package:rookie_yaml` and most (if not all) YAML parsers. This package also provides the foundation you need to build your own configurable YAML dumper/formatter.

> [!TIP]
> If you're migrating from `package:rookie_yaml` version 0.6.0 and below, see the [migration guide](https://github.com/kekavc24/yaml_dart/blob/main/packages/dump_yaml/migrations/from_rookie_yaml.md).

## Principles

1. **100% spec-compliant** - All supported features are included in the YAML spec and vice versa (all YAML features are supported).
2. **Simplicity** - No YAML features are shoved into your files unless you explicitly use them.
3. **Configurability** - The dumper includes features you can use to accurately control the final output of your YAML files. (See next section).

## What's Included

Dumping YAML is tricky but incredibly satisfying when gotten right. The `YamlDumper` exposed is built for configurability and reusability. The dumper accepts a config with 2 options:

- `styling` - Controls the node styles used when dumping.
- `formatting` - Controls the final YAML output.

### Styling

As stated earlier, no YAML features are shoved into your files unless you use them. For this stage, the dumper exposes additional utility classes.

- `TreeBuilder` - used by the dumper to inspect which YAML features are used and normalizes them before dumping the object to YAML.
- `DumpableView` - a mutable lightweight wrapper class that exposes additional YAML features you may require.

> [!TIP]
> A `DumpableView` can be used to override the style of nested nodes or apply comments. It provides useful setters for such usecases.

### Formatting

Use this option to configure:

1. Starting indent.
2. Indentation step for nested nodes of a collection.
3. Line ending used for your files.

## Usage

- Simple dumper for clean YAML files.

```dart
print(dumpAsYaml(['hello', 'there']));
```

```yaml
- hello
- there
```

- A bit sophisticated. A `DumpableView` provides granular control over the `TreeBuilder` but still relies on the same builder for housekeeping. For example, `ScalarStyle.literal` is not allowed in flow styles in YAML.

```dart
// With Dart's shorthand syntax. Setter mimics the enum.
final configurable = [
  ScalarView('hello YAML, from world')
    ..anchor = 'scalar'
    ..scalarStyle = .literal // Not allowed in YAML flow.
    ..commentStyle = .trailing
    ..comments.addAll(['trailing', 'comments']),

  YamlMapping({'key': 24, 'next': Alias('scalar')})
      ..forceInline = true
      ..commentStyle = .block
      ..comments.addAll(['block', 'comments'])
];

print(
  dumpAsYaml(
    configurable,
    config: Config.yaml(
      includeYamlDirective: true,
      styling: TreeConfig.flow(
        forceInline: false,
        scalarStyle: ScalarStyle.doubleQuoted,
        includeSchemaTag: true,
      ),
      formatting: Formatter.config(rootIndent: 3, indentationStep: 1),
    ),
  ),
);
```

```yaml
%YAML 1.2
---
   !!seq [
    &scalar "hello YAML, from world" # trailing
                                     # comments
    ,
    # block
    # comments
    {!!str "key": !!int "24", !!str "next": *scalar}
   ]
```

## Documentation & Examples (Still in progress 🏗️)

- The `docs` folder in the repository. Use the [table of contents](https://github.com/kekavc24/yaml_dart/blob/main/packages/dump_yaml/doc/_contents.md) as a guide.
- Visit pub [guide](https://pub.dev/documentation/dump_yaml/latest/) which provides an automatic guided order for the docs above.

## Contribution

All contributions are welcome.

- Create an issue if you need help or any features you'd like.
- See [guide](https://github.com/kekavc24/yaml_dart/blob/main/CONTRIBUTING.md) on how to make contributions to this repository.
