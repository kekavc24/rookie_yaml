import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/model_helpers.dart';

void main() {
  const asciiList = [73, 32, 108, 111, 118, 101, 32, 68, 97, 114, 116];
  const suffix = 'ascii-tag';

  final asciiTag = TagShorthand.fromTagUri(TagHandle.primary(), suffix);

  test('Resolves scalar', () {
    final asciiString = asciiList.join(' ');

    final resolver = PreResolvers<String, String>.string(
      suffix,
      contentResolver: (s) => String.fromCharCodes(
        s.split(' ').map(int.parse).toList(),
      ),
      toYamlSafe: (t) => t.codeUnits.join(' '),
    );

    final yaml =
        '''
- $asciiTag "$asciiString" # Double quoted
- $asciiTag '$asciiString' # Single quoted
- $asciiTag  $asciiString  # Plain
- $asciiTag |-             # Literal
   $asciiString
- $asciiTag >-             # Folded
   $asciiString
''';

    check(
      bootstrapDocParser(
        yaml,
        resolvers: [resolver],
      ).parseDocs().parseNodeSingle(),
    ).isA<Sequence>().every(
      (p) => p.isA<Scalar>()
        ..hasInferred('Dart ascii string', String.fromCharCodes(asciiList))
        ..hasTag(asciiTag),
    );
  });

  test('Resolves flow sequence', () {
    final resolver = PreResolvers.node(
      suffix,
      resolver: (s) => String.fromCharCodes(
        s.castTo<Sequence>().map((e) => (e as Scalar).value as int),
      ),
    );

    final yaml = '$asciiTag $asciiList';

    check(
          bootstrapDocParser(
            yaml,
            resolvers: [resolver],
          ).parseDocs().parseNodeSingle(),
        )
        .isNotNull()
        .has((p) => p.asCustomType(), 'Custom type')
        .which((v) => v.isNotNull().equals(String.fromCharCodes(asciiList)));
  });

  test('Resolves block map', () {
    // Let's create a tag. Resolver is a bit verbose
    final yaml =
        '''
$asciiTag { handle: primary, suffix: $suffix}
''';

    final resolver = PreResolvers<Mapping, TagShorthand>.node(
      suffix,
      resolver: (m) {
        final map = m.castTo<Mapping>();
        dynamic mapVal(dynamic key) => (map[DartNode(key)] as Scalar).value;

        return TagShorthand.fromTagUri(
          switch (mapVal('handle')) {
            'secondary' => TagHandle.secondary(),
            dynamic val when val != 'primary' => TagHandle.named(
              val.toString(),
            ),
            _ => TagHandle.primary(),
          },
          mapVal('suffix').toString(),
        );
      },
    );

    check(
          bootstrapDocParser(
            yaml,
            resolvers: [resolver],
          ).parseDocs().parseNodeSingle(),
        )
        .isNotNull()
        .has((p) => p.asCustomType(), 'Custom type')
        .which((v) => v.isNotNull().equals(asciiTag));
  });
}
