import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/object_dumper.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';
import 'package:test/test.dart';

void main() {
  const funkyMap = {
    'key': 24,
    24: ['rookie', 'yaml'],
    ['is', 'dumper']: {true: 24.0},
    '24\n0': 'value',
  };

  String dumpMap(
    NodeStyle style, {
    bool preferInline = false,
    ScalarStyle scalarStyle = ScalarStyle.doubleQuoted,
  }) {
    return dumpObject(
      funkyMap,
      dumper: ObjectDumper.of(
        scalarStyle: scalarStyle,
        mapStyle: style,
        forceIterablesInline: preferInline,
        forceMapsInline: preferInline,
        forceScalarsInline: preferInline,
      ),
    );
  }

  group('Flow maps', () {
    test('Dumps map with double quoted scalar style', () {
      check(
        dumpMap(NodeStyle.flow),
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
   ]
 : {
    "true": "24.0"
   },
 ? "24

   0"
 : "value"
}''');
    });

    test('Dumps map with single quoted style', () {
      check(
        dumpMap(NodeStyle.flow, scalarStyle: ScalarStyle.singleQuoted),
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
   ]
 : {
    'true': '24.0'
   },
 ? '24

   0'
 : 'value'
}''');
    });

    test('Dumps map with plain style', () {
      check(
        dumpMap(NodeStyle.flow, scalarStyle: ScalarStyle.plain),
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
   ]
 : {
    true: 24.0
   },
 ? 24

   0
 : value
}''');
    });
  });

  group('Inline flow maps', () {
    test('Dumps inline map with plain style', () {
      check(
        dumpMap(
          NodeStyle.flow,
          scalarStyle: ScalarStyle.plain,
          preferInline: true,
        ),
      ).equals(
        r'{key: 24, 24: [rookie, yaml], [is, dumper]: {true: 24.0}, "24\n0": value}',
      );
    });

    test('Dumps inline map with single quoted style', () {
      check(
        dumpMap(
          NodeStyle.flow,
          scalarStyle: ScalarStyle.singleQuoted,
          preferInline: true,
        ),
      ).equals(
        "{'key': '24', '24': ['rookie', 'yaml'], "
        "['is', 'dumper']: {'true': '24.0'}, \"24\\n0\": 'value'}",
      );
    });

    test('Dumps inline map with double quoted style', () {
      check(
        dumpMap(
          NodeStyle.flow,
          scalarStyle: ScalarStyle.doubleQuoted,
          preferInline: true,
        ),
      ).equals(
        '{"key": "24", "24": ["rookie", "yaml"], '
        r'["is", "dumper"]: {"true": "24.0"}, "24\n0": "value"}',
      );
    });
  });

  group('Block maps', () {
    test('Dumps map with literal scalar style', () {
      check(
        dumpMap(NodeStyle.block, scalarStyle: ScalarStyle.literal),
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
        dumpMap(NodeStyle.block, scalarStyle: ScalarStyle.folded),
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
        dumpMap(NodeStyle.block, scalarStyle: ScalarStyle.doubleQuoted),
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
        dumpMap(NodeStyle.block, scalarStyle: ScalarStyle.singleQuoted),
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
        dumpMap(NodeStyle.block, scalarStyle: ScalarStyle.plain),
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

    test('Preserves leading whitespace in nested block scalars', () {
      const scalar = ' sh-Kalar';

      const map = {scalar: scalar, 'nested': scalar};
      final dumped = dumpObject(
        map,
        dumper: ObjectDumper.of(scalarStyle: ScalarStyle.literal),
      );

      check(dumped).equals('''
? |1-
 $scalar
: |1-
 $scalar
? |-
  nested
: |1-
 $scalar
''');

      check(
        DeepCollectionEquality.unordered().equals(
          loadDartObject(YamlSource.string(dumped)),
          map,
        ),
      ).isTrue();
    });
  });
}
