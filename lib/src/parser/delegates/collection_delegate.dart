part of 'parser_delegate.dart';

/// Returns a `null` wrapped in a [ScalarDelegate].
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

/// Returns `true` if a [tag] is a [Mapping] tag.
bool _isMapTag(TagShorthand tag) =>
    tag != sequenceTag && !scalarTags.contains(tag);

/// Returns a default [NodeTag] with the [yamlGlobalTag] as its prefix. [tag]
/// must be a secondary tag.
NodeTag _defaultTo(TagShorthand tag) => NodeTag(yamlGlobalTag, tag);

/// A collection delegate
abstract base class CollectionDelegate<R, T, I> extends ParserDelegate<T> {
  CollectionDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Collection style
  final NodeStyle collectionStyle;

  /// Returns `true` if the collection is empty
  bool get isEmpty;

  /// Buffers input [I] to a collection
  R accept(I input);
}

/// A delegate that resolves to a [Sequence]
final class SequenceDelegate<I, Seq extends List<I>>
    extends CollectionDelegate<void, Seq, I> {
  SequenceDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.listResolver,
  });

  /// Actual list
  final _list = <I>[];

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final ListFunction<I, Seq> listResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (suffix == mappingTag || scalarTags.contains(suffix)) {
      throw FormatException('A sequence cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, sequenceTag);
  }

  @override
  Seq _resolver() => listResolver(
    _list,
    collectionStyle,
    _tag ?? _defaultTo(sequenceTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );

  @override
  void accept(I input) => _list.add(input);

  @override
  bool get isEmpty => _list.isEmpty;
}

/// A delegate that resolves to a [Mapping]
final class MappingDelegate<I, M extends Map<I, I?>>
    extends CollectionDelegate<bool, M, MapInput<I>> {
  MappingDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.mapResolver,
  });

  /// A map that is resolved as a key is added
  final _map = <I, I?>{};

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final MapFunction<I, M> mapResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (!_isMapTag(suffix)) {
      throw FormatException('A mapping cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, mappingTag);
  }

  @override
  M _resolver() => mapResolver(
    _map,
    collectionStyle,
    _tag ?? _defaultTo(mappingTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );

  @override
  bool accept(MapInput<I> input) {
    final (key, value) = input;
    if (_map.containsKey(key)) return false;
    _map[key] = value;
    return true;
  }

  @override
  bool get isEmpty => _map.isEmpty;
}
