part of 'object_delegate.dart';

/// A delegate that maps an iterable to an object [T]. No intermediate [List] or
/// [Iterable] is constructed. You must override the `parsed` method.
///
/// Additionally, it has been forced to accept a nullable [Object] as an
/// element. All subclasses need to guarantee their own runtime safety in case
/// the shape of the YAML sequence doesn't match the desired object.
abstract base class SequenceToObject<T> = ObjectDelegate<T>
    with _IterableDelegate<Object?>;

/// A delegate that buffers to a sequence-like structure.
abstract base class SequenceLikeDelegate<E, T> extends NodeDelegate<T>
    with _IterableDelegate<E> {
  SequenceLikeDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// [NodeStyle] for the sequence-like node.
  final NodeStyle collectionStyle;

  /// Creates a [SequenceLikeDelegate] for an external sequence linked to a tag.
  factory SequenceLikeDelegate.boxed(
    SequenceToObject<T> delegate, {
    required NodeStyle collectionStyle,
    required int indentLevel,
    required int indent,
    required RuneOffset start,
  }) =>
      _BoxedSequence(
            delegate,
            collectionStyle: collectionStyle,
            indentLevel: indentLevel,
            indent: indent,
            start: start,
          )
          as SequenceLikeDelegate<E, T>;
}

/// Wraps an external [SequenceToObject] and allows it to behave like a
/// [SequenceLikeDelegate] that the parser can interact with.
final class _BoxedSequence<T> extends SequenceLikeDelegate<Object?, T> {
  _BoxedSequence(
    this._delegate, {
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Delegate with external sequence implementation.
  final SequenceToObject<T> _delegate;

  @override
  set updateNodeProperties(ParsedProperty? property) {
    super.updateNodeProperties = property;
    _delegate._property = property;
  }

  @override
  void accept(Object? input) => _delegate.accept(input);

  @override
  T parsed() => _delegate.parsed();
}

/// Callback for pushing elements into an iterable
typedef _OnSequenceInput<T> = void Function(T input);

/// An iterable and its push function
typedef _SequenceHelper<T> = (Iterable<T> iterable, _OnSequenceInput<T>);

/// Creates a set and its push function
_SequenceHelper<T> _setHelper<T>() {
  final seq = <T>{};
  return (seq, seq.add);
}

/// Creates a list and its push function
_SequenceHelper<T> _listHelper<T>() {
  final seq = <T>[];
  return (seq, seq.add);
}

/// A delegate that resolves to a [Sequence].
final class GenericSequence<I> extends SequenceLikeDelegate<I, I>
    with _ResolvingCache<I> {
  GenericSequence._(
    this._iterable, {
    required _OnSequenceInput<I> onInput,
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.listResolver,
  }) : _pushFunc = onInput;

  /// Iterable matching the type of sequence.
  final Iterable<I> _iterable;

  /// Adds elements to the [_iterable]
  final _OnSequenceInput<I> _pushFunc;

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ListFunction<I> listResolver;

  factory GenericSequence.byKind({
    required NodeStyle style,
    required int indent,
    required int indentLevel,
    required RuneOffset start,
    required ListFunction<I> resolver,
    NodeKind kind = YamlKind.sequence,
  }) {
    final (iterable, pushFunc) = kind == YamlKind.set
        ? _setHelper<I>()
        : _listHelper<I>();

    return GenericSequence._(
      iterable,
      onInput: pushFunc,
      collectionStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      listResolver: resolver,
    );
  }

  /// Adds an [input] to the iterable backing this delegate.
  @override
  void accept(I input) => _pushFunc(input);

  /// Whether the iterable backing this delegate has no elements.
  bool get isEmpty => _iterable.isEmpty;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlScalarTag(suffix) || suffix == mappingTag) {
      throw FormatException('A sequence cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, sequenceTag);
  }

  @override
  I _resolveNode() => listResolver(
    _iterable,
    collectionStyle,
    _tag ?? _defaultTo(_iterable is Set ? setTag : sequenceTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
