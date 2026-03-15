import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:rookie_yaml/rookie_yaml.dart' show ScalarStyle, YamlSource, loadObject;
import 'package:test/test.dart';

const _funkyMap = {
  'key': 24,
  24: ['rookie', 'yaml'],
  ['is', 'dumper']: {true: 24.0},
  '24\n0': 'value',
};

void main() {
  late final YamlDumper dumper;

  setUpAll(() {
    dumper = YamlDumper(Config.defaults());
  });

  group('Flow maps', () {
    test('Dumps map with double quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(forceInline: false),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.plain,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals(
        r'{key: 24, 24: [rookie, yaml], [is, dumper]: {true: 24.0}, "24\n0": value}',
      );
    });

    test('Dumps inline map with single quoted style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals(
        "{'key': '24', '24': ['rookie', 'yaml'], "
        "['is', 'dumper']: {'true': '24.0'}, \"24\\n0\": 'value'}",
      );
    });

    test('Dumps inline map with double quoted style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: true,
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals(
        '{"key": "24", "24": ["rookie", "yaml"], '
        r'["is", "dumper"]: {"true": "24.0"}, "24\n0": "value"}',
      );
    });
  });

  group('Block maps', () {
    test('Dumps map with literal scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.folded),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.doubleQuoted),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.singleQuoted),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(scalarStyle: ScalarStyle.plain),
          ),
        )
        ..dump(_funkyMap);

      check(dumper.dumped()).equals('''
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

      dumper.reset(
        config: Config.yaml(
          styling: TreeConfig.block(scalarStyle: ScalarStyle.literal),
        ),
      );

      final dumped = (dumper..dump(map)).dumped();

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
          loadObject(YamlSource.simpleString(dumped)),
          map,
        ),
      ).isTrue();
    });
  });
}
