part of 'object_delegate.dart';

/// A delegate that accepts the bytes/code units of a scalar from the directly
/// underlying [SourceIterator].
abstract base class BytesToScalar<T> extends ObjectDelegate<T> {
  /// A callback for the scalar function at the lowest level that has access to
  /// the [SourceIterator] backing the parser. Will be called for every code
  /// point that is considered content.
  CharWriter get onWriteRequest;

  /// Always called once no more bytes/utf code units are present.
  ///
  /// The parser may fail to call this method if the scalar was declared as a
  /// [ScalarStyle.plain] node with no content. Your delegate implementation
  /// must take this into consideration if your scalar may be empty.
  void onComplete();
}

/// A delegate that accepts a scalar-like value.
sealed class ScalarLikeDelegate<T> extends NodeDelegate<T> {
  ScalarLikeDelegate({
    required this.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Scalar style
  final ScalarStyle scalarStyle;
}

/// Wraps a [BytesToScalar].
final class BoxedScalar<T> extends ScalarLikeDelegate<T> {
  BoxedScalar(
    this.delegate, {
    required super.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// External delegate that accepts code points representing the scalar's
  /// content.
  final BytesToScalar<T> delegate;

  @override
  set updateNodeProperties(ParsedProperty? property) {
    super.updateNodeProperties = property;
    delegate._property = property;
  }

  @override
  T parsed() => delegate.parsed();
}

/// A delegate that resolves to a [Scalar].
final class ScalarDelegate<T> extends ScalarLikeDelegate<T>
    with _ResolvingCache<T> {
  ScalarDelegate({
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.scalarResolver,
    this.isNullDelegate = false,
    PreScalar? prescalar,
  }) : content = prescalar?.content ?? '',
       wroteLineBreak = prescalar?.wroteLineBreak ?? false,
       super(
         scalarStyle: prescalar?.scalarInfo.scalarStyle ?? ScalarStyle.plain,
       ) {
    if (prescalar == null) return;

    indent = prescalar.scalarInfo.scalarIndent;
    _hasLineBreak = prescalar.scalarInfo.hasLineBreak;
    _end = prescalar.scalarInfo.end;
  }

  /// Whether this is a non-existent null.
  final bool isNullDelegate;

  /// Parsed content
  final String content;

  /// [content] has a line break.
  final bool wroteLineBreak;

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ScalarFunction<T> scalarResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlMapTag(suffix) || isYamlSequenceTag(suffix)) {
      throw FormatException('A scalar cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, stringTag);
  }

  @override
  T _resolveNode() {
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
            defaultToString: wroteLineBreak || _tag is ContentResolver,
            parsedTag: _tag?.suffix,
            ifParsedTagNull: (inferred) {
              /// Verbatim tags have no suffix. They are complete and in a
              /// resolved state as they are.
              ///
              /// Type resolver tags are somewhat qualified. They intentionally
              /// hide the suffix of a resolved tag forcing the scalar to be in
              /// its natural formatted form after parsing.
              if (_tag case VerbatimTag() || ContentResolver()) return;
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
  isNullDelegate: true,
);
