import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

dynamic _inferredValue(PreScalar scalar) => scalar.inferredValue;

extension PreScalarHelper on Subject<PreScalar?> {
  void hasScalarStyle(ScalarStyle style) =>
      isNotNull().has((p) => p.scalarStyle, 'ScalarStyle').equals(style);

  void hasFormattedContent(String content) => isNotNull()
      .has((p) => p.parsedContent, 'Canonical Content')
      .equals(content);

  void hasDocEndMarkers() => isNotNull()
      .has((p) => p.hasDocEndMarkers, 'Document End Markers')
      .isTrue();

  void indentDidChangeTo(int indent) => isNotNull()
    ..has((p) => p.indentDidChange, 'Indent Change Indicator').isTrue()
    ..has((p) => p.indentOnExit, 'Indent on Exit').equals(indent);

  void _hasInferred<T>(
    T Function(PreScalar scalar) extractor,
    String name,
    T expected,
  ) => isNotNull().has(extractor, name).isA<T>().equals(expected);

  void simpleInferredType<T>(String name, T expected) =>
      _hasInferred(_inferredValue, name, expected);

  void hasParsedInteger(int number, int radix) => _hasInferred(
    (p) => (p.inferredValue, p.radix),
    'Parsed Integer',
    (number, radix),
  );

  void inferredBool(bool value) => simpleInferredType('Boolean', value);

  void inferredFloat(double value) => simpleInferredType('Float', value);

  void inferredNull() => isNotNull().has(_inferredValue, 'Null').isNull();
}
