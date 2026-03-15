import 'package:checks/checks.dart';
import 'package:dump_yaml/src/configs.dart';
import 'package:dump_yaml/src/dumper/yaml_dumper.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart' show NodeStyle, ScalarStyle;
import 'package:test/test.dart';

const _comments = ['possessive', 'comments'];

void main() {
  late final YamlDumper dumper;

  setUpAll(() {
    dumper = YamlDumper(Config.defaults());
  });

  test('Applies possessive comments in block collections', () {
    dumper
      ..reset(config: Config.defaults())
      ..dump(
        ScalarStyle.values
            .map(
              (s) => ScalarView(24)
                ..scalarStyle = s
                ..comments.addAll(_comments),
            )
            .cast<DumpableView>()
            .followedBy([
              YamlIterable('block sequence'.split(' '))
                ..comments.addAll(_comments),
              YamlIterable([])
                ..nodeStyle = NodeStyle.flow
                ..comments.addAll(_comments),
              YamlMapping({'block': 'map'})..comments.addAll(_comments),
              YamlMapping({})
                ..nodeStyle = NodeStyle.flow
                ..comments.addAll(_comments),
            ]),
      );

    check(dumper.dumped()).equals('''
- # possessive
  # comments
  |-
  24
- # possessive
  # comments
  >-
  24
- # possessive
  # comments
  24
- # possessive
  # comments
  '24'
- # possessive
  # comments
  "24"
- # possessive
  # comments
  - block
  - sequence
- # possessive
  # comments
  []
- # possessive
  # comments
  block: map
- # possessive
  # comments
  {}
''');
  });

  test('Keys are made explicit if comments are declared possessive', () {
    dumper.reset();

    final key = ScalarView(24)..comments.addAll(_comments);
    final map = {key: 'value'};

    dumper.dump([map, YamlMapping(map)..nodeStyle = NodeStyle.flow]);

    check(dumper.dumped()).equals('''
- ? # possessive
    # comments
    24
  : value
- {
    ? # possessive
      # comments
      24
    : value
  }
''');
  });

  test('Possessive comments degenerate to block comments', () {
    dumper.reset();

    final scalar = ScalarView(24)..comments.addAll(_comments);

    dumper.dump(
      [
        {'block map': scalar},

        YamlIterable([
            scalar,
            {'key': scalar},
          ])
          ..comments.addAll(_comments)
          ..nodeStyle = NodeStyle.flow,
      ],
    );

    check(dumper.dumped()).equals('''
- block map:
    # possessive
    # comments
    24
- # possessive
  # comments
  [
    # possessive
    # comments
    24,
    {
      key:
        # possessive
        # comments
        24
    }
  ]
''');
  });
}
