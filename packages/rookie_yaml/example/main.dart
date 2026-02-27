import 'package:rookie_yaml/rookie_yaml.dart';

void main(List<String> args) {
  const yaml = '''
plain
---
"double quoted"
---
'single quoted'
---
> # Comment
  folded
---
| # Comment
  literal
---
flow: {
  flow: map
  flow: [sequence]
 }
block:
  block: map
  block:
    - sequence
''';

  final docs = loadAllObjects(YamlSource.string(yaml)); // Parse documents

  print(docs);
}
