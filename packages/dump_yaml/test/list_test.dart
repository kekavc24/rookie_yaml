import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show ScalarStyle, YamlSource, loadObject;
import 'package:test/test.dart';

const _sequence = [
  'value',
  24,
  true,
  ['rookie', 'yaml', 'is', 'dumper'],
  {true: 24.0},
  '24\n0',
];

void main() {
  late final YamlDumper dumper;
  late final StringBuffer buffer;

  setUpAll(() {
    buffer = StringBuffer();
    dumper = YamlDumper.string(config: Config.defaults(), buffer: buffer);
  });

  tearDown(() {
    buffer.clear();
  });

  group('Flow Sequences', () {
    test('Dumps sequence with double quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(
              forceInline: false,
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(styling: TreeConfig.flow(forceInline: false)),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(scalarStyle: ScalarStyle.doubleQuoted),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals(
        r'["value", "24", "true", ["rookie", "yaml", "is", "dumper"],'
        r' {"true": "24.0"}, "24\n0"]',
      );
    });

    test('Dumps inlined sequence with double quoted scalar style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.flow(scalarStyle: ScalarStyle.singleQuoted),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals(
        "['value', '24', 'true', ['rookie', 'yaml', 'is', 'dumper'],"
        " {'true': '24.0'}, \"24\\n0\"]",
      );
    });

    test('Dumps inlined sequence with double quoted scalar style', () {
      dumper
        ..reset(config: Config.yaml(styling: TreeConfig.flow()))
        ..dump(_sequence);

      check(buffer.toString()).equals(
        r'[value, 24, true, [rookie, yaml, is, dumper],'
        r' {true: 24.0}, "24\n0"]',
      );
    });
  });

  group('Block Sequences', () {
    test('Dumps sequence with literal style', () {
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(
              scalarStyle: ScalarStyle.literal,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(
              scalarStyle: ScalarStyle.folded,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(
              scalarStyle: ScalarStyle.doubleQuoted,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(
              scalarStyle: ScalarStyle.singleQuoted,
            ),
          ),
        )
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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
      dumper
        ..reset(config: Config.yaml(styling: TreeConfig.block()))
        ..dump(_sequence);

      check(buffer.toString()).equals('''
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

    test('Preserves leading whitespace correctly in nested block scalars', () {
      const scalar = ' sh-Kalar';
      const iterable = [
        scalar,
        [
          scalar,
          [scalar],
        ],
      ];

      dumper
        ..reset(
          config: Config.yaml(
            styling: TreeConfig.block(
              scalarStyle: ScalarStyle.literal,
            ),
          ),
        )
        ..dump(iterable);

      final dumped = buffer.toString();

      check(dumped).equals('''
- |1-
 $scalar
- - |1-
   $scalar
  - - |1-
     $scalar
''');

      check(
        loadObject(YamlSource.string(dumped)),
      ).isA<Iterable>().deepEquals(iterable);
    });
  });
}
