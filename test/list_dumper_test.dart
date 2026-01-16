import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/object_dumper.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

void main() {
  const sequence = [
    'value',
    24,
    true,
    ['rookie', 'yaml', 'is', 'dumper'],
    {true: 24.0},
    '24\n0',
  ];

  String dumpSequence(
    NodeStyle style, {
    bool preferInline = false,
    ScalarStyle scalarStyle = ScalarStyle.doubleQuoted,
  }) {
    return ObjectDumper.of(
      scalarStyle: scalarStyle,
      iterableStyle: style,
      flowIterableInline: preferInline,
      flowMapInline: preferInline,
      forceScalarsInline: preferInline,
    ).dump(
      sequence,
      includeYamlDirective: false,
      includeDocumendEnd: false,
    );
  }

  group('Flow Sequences', () {
    test('Dumps sequence with double quoted scalar style', () {
      check(dumpSequence(NodeStyle.flow)).equals('''
[
 "value",
 "24",
 "true",
 [
  "rookie",
  "yaml",
  "is",
  "dumper"
 ],
 {
  "true": "24.0"
 },
 "24

 0"
]''');
    });

    test('Dumps sequence with single quoted scalar style', () {
      check(
        dumpSequence(NodeStyle.flow, scalarStyle: ScalarStyle.singleQuoted),
      ).equals('''
[
 'value',
 '24',
 'true',
 [
  'rookie',
  'yaml',
  'is',
  'dumper'
 ],
 {
  'true': '24.0'
 },
 '24

 0'
]''');
    });

    test('Dumps sequence with plain scalar style', () {
      check(
        dumpSequence(NodeStyle.flow, scalarStyle: ScalarStyle.plain),
      ).equals('''
[
 value,
 24,
 true,
 [
  rookie,
  yaml,
  is,
  dumper
 ],
 {
  true: 24.0
 },
 24

 0
]''');
    });
  });

  group('Inlined Flow Sequences', () {
    test('Dumps inlined sequence with double quoted scalar style', () {
      check(dumpSequence(NodeStyle.flow, preferInline: true)).equals(
        r'["value", "24", "true", ["rookie", "yaml", "is", "dumper"], {"true": "24.0"}, "24\n0"]',
      );
    });

    test('Dumps inlined sequence with double quoted scalar style', () {
      check(
        dumpSequence(
          NodeStyle.flow,
          scalarStyle: ScalarStyle.singleQuoted,
          preferInline: true,
        ),
      ).equals(
        "['value', '24', 'true', ['rookie', 'yaml', 'is', 'dumper'], {'true': '24.0'}, \"24\\n0\"]",
      );
    });

    test('Dumps inlined sequence with double quoted scalar style', () {
      check(
        dumpSequence(
          NodeStyle.flow,
          scalarStyle: ScalarStyle.plain,
          preferInline: true,
        ),
      ).equals(
        r'[value, 24, true, [rookie, yaml, is, dumper], {true: 24.0}, "24\n0"]',
      );
    });
  });

  group('Block Sequences', () {
    test('Dumps sequence with literal style', () {
      check(
        dumpSequence(NodeStyle.block, scalarStyle: ScalarStyle.literal),
      ).equals('''
- |-
 value
- |-
 24
- |-
 true
- - |-
   rookie
  - |-
   yaml
  - |-
   is
  - |-
   dumper
- ? |-
    true
  : |-
    24.0
- |-
 24
 0
''');
    });

    test('Dumps sequence with folded style', () {
      check(
        dumpSequence(NodeStyle.block, scalarStyle: ScalarStyle.folded),
      ).equals('''
- >-
 value
- >-
 24
- >-
 true
- - >-
   rookie
  - >-
   yaml
  - >-
   is
  - >-
   dumper
- ? >-
    true
  : >-
    24.0
- >-
 24

 0
''');
    });

    test('Dumps sequence with double quoted style', () {
      check(
        dumpSequence(NodeStyle.block, scalarStyle: ScalarStyle.doubleQuoted),
      ).equals('''
- "value"
- "24"
- "true"
- - "rookie"
  - "yaml"
  - "is"
  - "dumper"
- "true": "24.0"
- "24\n\n 0"
''');
    });

    test('Dumps sequence with single quoted style', () {
      check(
        dumpSequence(NodeStyle.block, scalarStyle: ScalarStyle.singleQuoted),
      ).equals('''
- 'value'
- '24'
- 'true'
- - 'rookie'
  - 'yaml'
  - 'is'
  - 'dumper'
- 'true': '24.0'
- '24\n\n 0'
''');
    });

    test('Dumps sequence with plain style', () {
      check(
        dumpSequence(NodeStyle.block, scalarStyle: ScalarStyle.plain),
      ).equals('''
- value
- 24
- true
- - rookie
  - yaml
  - is
  - dumper
- true: 24.0
- 24\n\n 0
''');
    });
  });
}
