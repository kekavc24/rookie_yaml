YAML today is used to declare configs and schemas. Most people think of tags as a way to create types but tags can also be used to extend the capability of a predictable, configurable and/or rarely-changing YAML schema/config file.

## `CustomResolver`s

As earlier stated, the parser uses delegates to pack node information that is meaningful in the current parsing context. Custom resolvers are meant to extend this context and nudge the parser to construct objects that much a specific type.

A `CustomResolver` allows a custom delegate to be used by the parser to parse objects based on the current node kind. The delegate doesn't control the parser but a tag can hint what the parser should do. With this resolver:

  1. Step into the `Representation` stage when implementing the delegate itself.
  2. Replay a decomposed view of the `Representation` and `Serialization` stage via a callback once the the object in `Step 1` has been constructed.

There are 3 types of delegates matching each generic node kind you can extend:

| Delegate            | Description                                                                             | `CustomResolver` provider-of-callee   |
|---------------------|-----------------------------------------------------------------------------------------|:-------------------------------------:|
| `BytesToScalar`     | Has access to the underlying code points of a scalar. The parser writes to it.          | `ObjectFromScalarBytes`               |
| `SequenceToObject`  | Accepts entries as a sequence/list would.                                               | `ObjectFromIterable`                  |
| `MappingToObject`   | Accepts a key-value pair as a map/mapping would.                                        | `ObjectFromMap`                       |

The parser only calls the `parsed` method of the delegate and doesn't resolve it. Such a resolution is assumed to be within your implementation. Ergo, your delegate will only have access to the `ParsedProperty` which contains the local tag you associated with your resolver in its resolved form.

A helper mixin, `TagInfo` is exported by the package if this tag is important to you. This is inline with YAML's process model at the [representation stage](https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models).

A custom resolver may be bound to a tag and provided via a `CustomTriggers` class to the parser.

## Triggers

If your YAML schema/config file doesn't rely on tags. You can build a custom schema emitter on top of the `CustomTriggers` class by extending it.

> [!TIP]
> A cheeky implementation could make the parser return a byte view of your yaml file with any indentation/styles/tags stripped. :)
