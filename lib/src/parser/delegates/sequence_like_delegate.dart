part of 'object_delegate.dart';

void throwIfNotListTag(TagShorthand suffix) => throwOnTagMismatch(
  suffix,
  (t) => isYamlScalarTag(suffix) || suffix == mappingTag,
  'mapping',
);

/// A delegate that behaves like a sequence/iterable.
mixin _IterableDelegate<E> {
  /// Adds an [input] to a sequence like delegate.
  void accept(E input);
}

/// A delegate that maps an iterable to an object [T] and accepts an object [E].
/// No intermediate [List] or [Iterable] is constructed. You must override the
/// `parsed` method.
///
/// {@category sequence_to_obj}
abstract base class SequenceToObject<E, T> = ObjectDelegate<T>
    with _IterableDelegate<E>;

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
    SequenceToObject<E, T> delegate, {
    required NodeStyle collectionStyle,
    required int indentLevel,
    required int indent,
    required RuneOffset start,
    required AfterCollection<T> afterSequence,
  }) => _BoxedSequence(
    delegate,
    collectionStyle: collectionStyle,
    indentLevel: indentLevel,
    indent: indent,
    start: start,
    afterSequence: afterSequence,
  );
}

/// Wraps an external [SequenceToObject] and allows it to behave like a
/// [SequenceLikeDelegate] that the parser can interact with.
final class _BoxedSequence<E, T> extends SequenceLikeDelegate<E, T>
    with _BoxedCallOnce<T> {
  _BoxedSequence(
    this._delegate, {
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.afterSequence,
  });

  /// Delegate with external sequence implementation.
  final SequenceToObject<E, T> _delegate;

  /// Called when the sequence is complete.
  final AfterCollection<T> afterSequence;

  @override
  set updateNodeProperties(ParsedProperty? property) {
    if (property == null) return;
    _delegate._property = property;

    super.updateNodeProperties = property;

    if (property is NodeProperty) {
      _anchor = property.anchor;
    }
  }

  @override
  void accept(E input) => _delegate.accept(input);

  @override
  T parsed() => _callOnce(
    _delegate.parsed(),
    ifNotCalled: (type) => afterSequence(
      collectionStyle,
      type,
      _anchor,
      nodeSpan(),
    ),
  );
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
  final YamlCollectionBuilder<I> listResolver;

  factory GenericSequence.byKind({
    required NodeStyle style,
    required int indent,
    required int indentLevel,
    required RuneOffset start,
    required YamlCollectionBuilder<I> resolver,
    NodeKind kind = YamlCollectionKind.sequence,
  }) {
    final (iterable, pushFunc) = kind == YamlCollectionKind.set
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
    throwIfNotListTag(tag.suffix);
    return overrideNonSpecific(tag, sequenceTag);
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
