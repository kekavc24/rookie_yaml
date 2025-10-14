import 'package:rookie_yaml/src/parser/yaml_parser.dart';

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

  final docs = YamlParser.ofString(yaml).parseDocuments(); // Parse documents

  // [parseNodes] maps the docs parsed as below.
  print(docs.map((d) => d.root));
}
