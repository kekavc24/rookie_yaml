import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/test_resolvers.dart';

void main() {
  group('ScalarResolver', () {
    test('Resolves an ascii string to sequence of code units', () {
      const string = 'Dart is great';

      final codeUnits = string.codeUnits.join(' ');
      final asciiTag = TagShorthand.fromTagUri(TagHandle.primary(), 'ascii');

      final resolver = ScalarResolver.onMatch(
        asciiTag,
        contentResolver: (s) => String.fromCharCodes(
          s.split(' ').map(int.parse).toList(),
        ),
        toYamlSafe: (t) => t.codeUnits.join(' '),
      );

      final yaml = '$asciiTag "$codeUnits"';

      check(
        bootstrapDocParser(yaml, resolvers: [resolver]).parseNodeSingle(),
      ).equals(string);
    });

    test('Uses default parser resolution if tag is missing', () {
      const string = 'Will be ignored';

      final resolver = ScalarResolver.onMatch(
        TagShorthand.fromTagUri(TagHandle.primary(), 'ignored'),
        contentResolver: (s) => s.codeUnits,
        toYamlSafe: String.fromCharCodes,
      );

      check(
        bootstrapDocParser(string, resolvers: [resolver]).parseNodeSingle(),
      ).equals(string);
    });
  });

  group('Custom Resolver', () {
    const scalar = 'Code Units in Scalar';
    final tag = TagShorthand.fromTagUri(TagHandle.primary(), 'buffer');

    final resolver = ObjectFromScalarBytes<List<int>>(
      onCustomScalar: () => SimpleUtfBuffer(),
    );

    test('Buffers all code units of scalar', () {
      check(
        loadResolvedDartObject(
          '$tag $scalar',
          nodeResolvers: {tag: resolver},
        ),
      ).isA<List<int>>().deepEquals(scalar.codeUnits.followedBy([-1]));
    });

    test('Buffers all code units of scalar when in list', () {
      check(
        loadResolvedDartObject(
          '- $tag $scalar',
          nodeResolvers: {tag: resolver},
        ),
      ).isA<List>().which(
        (l) => l.first.isA<List<int>>().deepEquals(
          scalar.codeUnits.followedBy([-1]),
        ),
      );
    });

    test('Buffers all code units of scalar when in map', () {
      final mimic = '$tag $scalar';

      check(
        loadResolvedDartObject(
          '{$mimic: $mimic}',
          nodeResolvers: {tag: resolver},
        ),
      ).isA<Map>().which(
        (l) => l.entries.first.isA<MapEntry>()
          ..has((e) => e.key, 'Key').isA<List<int>>().deepEquals(
            scalar.codeUnits.followedBy([-1]),
          )
          ..has((e) => e.value, 'Value').isA<List<int>>().deepEquals(
            scalar.codeUnits.followedBy([-1]),
          ),
      );
    });
  });
}
