part of 'parser_delegate.dart';

/// A delegate that resolves to a [Scalar].
final class ScalarDelegate extends ParserDelegate {
  ScalarDelegate({
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
    required super.blockTags,
    required super.inlineTags,
    required super.blockAnchors,
    required super.inlineAnchors,
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
  }

  @override
  bool isChild(int indent) => false; // Scalars have no children.

  /// Returns a [Scalar].
  ///
  /// Scalars are resolved immediately once their parsing is complete when the
  /// [scalar] setter is called. If the setter is never called, an empty
  /// scalar is emitted with a [ScalarStyle.doubleQuoted].
  @override
  Node _resolveNode() {
    final parsedTags = tags();
    final parsedAnchors = anchors();

    return preScalar?.parsedScalar(parsedTags, parsedAnchors) ??
        Scalar(
          null,
          content: '',
          scalarStyle: ScalarStyle.plain,
          tags: parsedTags,
          anchors: parsedAnchors,
        );
  }
}
