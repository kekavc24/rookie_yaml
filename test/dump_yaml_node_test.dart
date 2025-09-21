import 'dart:collection';

import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumping.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/yaml_parser.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

final class _TestObject<T> implements CompactYamlNode {
  _TestObject(
    this.wrapped, {
    this.alias,
    this.anchor,
    this.tag,
    NodeStyle? style,
  }) : nodeStyle = style ?? NodeStyle.flow;

  final T wrapped;

  @override
  final String? alias;

  @override
  final String? anchor;

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;
}

String _dumpTestObject(
  _TestObject object, [
  ScalarStyle style = ScalarStyle.plain,
]) => dumpCompactNode(
  object,
  nodeUnpacker: (c) => c.wrapped as Object,
  scalarStyle: style,
);

void main() {
  group('Dumps Dart nodes', () {
    test('Dumps scalars', () {
      // ScalarStyle.plain
      check(dumpYamlNode(DartNode(24))).equals('24');
    });

    test('Dumps iterables', () {
      // All dumped as block sequences with ScalarStyle.plain
      const output = '- 24\n';

      check(dumpYamlNode(DartNode([24]))).equals(output);

      check(dumpYamlNode(DartNode({24}))).equals(output);

      check(dumpYamlNode(DartNode(SplayTreeSet.of([24])))).equals(output);
    });

    test('Dumps maps', () {
      // All dumped as block maps with ScalarStyle.plain
      const output = 'Dart: Map\n';

      const map = {'Dart': 'Map'};

      check(dumpYamlNode(DartNode(map))).equals(output);

      check(dumpYamlNode(DartNode(SplayTreeMap.from(map)))).equals(output);

      check(dumpYamlNode(DartNode(HashMap.from(map)))).equals(output);

      check(dumpYamlNode(DartNode(LinkedHashMap.from(map)))).equals(output);
    });
  });

  group('Dumps Compact subtypes nodes', () {
    test('Dumps a CompactYamlNode with no properties', () {
      check(_dumpTestObject(_TestObject([24]))).equals('''
%YAML 1.2
---
[
 24
]
...''');
    });

    test('Dumps scalar with properties', () {
      check(
        _dumpTestObject(
          _TestObject(
            24,
            anchor: 'test',
            tag: NodeTag(yamlGlobalTag, integerTag),
          ),
        ),
      ).equals('''
%YAML 1.2
---
&test !!int 24
...''');
    });

    test('Defaults list to flow node style when properties are present', () {
      final object = [
        'normal',
        _TestObject(
          [24],
          anchor: 'seq',
          tag: NodeTag(yamlGlobalTag, sequenceTag),
        ),
      ];

      check(
        _dumpTestObject(_TestObject(object, style: NodeStyle.block)),
      ).equals('''
%YAML 1.2
---
- normal
- &seq !!seq [
   24
  ]
...''');
    });

    test('Defaults map to flow node style when properties are present', () {
      final object = {
        'normal': 24,
        'compact': _TestObject(
          {'nested': 'map'},
          anchor: 'map',
          tag: NodeTag(yamlGlobalTag, mappingTag),
        ),
      };

      check(
        _dumpTestObject(_TestObject(object, style: NodeStyle.block)),
      ).equals('''
%YAML 1.2
---
normal: 24
compact: &map !!map {
   nested: map
  }
...''');
    });

    test('Links custom global tags present in properties', () {
      final globalFromTag = GlobalTag.fromTagShorthand(
        TagHandle.primary(),
        TagShorthand.fromTagUri(TagHandle.primary(), 'global-shorthand'),
      );

      final named = TagHandle.named('uri');

      final globalFromUri = GlobalTag.fromTagUri(named, 'uri:as.global');

      final object = [
        _TestObject(
          24,
          tag: NodeTag(
            globalFromTag,
            TagShorthand.fromTagUri(TagHandle.primary(), 'tag'),
          ),
        ),
        _TestObject(
          '24',
          tag: NodeTag(globalFromUri, TagShorthand.fromTagUri(named, 'tag')),
        ),

        // Ignored not saved globally
        _TestObject(
          'value',
          tag: VerbatimTag.fromTagShorthand(
            TagShorthand.fromTagUri(TagHandle.primary(), 'verbatim'),
          ),
        ),
      ];

      check(
        _dumpTestObject(
          _TestObject(object, style: NodeStyle.block),
          ScalarStyle.doubleQuoted,
        ),
      ).equals('''
%YAML 1.2
$globalFromTag
$globalFromUri
---
- !tag "24"
- !uri!tag "24"
- !<!verbatim> "value"
...''');
    });

    test('Links aliases correctly. Unpacks the value if absent', () {
      final object = [
        'clean value',
        _TestObject('target', anchor: 'anchor'),
        _TestObject(null, alias: 'anchor'),
        _TestObject('no anchor', alias: 'naught'),
      ];

      check(
        _dumpTestObject(
          _TestObject(object, style: NodeStyle.block),
          ScalarStyle.doubleQuoted,
        ),
      ).equals('''
%YAML 1.2
---
- "clean value"
- &anchor "target"
- *anchor
- "no anchor"
...''');
    });

    test("Prevents child block style override on parent flow's style", () {
      final object = _TestObject(
        [
          'clean',
          _TestObject(['value'], style: NodeStyle.block),
        ],
        anchor: 'parent',
      );

      check(_dumpTestObject(object)).equals('''
%YAML 1.2
---
&parent [
 clean,
 [
  value
 ]
]
...''');
    });

    test(
      'Throws an assertion error when a tag declared is not a valid YAML tag '
      'if the secondary tag handle is used',
      () {
        const assertion =
            'Only valid YAML tags can have a secondary tag handle';

        final tag = TagShorthand.fromTagUri(TagHandle.secondary(), 'myTag');

        check(
              () => _dumpTestObject(
                _TestObject(
                  24,
                  tag: NodeTag(yamlGlobalTag, tag),
                ),
              ),
            )
            .throws<AssertionError>()
            .has((e) => e.message.toString(), 'Message')
            .equals(assertion);

        check(() => _dumpTestObject(_TestObject(24, tag: NodeTag(tag, null))))
            .throws<AssertionError>()
            .has((e) => e.message.toString(), 'Message')
            .equals(assertion);
      },
    );
  });

  group('Dumps YamlSourceNode as compact nodes', () {
    test('Dumps a YamlSourceNode back to a reproducible state', () {
      const source = '''
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
  !!str &anchor value,
  *anchor ,
  !tag [ *anchor , 24 ],
]
''';

      check(
        dumpCompactNode(
          YamlParser(source).parseNodes().first,
          nodeUnpacker: null,
        ),
      ).equals('''
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
...''');
    });

    test('Dumps YamlSourceNode parsed within document', () {
      const source = '''
%RESERVED has no meaning
---
- &value value
- *value
...

%TAG !! !unused
---
!tag &map { key: value}
''';

      check(
        dumpYamlDocuments(YamlParser(source).parseDocuments()),
      ).equals('''
%YAML 1.2
%RESERVED has no meaning
---
!!seq [
 &value !!str value,
 *value
]
...
%YAML 1.2
%TAG !! !unused
---
&map !tag {
 !!str key: !!str value
}
...
''');
    });
  });
}
