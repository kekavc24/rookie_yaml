Despite the stick `YAML` gets, under all that complexity, is a highly configurable data format that you can bend to your will with the right tools.

Some great features of this parser include:

1. By default, all `YamlSourceNode` are immutable. Ergo, such a node is equal to a corresponding `Dart` object with the same type. Use of `DeepCollectionEquality` **MAY** be required for `Map` or `List`.
2. Preserves the parsed integer radix.
3. Extensive node support and an expressive way to declare directives and tags that aligns with the `YAML` spec.
4. Support for custom tags and their resolvers based on their [tag shorthand suffix][shorthand_url]. There is no limitation (currently) if the `!` has no global tag as its prefix.

> [!NOTE]
> Verbatim tags have no suffix and are usually not resolved.

Based on the [process model][process_model_url], the current parser provides a `YamlDocument` and `YamlSourceNode` that is an almagamation of the first two stages from the left. Future changes may (not) separate these stages based on programmer (actual user) sentiment.

[shorthand_url]: https://yaml.org/spec/1.2.2/#69-node-properties:~:text=tag%20starting%0A%20%20with%20%27!%27.-,Tag%20Shorthands,-A%20tag%20shorthand
[process_model_url]: https://yaml.org/spec/1.2.2/#31-processes
