Tags are also node properties declared in tandem with an `anchor` but never with an `alias`. They form the backbone of the custom resolvers this package allows. Do not skip this section (compacted version of the spec). You can use this as a reference to read the spec (Create an issue if there is an error).

Every node tag begins with the `!` indicator. This signifies the start of a node tag's `tag handle`. There are 3 types of tag handles in `YAML`.

The package also has an expressive way to write tags in `Dart` (in line with the spec).

## Primary Tag Handle `!`

Has a single `!`. You can use this to declare your own tags without declaring a global tag to resolve them.

## Secondary Tag Handle `!!`

Declared as `!!`. Reserved to tags that instruct the parser on how these node's can be represented based on the `YAML` spec. To that effect, tags with this handle are restricted to those the spec recognizes and are always resolved to the official `YAML` global tag prefix, `tag:yaml.org,2002:`. This handle can be overriden by a custom global tag prefix. See the supported tags section.

## Named Tag Handle

Starts with a `!` + a custom name + `!` closing indicator. This handle must have a corresponding global tag (more on this later).

```yaml
%TAG !example! !named-must-have-global
---
[
  !my-tag scalar, # Custom primary tag

  !!int 24, # Secondary tag supported by yaml

  # Named tag resolved to "!named-must-have-global-tag"
  !example!-tag just-a-value,
]
```
