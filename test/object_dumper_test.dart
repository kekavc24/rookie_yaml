import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/object_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    forceReset();
  });

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
        forceMapsInline: true,
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
            forceMapsInline: true,
          ),
        ),
      ).equals('''
- clean
- &anchor scalar
- *anchor
- &anchor {key: value}
- *anchor
''');

      check(
        dumpObject(
          object,
          dumper: ObjectDumper.of(
            unpackAliases: true,
            mapStyle: NodeStyle.flow,
            forceMapsInline: true,
          ),
        ),
      ).equals('''
- clean
- &anchor scalar
- &anchor scalar
- &anchor {key: value}
- &anchor {key: value}
''');
    });

    test('Dumps an object as a full document', () {
      final globalTag = GlobalTag.fromTagUri(
        TagHandle.primary(),
        'hello:world.com',
      );

      final object = dumpableType(24)
        ..withNodeTag(
          localTag: TagShorthand.primary('tag'),
          globalTag: globalTag,
        );

      check(
        dumpObject(
          object,
          dumper: ObjectDumper.compact(),
          includeYamlDirective: true,
          includeDocumendEnd: true,
        ),
      ).equals('''
$parserVersion
$globalTag
---
!tag 24
...''');
    });

    test('Handles captured global tags and anchors correctly', () {
      final local = TagShorthand.primary('capture');
      final global = GlobalTag.fromTagShorthand(TagHandle.primary(), local);

      final object = [
        dumpableType(24)
          ..anchor = 'capture'
          ..withNodeTag(localTag: local, globalTag: global),
      ];

      String dump({OnProperties? onProps, bool includeGlobals = true}) {
        return dumpObject(
          object,
          dumper: ObjectDumper.compact(),
          objectProperties: onProps,
          includeGlobalTags: includeGlobals,
        );
      }

      const dumped = '- &capture !capture 24\n';

      // Includes global tags
      check(dump()).equals(
        '$global'
        '\n---'
        '\n$dumped',
      );

      final captured = <String>[];

      // Ignored
      check(
        dump(
          onProps: (tags, anchors) => captured.addAll(
            tags
                .map((e) => e.value.toString())
                .followedBy(anchors.map((e) => e.$1)),
          ),
          includeGlobals: false,
        ),
      ).equals(dumped);

      check(captured).deepEquals([global.toString(), 'capture']);

      // Must have at least one
      check(() => dump(includeGlobals: false))
          .throws<ArgumentError>()
          .has((e) => e.message, 'Error')
          .equals(
            'You must provide [onProperties] or allow global tags in the'
            " object's YAML content",
          );
    });

    test('Ignores comments when flow collections are inlined', () {
      check(
        dumpObject(
          [
            dumpableType('scalar')..comments.add('ignored'),
            dumpableType({'key': 'value'})..comments.add('ignored'),
          ],
          dumper: ObjectDumper.of(
            iterableStyle: NodeStyle.flow,
            mapStyle: NodeStyle.flow,
            forceMapsInline: true,
            forceIterablesInline: true,
          ),
        ),
      ).equals('[scalar, {key: value}]');
    });

    test('Respects the style of a nested flow node when declared in block', () {
      check(
        dumpObject(
          [
            dumpableType('scalar')..comments.add('comment'),
            dumpableType(['flow', 'list'])
              ..nodeStyle = NodeStyle.flow
              ..comments.add('comment'),
            dumpableType({'flow': 'map'})
              ..nodeStyle = NodeStyle.flow
              ..comments.add('comment'),
          ],
          dumper: ObjectDumper.of(
            commentStyle: CommentStyle.inline,
            forceMapsInline: true,
            forceIterablesInline: true,
          ),
        ),
      ).equals('''
- scalar # comment
- [flow, list] # comment
- {flow: map} # comment
''');
    });
  });

  group('Inline comments', () {
    test('Inline comments in flow scalars', () {
      const content = 'scalar';
      final type = dumpableType(content)..comments.addAll(['Hello', 'World']);

      void checkScalar(ScalarStyle style, [String wrap = '', int step = 0]) {
        final scalar = wrap.isEmpty ? content : '$wrap$content$wrap';

        check(
          dumpObject(
            type,
            dumper: ObjectDumper.of(
              scalarStyle: style,
              commentStyle: CommentStyle.inline,
              commentStepSize: step,
            ),
          ),
        ).equals(
          CommentDumper(CommentStyle.inline, step).applyComments(
            scalar,
            comments: type.comments,
            forceBlock: false,
            indent: 0,
            offsetFromMargin: scalar.length,
          ),
        );
      }

      checkScalar(ScalarStyle.plain);
      checkScalar(ScalarStyle.doubleQuoted, '"');
      checkScalar(ScalarStyle.singleQuoted, "'");

      checkScalar(ScalarStyle.plain, '', 2);
      checkScalar(ScalarStyle.doubleQuoted, '"', 2);
      checkScalar(ScalarStyle.singleQuoted, "'", 2);
    });

    test('Inline comments in flow iterables', () {
      final iterable = dumpableType([
        24,
        dumpableType(24)..comments.addAll(['scalar', 'comment']),
        dumpableType([24, 30])..comments.addAll(['flow', 'comment']),
      ])..comments.addAll(['parent', 'flow', 'comments']);

      check(
        dumpObject(
          iterable,
          dumper: ObjectDumper.of(
            iterableStyle: NodeStyle.flow,
            commentStyle: CommentStyle.inline,
          ),
        ),
      ).equals('''
[
 24,
 24, # scalar
     # comment
 [
  24,
  30
 ], # flow
    # comment
] # parent
  # flow
  # comments''');
    });

    test('Inline comments in flow maps', () {
      final map = dumpableType({
        dumpableType(24)..comments.addAll(['key', 'comment']): dumpableType(24)
          ..comments.addAll(['value', 'comment']),
        'hello': dumpableType({'there': 'world'})
          ..comments.addAll(['flow', 'map', 'comments']),
      })..comments.addAll(['parent', 'flow', 'comments']);

      check(
        dumpObject(
          map,
          dumper: ObjectDumper.of(
            mapStyle: NodeStyle.flow,
            commentStyle: CommentStyle.inline,
          ),
        ),
      ).equals('''
{
 24: # key
     # comment
  24, # value
      # comment
 hello: {
   there: world
  }, # flow
     # map
     # comments
} # parent
  # flow
  # comments''');
    });
  });

  group('Block comments', () {
    test('Dumps comments as block in scalars', () {
      final scalar = dumpableType('scalar')
        ..comments.addAll(['Block', 'Comment']);
      final commentHeader = scalar.comments.map((e) => '# $e').join('\n');

      void block(ScalarStyle style, String string) {
        check(
          dumpObject(scalar, dumper: ObjectDumper.of(scalarStyle: style)),
        ).equals(
          '$commentHeader\n'
          '$string',
        );
      }

      block(ScalarStyle.doubleQuoted, '"scalar"');
      block(ScalarStyle.singleQuoted, "'scalar'");
      block(ScalarStyle.plain, 'scalar');
      block(ScalarStyle.folded, '>-\nscalar');
      block(ScalarStyle.literal, '|-\nscalar');
    });

    test('Dumps comments as block in iterables', () {
      check(
        dumpObject(
          dumpableType([
            dumpableType(24)..comments.addAll(['scalar', 'comment']),
            25,
            dumpableType(['free', 'range'])
              ..comments.addAll(['nested', 'list']),
          ])..comments.addAll(['block', 'parent']),
          dumper: ObjectDumper.compact(),
        ),
      ).equals('''
# block
# parent
- # scalar
  # comment
  24
- 25
- # nested
  # list
  - free
  - range
''');
    });

    test('Dumps comments as block in maps', () {
      check(
        dumpObject(
          dumpableType({
            24: 'hello',
            dumpableType(35)
              ..comments.addAll(['key', 'comments']): dumpableType({
              'block': 'map',
            })..comments.addAll(['nested', 'map']),
          })..comments.addAll(['parent', 'map']),
          dumper: ObjectDumper.compact(),
        ),
      ).equals('''
# parent
# map
24: hello
# key
# comments
35:
 # nested
 # map
 block: map
''');
    });
  });
}
