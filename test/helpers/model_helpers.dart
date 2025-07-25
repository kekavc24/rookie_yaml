import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

dynamic _inferredValue(PreScalar scalar) => scalar.inferredValue;

extension PreScalarHelper on Subject<PreScalar?> {
  void hasScalarStyle(ScalarStyle style) =>
      isNotNull().has((p) => p.scalarStyle, 'ScalarStyle').equals(style);

  void hasIndent(int indent) =>
      isNotNull().has((p) => p.scalarIndent, 'Inferred indent').equals(indent);

  void hasFormattedContent(String content) => isNotNull()
      .has((p) => p.parsedContent, 'Canonical Content')
      .equals(content);

  void hasDocEndMarkers() => isNotNull()
      .has((p) => p.hasDocEndMarkers, 'Document End Markers')
      .isTrue();

  void indentDidChangeTo(int indent) => isNotNull()
    ..has((p) => p.indentDidChange, 'Indent Change Indicator').isTrue()
    ..has((p) => p.indentOnExit, 'Indent on Exit').equals(indent);

  void hasInferred<T>(
    T Function(PreScalar scalar) extractor,
    String name,
    T expected,
  ) => isNotNull().has(extractor, name).isA<T>().equals(expected);

  void simpleInferredType<T>(String name, T expected) =>
      hasInferred(_inferredValue, name, expected);

  void hasParsedInteger(int number, int radix) => hasInferred(
    (p) => (p.inferredValue, p.radix),
    'Parsed Integer',
    (number, radix),
  );

  void inferredBool(bool value) => simpleInferredType('Boolean', value);

  void inferredFloat(double value) => simpleInferredType('Float', value);

  void inferredNull() => isNotNull().has(_inferredValue, 'Null').isNull();
}

extension ParsedNodeHelper on Subject<ParsedYamlNode?> {
  Subject<ResolvedTag?> withTag() =>
      isNotNull().has((n) => n.tag, 'Resolved tag');

  void hasNoTag() => withTag().isNull();

  void hasTag<T>(SpecificTag<T> tag, {String suffix = ''}) => withTag()
      .isNotNull()
      .has((t) => t.verbatim, 'As verbatim')
      .equals(ParsedTag(tag, suffix).verbatim);
}
