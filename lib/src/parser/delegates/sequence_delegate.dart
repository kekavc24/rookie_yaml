part of 'parser_delegate.dart';

/// A delegate that buffers to a sequence-like structure.
sealed class SequenceLikeDelegate<E, T> extends ParserDelegate<T> {
  /// Create a delegate that resolves a sequence-like structure.
  SequenceLikeDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// [NodeStyle] for the sequence-like node.
  final NodeStyle collectionStyle;

  /// Adds an [input] to the iterable backing this delegate.
  void accept(E input);
}

/// A delegate that maps an iterable to an object [T]. No intermediate [List] or
/// [Iterable] is constructed. Single element will always be provided once a
/// complete sequence entry has been parsed. You must override the `parsed`
/// method.
///
/// This class is a mirror of the intermediate object created before the
/// parser strips any styles and properties. This is the abstraction the parser
/// sees and not your object. All properties from the super class that this
/// class needs will be provided by the parser.
///
/// Additionally, it has been forced to accept a nullable [Object] as an
/// element. All subclasses need to guarantee their own runtime safety in case
/// the shape of the YAML sequence doesn't match the desired object.
abstract base class IterableToObjectDelegate<T>
    extends SequenceLikeDelegate<Object?, T> {
  IterableToObjectDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });
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
final class SequenceDelegate<I> extends SequenceLikeDelegate<I, I>
    with _ResolvingCache<I> {
  SequenceDelegate._(
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

  factory SequenceDelegate.byKind({
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
  I _resolveObject() => listResolver(
    _iterable,
    collectionStyle,
    _tag ?? _defaultTo(_iterable is Set ? setTag : sequenceTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
