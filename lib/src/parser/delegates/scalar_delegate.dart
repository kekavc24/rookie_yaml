part of 'parser_delegate.dart';

/// A delegate that resolves to a [Scalar].
final class ScalarDelegate extends ParserDelegate {
  ScalarDelegate({
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  PreScalar? preScalar;

  set scalar(PreScalar scalar) {
    assert(
      preScalar == null,
      'A scalar can only be resolved once after its parsing is complete',
    );

    preScalar = scalar;
    indent = scalar.scalarIndent;
    _hasLineBreak = scalar.hasLineBreak;
    updateEndOffset = scalar.end;
  }

  @override
  bool isChild(int indent) => false; // Scalars have no children.

  /// Returns a [Scalar].
  ///
  /// Scalars are resolved immediately once their parsing is complete when the
  /// [scalar] setter is called. If the setter is never called, an empty
  /// scalar is emitted with a [ScalarStyle.doubleQuoted].
  @override
  ParsedYamlNode _resolveNode() =>
      preScalar?.parsedScalar(_tag, _anchor) ??
      Scalar(
        null,
        content: '',
        scalarStyle: ScalarStyle.plain,
        tag: _tag,
        anchor: _anchor,
      );
}
