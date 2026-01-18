import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/object_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

void main() {
  group('Dumps YamlSourceNode', () {
    test('Dumps a YamlSourceNode back to a reproducible state', () {
      const source = '''
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
  !!str &anchor value,
  *anchor,
  !tag [ *anchor, 24 ],
]
''';

      check(
        dumpObject(
          loadYamlNode(YamlSource.string(source)),
          dumper: ObjectDumper.of(iterableStyle: NodeStyle.flow),
          includeYamlDirective: true,
        ),
      ).equals('''
%YAML 1.2
%TAG !reproducible! !reproducible
---
!reproducible!sequence [
 &anchor !!str value,
 *anchor,
 !tag [
  *anchor,
  !!int 24
 ]
]''');
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

      final dumper = ObjectDumper.of(
        mapStyle: NodeStyle.flow,
        flowMapInline: true,
      );

      check(
        loadAllDocuments(YamlSource.string(source))
            .map(
              (doc) => dumpObject(
                doc.root,
                dumper: dumper,
                includeDocumendEnd: doc.hasExplicitEnd,
                directives: doc.tagDirectives.cast<Directive>().followedBy(
                  doc.otherDirectives,
                ),
              ),
            )
            .join('\n'),
      ).equals('''
%RESERVED has no meaning
---
!!seq
- &value !!str value
- *value
...
%TAG !! !unused
---
&map !tag {!!str key: !!str value}''');
    });
  });

  group('General', () {
    test('Links custom global tags present in properties', () {
      final globalFromTag = GlobalTag.fromTagShorthand(
        TagHandle.primary(),
        TagShorthand.fromTagUri(TagHandle.primary(), 'global-shorthand'),
      );

      final globalFromUri = GlobalTag.fromTagUri(
        TagHandle.named('uri'),
        'uri:as.global',
      );

      final object = [
        dumpableType(24)..withNodeTag(
          localTag: TagShorthand.primary('tag'),
          globalTag: globalFromTag,
        ),
        dumpableType('24')..withNodeTag(
          localTag: TagShorthand.named('uri', 'tag'),
          globalTag: globalFromUri,
        ),
        dumpableType(24.0)..withVerbatimTag(
          VerbatimTag.fromTagShorthand(TagShorthand.primary('verbatim')),
        ),
      ];

      check(
        dumpObject(
          object,
          dumper: ObjectDumper.of(
            iterableStyle: NodeStyle.block,
            scalarStyle: ScalarStyle.doubleQuoted,
          ),
        ),
      ).equals('''
$globalFromTag
$globalFromUri
---
- !tag "24"
- !uri!tag "24"
- !<!verbatim> "24.0"
''');
    });

    test('Links aliases correctly', () {
      final object = [
        'clean',
        dumpableType('scalar')..anchor = 'anchor',
        Alias('anchor'),
        dumpableType({'key': 'value'})..anchor = 'anchor',
        Alias('anchor'),
      ];

      check(
        dumpObject(
          object,
          dumper: ObjectDumper.of(
            mapStyle: NodeStyle.flow,
            flowMapInline: true,
          ),
        ),
      ).equals('''
- clean
- &anchor scalar
- *anchor
- &anchor {key: value}
- *anchor
''');
    });
  });
}
