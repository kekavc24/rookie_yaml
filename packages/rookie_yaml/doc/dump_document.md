Any `YamlSourceNode` subtype can be reproduced with the right configuration when calling `dumpObject`.

```dart
const source = '''
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
  !!str &anchor value,
  *anchor,
  !tag [ *anchor, 24 ],
]
''';

print(
  dumpObject(
    loadYamlNode(YamlSource.string(source)),
    dumper: ObjectDumper.of(iterableStyle: NodeStyle.flow),
  ),
);
```

```yaml
# Output in yaml
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
 &anchor !!str value,
 *anchor ,
 !tag [
  *anchor,
  !!int 24
 ]
]
...
```

## Documents

If your `YamlDocument` has some global tags that are declared but not used by any node, you can provide these directives to `dumpObject`.

```dart
const source = '''
%TAG !! !unused
%RESERVED has no meaning
---
!tag &map { key: value }
''';

final doc = loadAllDocuments(YamlSource.string(source)).first;

print(
  dumpObject(
    dumpableType(document.root)
      ..comments.add(
        'A YamlSourceNode contains all tags'
        ' (including parser-resolved tags).',
      ),
    dumper: ObjectDumper.of(
      mapStyle: NodeStyle.flow,
      forceMapsInline: true,
    ),
    directives: document.otherDirectives.cast<Directive>().followedBy(
      document.tagDirectives,
    ),
  ),
);
```

```yaml
%RESERVED has no meaning
%TAG !! !unused
---
# A YamlSourceNode contains all tags (including parser-resolved tags).
&map !tag {!!str key: !!str value}
```
