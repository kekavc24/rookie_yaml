part of 'object_delegate.dart';

/// A delegate that accepts the bytes/code units of a scalar from the underlying
/// [SourceIterator].
///
/// All implementations of this object are guaranteed to be returned as an
/// "as-is" [T] if a spec-compliant YAML string is provided. The parser will
/// only call `parsed` on this object and any parsed properties defined in the
/// [ObjectDelegate] parent class will be available.
///
/// See also the [TagInfo] mixin.
///
/// {@category bytes_to_scalar}
abstract class BytesToScalar<T> extends ObjectDelegate<T> {
  BytesToScalar();

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

  /// Creates a [BytesToScalar] that buffers the utf code points of the
  /// underlying scalar on your behalf and uses the [mapper] to obtain [T].
  ///
  /// [onSliced] is called when no more bytes are present. However, the parser
  /// \*may\* fail to call this method if the scalar was declared as a
  /// [ScalarStyle.plain] node with no content.
  factory BytesToScalar.sliced({
    required T Function(List<int> slice) mapper,
    void Function()? onSliced,
  }) => _LazyScalarSlice<T>(mapper: mapper, onSliced: onSliced ?? () {});
}

/// A delegate that buffers all the utf code points of a scalar's content and
/// maps it to [T].
final class _LazyScalarSlice<T> extends BytesToScalar<T> {
  _LazyScalarSlice({required this.mapper, required this.onSliced});

  /// Buffers the unicode code point of the underlying scalar.
  final _mainBuffer = <int>[];

  /// Creates [T] from the buffered slice.
  final T Function(List<int> slice) mapper;

  /// Called when no more characters are available.
  final void Function() onSliced;

  @override
  void onComplete() => onSliced();

  @override
  CharWriter get onWriteRequest => _mainBuffer.add;

  @override
  T parsed() => mapper(_mainBuffer);
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

/// A delegate that wraps an external [BytesToScalar] implementation and allows
/// the parser to interact with it.
///
/// Unlike internal implementations wrapped by the [EfficientScalarDelegate],
/// the parser never resolves the [BytesToScalar] wrapped by this class. Any
/// parsed properties are left untouched and only called `parsed`.
final class BoxedScalar<T> extends ScalarLikeDelegate<T>
    with _BoxedCallOnce<T> {
  BoxedScalar(
    this.delegate, {
    required super.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.afterScalar,
  });

  /// External delegate that accepts code points representing the scalar's
  /// content.
  final BytesToScalar<T> delegate;

  /// Called when the scalar is complete.
  final AfterScalar<T> afterScalar;

  @override
  set updateNodeProperties(ParsedProperty? property) {
    super.updateNodeProperties = property;
    delegate._property = property;
  }

  @override
  T parsed() => _callOnce(
    delegate.parsed(),
    ifNotCalled: (type) => afterScalar(
      scalarStyle,
      type,
      _anchor,
      nodeSpan(),
    ),
  );
}

/// A delegate that resolves to a [Scalar].
///
/// As the name suggests, this delegate behaves like a normal
/// [ScalarLikeDelegate] which can interact with the parser and also doubles
/// as a low level [BytesToScalar] delegate that accepts a scalar's utf code
/// points and forwards them to a concrete [ScalarValueDelegate] which returns
/// its valid representation of the [Scalar]'s value and its context-less schema
/// tag. However, this delegate may override such a value and schema tag based
/// on the YAML version implemented by the parser.
final class EfficientScalarDelegate<T> extends ScalarLikeDelegate<T>
    with _ResolvingCache<T>
    implements BytesToScalar<T> {
  EfficientScalarDelegate._(
    this._delegate, {
    required super.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.scalarResolver,
    this.isNullDelegate = true,
  });

  /// Creates a delegate for an empty plain scalar that can be treated as
  /// `null`.
  EfficientScalarDelegate.empty({
    required int indentLevel,
    required int indent,
    required RuneOffset startOffset,
    required ScalarFunction<T> resolver,
  }) : this._(
         StringDelegate(),
         scalarStyle: ScalarStyle.plain,
         indentLevel: indentLevel,
         indent: indent,
         start: startOffset,
         scalarResolver: resolver,
       );

  /// Creates a delegate whose scalar's type matches the [delegate] it writes
  /// code points to.
  EfficientScalarDelegate.ofScalar(
    ScalarValueDelegate<Object?> delegate, {
    required ScalarStyle style,
    required int indentLevel,
    required int indent,
    required RuneOffset start,
    required ScalarFunction<T> resolver,
  }) : this._(
         delegate,
         scalarStyle: style,
         indentLevel: indentLevel,
         indent: indent,
         start: start,
         scalarResolver: resolver,
         isNullDelegate: false,
       );

  /// Whether this is a non-existent null.
  final bool isNullDelegate;

  /// The actual delegate accepting bytes.
  final ScalarValueDelegate<Object?> _delegate;

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ScalarFunction<T> scalarResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlMapTag(suffix) || isYamlSequenceTag(suffix)) {
      throw FormatException('A scalar cannot be resolved as "$suffix" kind');
    }

    return overrideNonSpecific(tag, stringTag);
  }

  @override
  void onComplete() {
    _delegate.onComplete();
    hasLineBreak = _delegate.bufferedLineBreak;
  }

  @override
  CharWriter get onWriteRequest => _delegate.onWriteRequest;

  @override
  T _resolveNode() {
    var (:schemaTag, :scalar) = _delegate.parsed();

    if (_tag case ContentResolver<Object?>(
      :final resolver,
      :final toYamlSafe,
      :final acceptNullAsValue,
    )) {
      assert(
        scalar.value is String,
        'Resolution error. Expected [DartValue<String>] but found '
        '[${scalar.runtimeType}]. Please file a bug at '
        'https://github.com/kekavc24/rookie_yaml/issues',
      );

      if (resolver(scalar.value as String) case Object? resolved
          when resolved != null || acceptNullAsValue) {
        return scalarResolver(
          CustomValue(resolved, toYamlSafe: toYamlSafe),
          scalarStyle,
          _tag,
          _anchor,
          nodeSpan(),
        );
      }
    } else if (_tag is! VerbatimTag &&
        (isNullDelegate ||
            scalarStyle == ScalarStyle.plain &&
                scalar is NullView &&
                scalar.isVirtual)) {
      scalar = _resolveNullDelegate(scalar);
    }

    // Verbatim tags are in a resolved state as they are.
    return scalarResolver(
      scalar,
      scalarStyle,
      (_tag != null || _tag is VerbatimTag) ? _tag : _defaultTo(schemaTag),
      _anchor,
      nodeSpan(),
    );
  }

  /// Lazily resolves `this` to `null` if possible.
  ScalarValue<Object?> _resolveNullDelegate(ScalarValue<Object?> object) {
    if (_tag case NodeTag(:final suffix) when suffix.toString() != '!!null') {
      return object is NullView ? DartValue('') : object;
    }

    _tag ??= _defaultTo(nullTag);
    return NullView('');
  }
}

/// Creates a `null` wrapped by a [EfficientScalarDelegate]. The `null` may
/// be defaulted to an empty string if a custom tag is assigned to this
/// delegate while parsing.
EfficientScalarDelegate<T> nullScalarDelegate<T>({
  required int indentLevel,
  required int indent,
  required RuneOffset startOffset,
  required ScalarFunction<T> resolver,
}) => EfficientScalarDelegate.empty(
  indentLevel: indentLevel,
  indent: indent,
  startOffset: startOffset,
  resolver: resolver,
);
