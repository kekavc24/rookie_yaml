import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/yaml_loaders.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/model_helpers.dart';

final class _SimpleUtfBuffer extends BytesToScalar<List<int>> {
  _SimpleUtfBuffer({
    required super.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  final buffer = <int>[];

  @override
  void Function() get onComplete =>
      () => buffer.add(-1); // Spike on complete

  @override
  CharWriter get onWriteRequest => buffer.add;

  @override
  List<int> parsed() => buffer;
}

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
        ).isA<Scalar>()
        ..hasInferred('Dart ascii string', string)
        ..hasTag(asciiTag);
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
        ).isA<Scalar>()
        ..hasInferred('Dart ascii string', string)
        ..hasTag(yamlGlobalTag, suffix: stringTag);
    });
  });

  group('Custom Resolver', () {
    const scalar = 'Code Units in Scalar';
    final tag = TagShorthand.fromTagUri(TagHandle.primary(), 'buffer');

    final resolver = ObjectFromScalarBytes<List<int>>(
      onCustomScalar: (style, indentLevel, indent, start) => _SimpleUtfBuffer(
        scalarStyle: style,
        indentLevel: indentLevel,
        indent: indent,
        start: start,
      ),
    );

    test('Buffers all code units of scalar', () {
      check(
        loadDartObject(
          YamlSource.string('$tag $scalar'),
          nodeResolvers: {tag: resolver},
        ),
      ).isA<List<int>>().deepEquals(scalar.codeUnits.followedBy([-1]));
    });

    test('Buffers all code units of scalar when in list', () {
      check(
        loadDartObject(
          YamlSource.string('- $tag $scalar'),
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
        loadDartObject(
          YamlSource.string('{$mimic: $mimic}'),
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
