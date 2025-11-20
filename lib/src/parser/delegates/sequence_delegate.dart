part of 'parser_delegate.dart';

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

/// A delegate that resolves to a [Sequence]
final class SequenceDelegate<I, S extends Iterable<I>>
    extends ParserDelegate<S> {
  SequenceDelegate._(
    this._iterable, {
    required _OnSequenceInput<I> onInput,
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.listResolver,
  }) : _pushFunc = onInput;

  final NodeStyle collectionStyle;

  /// Iterable matching the type of sequence.
  final Iterable<I> _iterable;

  /// Adds elements to the [_iterable]
  final _OnSequenceInput<I> _pushFunc;

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ListFunction<I, S> listResolver;

  factory SequenceDelegate.byKind({
    required NodeStyle style,
    required int indent,
    required int indentLevel,
    required RuneOffset start,
    required ListFunction<I, S> resolver,
    NodeKind kind = NodeKind.sequence,
  }) {
    final (iterable, pushFunc) = kind == NodeKind.set
        ? _setHelper<I>()
        : _listHelper<I>();

    return SequenceDelegate._(
      iterable,
      onInput: pushFunc,
      collectionStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
      listResolver: resolver,
    );
  }

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlScalarTag(suffix) || (suffix != setTag && isYamlMapTag(suffix))) {
      throw FormatException('A sequence cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, sequenceTag);
  }

  /// Adds an [input] to the iterable backing this delegate.
  void accept(I input) => _pushFunc(input);

  /// Whether the iterable backing this delegate has no elements.
  bool get isEmpty => _iterable.isEmpty;

  @override
  S _resolver() => listResolver(
    _iterable,
    collectionStyle,
    _tag ?? _defaultTo(_iterable is Set ? setTag : sequenceTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
