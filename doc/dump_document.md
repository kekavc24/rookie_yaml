You can dump documents by calling `dumpYamlDocuments`. This package exposes `YamlDocument` which can only be constructed when an object is parsed. This is intentional. The root node of the `YamlDocument` will be dumped as a `CompactYamlNode`.

```dart
const source = '''
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
  !!str &anchor value,
  *anchor ,
  !tag [ *anchor , 24 ],
]
''';

print(
  dumpYamlDocuments(
    loadAllDocuments(source: source),
  ),
);
```

```yaml
# Output in yaml
%YAML 1.2
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
 &anchor !!str value,
 *anchor ,
 !tag [
  *anchor ,
  !!int 24
 ]
]
...
```
