YAML today is used to declare configs and schemas. Most people think of tags as a way to create types but tags can also be used to extend the capability of a predictable, configurable and/or rarely-changing YAML schema/config file. As you go through the `CustomResolver` section and examples, please keep this at the back of your mind.

## `CustomResolver`s

As earlier stated, the parser uses delegates to pack node information that is meaningful in the current parsing context. Custom resolvers are meant to extend this context and nudge the parser to construct objects that much a specific type. Internally, every delegate has information about the current node's state such as:

1. Starting and ending offset. The end offset is provided when the node cannot be parsed further in the current context.
2. Node properties (`ParsedProperty`) that:
  - Contains its span information within the YAML source provided.
  - The inferred kind if any schema tags were present, that is, map, sequence or scalar.
3. Other contextual parser properties.

A `CustomResolver` allows a custom delegate to be used by the parser to parse objects based on the current node kind. The delegate doesn't control the parser but a tag can hint what the parser should do. There are 3 types of delegates matching each generic node kind you can extend:

| Delegate            | Description                                                                             | `CustomResolver` provider-of-callee   |
|---------------------|-----------------------------------------------------------------------------------------|:-------------------------------------:|
| `BytesToScalar`     | Has access to the underlying code points of a scalar. The parser writes directly to it. | `ObjectFromScalarBytes`                       |
| `SequenceToObject`  | Accepts entries as a sequence/list would.                                               | `ObjectFromIterable`                  |
| `MappingToObject`   | Accepts a key-value pair as a map/mapping would.                                        | `ObjectFromMap`                       |

The parser only calls the `parsed` method of the delegate and doesn't resolve it. Such a resolution is assumed to be within your implementation. Ergo, your delegate will only have access to the `ParsedProperty` which contains the local tag you associated with your resolver in its resolved form.

A helper mixin, `TagInfo` is exported by the package if this tag is important to you. This is inline with YAML's process model at the [representation stage](https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models).

A custom resolver may be bound to a tag and provided via a `CustomTriggers` class to the parser.

## Triggers

If your YAML schema/config file doesn't rely on tags. You can build a custom schema emitter on top of the `CustomTriggers` class by extending it.

> [!TIP]
> A cheeky implementation could make the parser return a byte view of your yaml file with any indentation/styles/tags stripped. :)
>
> (Effectively turning this parser into a glorified end-to-end "byte lexer" for your yaml files)
