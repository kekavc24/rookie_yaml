part of 'parser_delegate.dart';

/// A delegate that resolves to a [Scalar].
final class ScalarDelegate extends ParserDelegate {
  ScalarDelegate({
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  PreScalar? _prescalar;

  PreScalar? get preScalar => _prescalar;

  set scalar(PreScalar scalar) {
    assert(
      preScalar == null,
      'A scalar can only be resolved once after its parsing is complete',
    );

    _prescalar = scalar;
    indent = scalar.scalarIndent;
    _hasLineBreak = scalar.hasLineBreak;
    _end = scalar.end;
  }

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (suffix == mappingTag || suffix == sequenceTag) {
      throw FormatException('A scalar cannot be resolved as "$suffix" kind');
    }

    return tag;
  }

  @override
  bool isChild(int indent) => false; // Scalars have no children.

  /// Returns a [Scalar].
  ///
  /// Scalars are resolved immediately once their parsing is complete when the
  /// [scalar] setter is called. If the setter is never called, an empty
  /// scalar is emitted with a [ScalarStyle.doubleQuoted].
  @override
  Scalar<T> _resolveNode<T>() {
    final end = _end!;

    if (_prescalar != null) {
      final PreScalar(:content, :scalarStyle, :wroteLineBreak) = _prescalar!;

      ScalarValue<T>? value;

      if (_tag case ContentResolver<T>(
        :final resolver,
        :final toYamlSafe,
        :final acceptNullAsValue,
      )) {
        if (resolver(content) case T? resolved
            when resolved != null || acceptNullAsValue) {
          value = CustomValue(resolved as T, toYamlSafe: toYamlSafe);
        }
      }

      // Just infer our way if it cannot be resolved or it was never declared
      value ??= ScalarValue.fromParsedScalar(
        content,
        defaultToString: wroteLineBreak || _tag is NodeResolver,
        parsedTag: _tag?.suffix,
        ifParsedTagNull: (inferred) {
          /// Verbatim tags have no suffix. They are complete and in a
          /// resolved state as they are.
          ///
          /// Type resolver tags are somewhat qualified. They intentionally
          /// hide the suffix of a resolved tag forcing the scalar to be in
          /// its natural formatted form after parsing.
          if (_tag case VerbatimTag _ || TypeResolverTag _) return;
          _tag = NodeTag(yamlGlobalTag, inferred);
        },
      );

      return Scalar(
        value,
        scalarStyle: scalarStyle,
        tag: _tag,
        anchor: _anchor,
        nodeSpan: (start: start, end: end),
      );
    }

    return Scalar(
      NullView('') as ScalarValue<T>,
      scalarStyle: ScalarStyle.plain,
      tag: _tag ?? _defaultTo(nullTag),
      anchor: _anchor,
      nodeSpan: (start: start, end: end),
    );
  }
}
