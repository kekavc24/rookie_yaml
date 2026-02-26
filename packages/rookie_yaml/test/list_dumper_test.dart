import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/object_dumper.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';
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
    return dumpObject(
      sequence,
      dumper: ObjectDumper.of(
        scalarStyle: scalarStyle,
        iterableStyle: style,
        forceIterablesInline: preferInline,
        forceMapsInline: preferInline,
        forceScalarsInline: preferInline,
      ),
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

    test('Preserves leading whitespace correctly in nested block scalars', () {
      const scalar = ' sh-Kalar';
      const iterable = [
        scalar,
        [
          scalar,
          [scalar],
        ],
      ];

      final dumped = dumpObject(
        iterable,
        dumper: ObjectDumper.of(scalarStyle: ScalarStyle.literal),
      );

      check(dumped).equals('''
- |1-
 $scalar
- - |1-
   $scalar
  - - |1-
     $scalar
''');

      check(
        loadDartObject(YamlSource.string(dumped)),
      ).isA<Iterable>().deepEquals(iterable);
    });
  });
}
