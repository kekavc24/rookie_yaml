part of 'parser_delegate.dart';

/// Creates a `null` wrapped in a [ScalarDelegate].
ScalarDelegate<T> nullScalarDelegate<T>({
  required int indentLevel,
  required int indent,
  required RuneOffset startOffset,
  required ScalarFunction<T> resolver,
}) => ScalarDelegate(
  indentLevel: indentLevel,
  indent: indent,
  start: startOffset,
  scalarResolver: resolver,
);

/// A delegate that resolves to a [Scalar].
final class ScalarDelegate<T> extends ParserDelegate<T> {
  ScalarDelegate({
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.scalarResolver,
    PreScalar? prescalar,
  }) : content = prescalar?.content ?? '',
       wroteLineBreak = prescalar?.wroteLineBreak ?? false,
       scalarStyle = prescalar?.scalarStyle ?? ScalarStyle.plain {
    if (prescalar == null) return;

    indent = prescalar.scalarIndent;
    _hasLineBreak = prescalar.hasLineBreak;
    _end = prescalar.end;
  }

  /// Parsed content
  final String content;

  /// [content] has a line break.
  final bool wroteLineBreak;

  /// Scalar style
  final ScalarStyle scalarStyle;

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ScalarFunction<T> scalarResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (suffix == mappingTag || suffix == sequenceTag) {
      throw FormatException('A scalar cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, stringTag);
  }

  @override
  T _resolver() {
    ScalarValue? value;

    if (_tag case ContentResolver<dynamic>(
      :final resolver,
      :final toYamlSafe,
      :final acceptNullAsValue,
    )) {
      if (resolver(content) case dynamic resolved
          when resolved != null || acceptNullAsValue) {
        value = CustomValue(resolved, toYamlSafe: toYamlSafe);
      }
    }

    return scalarResolver(
      // Just infer our way if it cannot be resolved or it was never declared
      value ??
          ScalarValue.fromParsedScalar(
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
              _tag = _defaultTo(inferred);
            },
          ),
      scalarStyle,
      _tag ?? _defaultTo(nullTag),
      _anchor,
      (start: start, end: _ensureEndIsSet()),
    );
  }
}
