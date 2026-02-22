Despite the stick `YAML` gets, under all that complexity, is a highly configurable data format that you can bend to your will with the right tools. Based on the [process model][process_model_url], the parser allows you to access data from the YAML string provided in two ways:

1. As a built-in Dart type
2. As a `YamlSourceNode`.

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

## YamlSourceNode

It has 3 distinct subtypes that cannot be subclassed:

- `Mapping` - corresponds to a Dart `Map`
- `Sequence` - corresponds to a Dart `List`
- `Scalar` - represents any type that is not a map or list.

> [!TIP]
> A `YamlSourceNode` just wraps a built-in Dart type. Calling its getter `node` provides the underlying built-in Dart type. For collections (`Mapping` and `Sequence`), every element will be a built-in Dart type. This is an `O(1)` operation with no recursive getter calls.
>
> If you need each element to be a `YamlSourceNode`, you must iterate the `children` getter instead.

Alternatively, the parser can also emit a `YamlSourceNode`. :

1. Represents a subtree of the entire YAML tree.
1. Has span information about the node in the source string or byte source.
2. Persists its resolved/default tag assigned to it by the parser.
3. Preserves its own anchor/alias information. Usually, every `AliasNode` holds a reference and anchor name to the actual node it referenced as an anchor. The same node also has the same anchor name. You need not worry about any node mismatch.
4. Preserves the natural formatting of a scalar.

> [!TIP]
> Always select a loader for your YAML string based on the level of detail your require.

## Additional Features

- A spec-compliant expressive API to declare tags and other YAML properties.
- Custom resolvers for custom tag shorthands.
- `CompactNode` interface that allows custom objects to declare custom properties
- Dumper functions that can dump any object to YAML.

[shorthand_url]: https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand
[process_model_url]: https://yaml.org/spec/1.2.2/#31-processes
