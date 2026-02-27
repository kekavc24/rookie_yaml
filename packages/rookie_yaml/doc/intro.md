> [!IMPORTANT]
> `YamlSourceNode` has been migrated to `package:editable_yaml` (unreleased). Please add that package if you use the class. The package also exports `package:rookie_yaml`.

Despite the stick `YAML` gets, under all that complexity, is a highly configurable data format that you can bend to your will with the right tools. Based on the [process model][process_model_url], the parser allows you to access data from the YAML string provided in two ways:

1. As a built-in Dart type at the `Native` stage once parsing is complete.
2. As a delegate using the resolver API which gives you access to the `Representation` stages.

## Built-in Dart types

YAML supports various types out of the box which, by default, are built-in Dart types. These types include:

| YAML                                              | Dart                                                |
|---------------------------------------------------|:---------------------------------------------------:|
| `int` (`hex` and `octal` are considered integers) | `int`                                               |
| `str`                                             | `String`                                            |
| `float`                                           | `double`                                            |
| `null`                                            | `null`                                              |
| `bool`                                            | `bool`                                              |
| `seq`                                             | `List`                                              |
| `omap`, `map`                                     | `Map` (default maps behave like `LinkedHashMap`s)   |

The parser determines these YAML types automatically as required by the spec. All tags, aliases, anchors and styles are stripped and objects returned as any of the Dart types mentioned above. The types are not wrapped in any intermediate class. Any unsupported scalar type will always be returned as a `String`.

## Additional Features

- A spec-compliant expressive API to declare tags and other YAML properties.
- Custom resolvers for custom tag shorthands.
- `CompactNode` interface that allows custom objects to declare custom properties
- Dumper functions that can dump any object to YAML.

[shorthand_url]: https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand
[process_model_url]: https://yaml.org/spec/1.2.2/#31-processes
