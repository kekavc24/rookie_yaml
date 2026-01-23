In YAML, you can declare nodes with(out) their properties. If you need to inject properties or even comments, you can wrap the object with a `DumpableNode` type and add them.

## Dumpable Types.

You must call the `dumpableType` exported by the package.

### Scalars

```dart
dumpObject(
  dumpableType(24)
    ..anchor = 'scalar'
    ..withNodeTag(localTag: TagShorthand.primary('tag')),
  dumper: ObjectDumper.compact(),
);
```

```yaml
&scalar !tag 24
```

### Sequences

- Block sequences.

```dart
dumpObject(
  dumpableType([12, 12, 19, 63, 24])
    ..anchor = 'sequence'
    ..withNodeTag(localTag: sequenceTag),
  dumper: ObjectDumper.compact(),
);
```

```yaml
&sequence !!seq
- 12
- 12
- 19
- 63
- 24
```

### Maps

- Flow maps

```dart
final flowSequence = dumpableType(['in', '24', 'hours'])
  ..withVerbatimTag(
    VerbatimTag.fromTagShorthand(
      TagShorthand.primary('sequence'),
    ),
  );

print(
  dumpObject(
    dumpableType({'gone': flowSequence})
      ..anchor = 'map'
      ..withNodeTag(localTag: mappingTag),
    dumper: ObjectDumper.of(
      mapStyle: NodeStyle.flow,
      iterableStyle: NodeStyle.flow,
      forceIterablesInline: true,
      forceMapsInline: true,
    ),
  ),
);
```

```yaml
# Both map and sequence inlined.
&map !!map {gone: !<!sequence> [in, 24, hours]}
```

## Aliases

Aliases in YAML act like references to objects. You can reference an object using its alias using the `Alias` extension type or a `DumpableAlias`.

> [!CAUTION]
> Recursive aliases are not supported.

- You can force a compact view of your aliases by passing in `false` for `unpackAliases`.

```dart
final verboseList = dumpableType([
  12,

  dumpableType(24)
    ..anchor = 'int'
    ..withNodeTag(localTag: integerTag),

  Alias('int'),
]);

print(
  dumpObject(
    [
      // Override its node style.
      verboseList
        ..anchor = 'list'
        ..nodeStyle = NodeStyle.flow,

      Alias('list'),
    ],
    dumper: ObjectDumper.of(
      iterableStyle: NodeStyle.block,
      forceIterablesInline: true,
      unpackAliases: false,
    ),
  ),
);
```

```yaml
# Output.
- &list [12, &int !!int 24, *int]
- *list
```

- If you pass in `true`, the dumper will instead dump the object it compacted "as-is". Using the example above, the output will be:

```yaml
# The dumper dumps the entire object again.
- &list [12, &int !!int 24, &int !!int 24]
- &list [12, &int !!int 24, &int !!int 24]
```

## Comments

YAML allows comments but are not considered part of the node's content. YAML even goes further and indicates that the comment should not be associated with a node. See [here](https://yaml.org/spec/1.2.2/#3233-comments).

To the human eye, however, comments can provide context.

> [!IMPORTANT]
> 1. Comments for collection entries are ignored when flow collections are forced inline.
> 2. Comments are always dumped for top-level nodes.

### Inline comments

Inline comments can only be applied to flow nodes and are always dumped as trailing comments.

```dart
final collection = [
  10,
  dumpableType(24)..comments.addAll(['hello', 'scalar']),
  dumpableType({'key': 'value'})..comments.addAll(['flow', 'map']),
  30,
];

print(
  dumpObject(
    collection,
    dumper: ObjectDumper.of(
      commentStyle: CommentStyle.inline,
      iterableStyle: NodeStyle.flow,
      forceMapsInline: true,
    ),
  ),
);
```

```yaml
[
 10,
 24, # hello
     # scalar
 {key: value}, # flow
               # map
 30
]
```

### Block comments

Comments are always dumped as block comments for any block node. This comment style is also used for comments that cannot be dumped inline.

- Comments are dumped before the node but on the same indent level.

```dart
  final collection = dumpableType([
    10,
    20,
    30,
  ])..comments.addAll(['hello', 'block']);

  print(
    dumpObject(
      collection,
      dumper: ObjectDumper.compact(),
    ),
  );
```

```yaml
# hello
# block
- 10
- 20
- 30
```

- Comments are dumped in a way that signifies ownership moreso for block nodes that support YAML's compact inline notation.

```dart
// Dump customized map
final collection = {
  'key': dumpableType([
    10,
    dumpableType(24)..comments.addAll(['possessive', 'scalar']),

    dumpableType({'key': 'value'})
      ..comments.addAll(['possessive', 'block', 'map']),
    30,
  ])..comments.addAll(['normal', 'block']),

  dumpableType(['block', 'list'])
        ..comments.addAll(['possessive', 'explicit']):
      'value',
};

print(
  dumpObject(
    collection,
    dumper: ObjectDumper.compact(),
  ),
);
```

```yaml
key:
 # normal
 # block
 - 10
 - # possessive
   # scalar
   24
 - # possessive
   # block
   # map
   key: value
   next: value
 - 30
? # possessive
  # explicit
  - block
  - list
: value
```

## Dumpable Types as YAML documents

The dumper can collect global tags declared in any nested type. Any global tags must be included in the dumped YAML. By default, the dumper excludes the YAML global tag, `tag:yaml.org,2002:` if used for secondary tags.

> [!CAUTION]
> Do not exclude global tags unless you are sure the dumped YAML will still be valid.

```dart
print(
  dumpObject(
    dumpableType([10, 24, 30])..withNodeTag(
      localTag: sequenceTag,
      globalTag: GlobalTag.fromTagShorthand(
        TagHandle.secondary(),
        TagShorthand.primary('my-global-tag'),
      ),
    ),
    dumper: ObjectDumper.compact(),
    includeYamlDirective: true,
    includeGlobalTags: true,
    includeDocumendEnd: true,
  ),
);
```

```yaml
%YAML 1.2
%TAG !! !my-global-tag
---
!!seq
- 10
- 24
- 30
...
```
