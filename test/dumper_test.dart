import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumping.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';

void main() {
  group('Dumps scalar', () {

    group('Dumps map', () {
      final funkyMap = {
        'key': 24,
        24: ['rookie', 'yaml'],
        ['is', 'dumper']: {true: 24.0},
        '24\n0': 'value',
      };

      group('Dumps flow map', () {
        test('Dumps map with default double quoted scalar style', () {
          check(
            dumpMapping(funkyMap, collectionNodeStyle: NodeStyle.flow),
          ).equals('''
{
 "key": "24",
 "24": [
   "rookie",
   "yaml"
  ],
 ? [
  "is",
  "dumper"
 ]: {
   "true": "24.0"
  },
 ? "24

 0": "value"
}''');
        });

        test('Dumps map with single quoted style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.flow,
              keyScalarStyle: ScalarStyle.singleQuoted,
              valueScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
{
 'key': '24',
 '24': [
   'rookie',
   'yaml'
  ],
 ? [
  'is',
  'dumper'
 ]: {
   'true': '24.0'
  },
 ? '24

 0': 'value'
}''');
        });

        test('Dumps map with plain style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.flow,
              keyScalarStyle: ScalarStyle.plain,
              valueScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
{
 key: 24,
 24: [
   rookie,
   yaml
  ],
 ? [
  is,
  dumper
 ]: {
   true: 24.0
  },
 ? 24

 0: value
}''');
        });

        test(
          'Dumps map with block style or json compatible as true defaults to'
          ' double quoted',
          () {
            const output = '''
{
 "key": "24",
 "24": [
   "rookie",
   "yaml"
  ],
 ? [
  "is",
  "dumper"
 ]: {
   "true": "24.0"
  },''';

            const block =
                '''
$output
 ? "24

 0": "value"
}''';

            const json =
                '$output\n'
                r' "24\n0": "value"'
                '\n}';

            check(
              [
                dumpMapping(
                  funkyMap,
                  collectionNodeStyle: NodeStyle.flow,
                  keyScalarStyle: ScalarStyle.literal,
                  valueScalarStyle: ScalarStyle.literal,
                ),
                dumpMapping(
                  funkyMap,
                  collectionNodeStyle: NodeStyle.flow,
                  keyScalarStyle: ScalarStyle.folded,
                  valueScalarStyle: ScalarStyle.folded,
                ),
                dumpMapping(funkyMap, jsonCompatible: true),
              ],
            ).deepEquals([block, block, json]);
          },
        );
      });

      group('Dumps block map', () {
        test('Dumps map with default literal scalar style', () {
          check(
            dumpMapping(funkyMap, collectionNodeStyle: NodeStyle.block),
          ).equals('''
? |-
  key
: |-
  24
? |-
  24
: - |-
    rookie
  - |-
    yaml
? - |-
    is
  - |-
    dumper
: ? |-
    true
  : |-
    24.0
? |-
  24
  0
: |-
  value
''');
        });

        test('Dumps map with folded scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.folded,
              valueScalarStyle: ScalarStyle.folded,
            ),
          ).equals('''
? >-
  key
: >-
  24
? >-
  24
: - >-
    rookie
  - >-
    yaml
? - >-
    is
  - >-
    dumper
: ? >-
    true
  : >-
    24.0
? >-
  24

  0
: >-
  value
''');
        });

        test('Dumps map with double quoted scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.doubleQuoted,
              valueScalarStyle: ScalarStyle.doubleQuoted,
            ),
          ).equals('''
"key": "24"
"24":
  - "rookie"
  - "yaml"
? - "is"
  - "dumper"
: "true": "24.0"
? "24

  0"
: "value"
''');
        });

        test('Dumps map with single quoted scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.singleQuoted,
              valueScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
'key': '24'
'24':
  - 'rookie'
  - 'yaml'
? - 'is'
  - 'dumper'
: 'true': '24.0'
? '24

  0'
: 'value'
''');
        });

        test('Dumps map with plain scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.plain,
              valueScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
key: 24
24:
  - rookie
  - yaml
? - is
  - dumper
: true: 24.0
? 24

  0
: value
''');
        });
      });

      group('Dumps with different scalar styles for key and value', () {
        test('Dumps key as flow and value as block in block map', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
key: |-
  24
24:
  - |-
    rookie
  - |-
    yaml
? - is
  - dumper
: true: |-
    24.0
? 24

  0
: |-
  value
''');
        });

        test(
          'Dumps key as single quoted and values as double quoted in flow map',
          () {
            check(
              dumpMapping(
                funkyMap,
                collectionNodeStyle: NodeStyle.flow,
                keyScalarStyle: ScalarStyle.singleQuoted,
                valueScalarStyle: ScalarStyle.doubleQuoted,
              ),
            ).equals('''
{
 'key': "24",
 '24': [
   "rookie",
   "yaml"
  ],
 ? [
  'is',
  'dumper'
 ]: {
   'true': "24.0"
  },
 ? '24

 0': "value"
}''');
          },
        );
      });
    });

    group('Dumps list', () {
      const sequence = [
        'value',
        24,
        true,
        ['rookie', 'yaml', 'is', 'dumper'],
        {true: 24.0},
        '24\n0',
      ];

      group('Dumps flow list', () {
        test('Dumps sequence with default double quoted scalar style', () {
          check(
            dumpSequence(sequence, collectionNodeStyle: NodeStyle.flow),
          ).equals('''
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
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.flow,
              preferredScalarStyle: ScalarStyle.singleQuoted,
            ),
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
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.flow,
              preferredScalarStyle: ScalarStyle.plain,
            ),
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

        test(
          'Dumps sequence with block style or json compatible as true defaults '
          'to double quoted',
          () {
            const output = '''
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
 },''';

            const block =
                '''
$output
 "24

 0"
]''';

            const json =
                '$output\n'
                r' "24\n0"'
                '\n]';

            check(
              [
                dumpSequence(
                  sequence,
                  collectionNodeStyle: NodeStyle.flow,
                  preferredScalarStyle: ScalarStyle.literal,
                ),
                dumpSequence(
                  sequence,
                  collectionNodeStyle: NodeStyle.flow,
                  preferredScalarStyle: ScalarStyle.folded,
                ),
                dumpSequence(sequence, jsonCompatible: true),
              ],
            ).deepEquals([block, block, json]);
          },
        );
      });

      group('Dumps block list', () {
        test('Dumps sequence with default literal style', () {
          check(
            dumpSequence(sequence, collectionNodeStyle: NodeStyle.block),
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
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.folded,
            ),
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
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.doubleQuoted,
            ),
          ).equals('''
- "value"
- "24"
- "true"
- - "rookie"
  - "yaml"
  - "is"
  - "dumper"
- "true": "24.0"
- "24\n\n  0"
''');
        });

        test('Dumps sequence with single quoted style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
- 'value'
- '24'
- 'true'
- - 'rookie'
  - 'yaml'
  - 'is'
  - 'dumper'
- 'true': '24.0'
- '24\n\n  0'
''');
        });

        test('Dumps sequence with plain style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
- value
- 24
- true
- - rookie
  - yaml
  - is
  - dumper
- true: 24.0
- 24\n\n  0
''');
        });
      });
    });
  });
}
