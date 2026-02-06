part of 'object_delegate.dart';

/// A delegate that behaves like a map.
mixin _MapDelegate<E> {
  /// Adds a [key]-[value] pair.
  ///
  /// Returning `false` makes the parser assume this is a duplicate key. Prefer
  /// returning `true` or throwing.
  bool accept(E key, E? value);
}

/// A delegate that directly maps a YAML map to an object [T]. No intermediate
/// [Map] is constructed. Both the key and value are presented at the same time
/// after the complete entry has been parsed. You must override the `parsed`
/// method.
///
/// Additionally, it has been forced to accept a nullable [Object] as a
/// key-value pair. All subclasses need to guarantee their own runtime safety in
/// case the shape of the YAML map doesn't match the desired object.
///
/// {@category mapping_to_obj}
abstract base class MappingToObject<T> = ObjectDelegate<T>
    with _MapDelegate<Object?>;

/// A delegate that buffers to a map-like structure.
sealed class MapLikeDelegate<E, T> extends NodeDelegate<T>
    with _MapDelegate<E> {
  MapLikeDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// [NodeStyle] for the map-like node.
  final NodeStyle collectionStyle;

  /// Creates a [MapLikeDelegate] for an external map linked to a tag.
  factory MapLikeDelegate.boxed(
    MappingToObject<T> delegate, {
    required NodeStyle collectionStyle,
    required int indentLevel,
    required int indent,
    required RuneOffset start,
  }) =>
      _BoxedMap(
            delegate,
            collectionStyle: collectionStyle,
            indentLevel: indentLevel,
            indent: indent,
            start: start,
          )
          as MapLikeDelegate<E, T>;
}

/// Wraps an external [MappingToObject] and allows it to behave like a
/// [MapLikeDelegate] that the parser can interact with.
final class _BoxedMap<T> extends MapLikeDelegate<Object?, T> {
  _BoxedMap(
    this._delegate, {
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Delegate with external map implementation.
  final MappingToObject<T> _delegate;

  @override
  set updateNodeProperties(ParsedProperty? property) {
    super.updateNodeProperties = property;
    _delegate._property = property;
  }

  @override
  T parsed() => _delegate.parsed();

  @override
  bool accept(Object? key, Object? value) => _delegate.accept(key, value);
}

/// A delegate that resolves to a [Mapping] or [Map].
final class GenericMap<I> extends MapLikeDelegate<I, I>
    with _ResolvingCache<I> {
  GenericMap({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.mapResolver,
  });

  /// Map backing this delegate
  final _map = LinkedHashMap<I, I?>(
    equals: yamlCollectionEquality.equals,
    hashCode: yamlCollectionEquality.hash,
  );

  /// A dynamic resolver function assigned at runtime by the parser.
  final YamlCollectionBuilder<I> mapResolver;

  @override
  NodeTag<dynamic> _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlScalarTag(suffix) || suffix == sequenceTag) {
      throw FormatException('A mapping cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, mappingTag);
  }

  /// Adds an [key]-[value] pair only if the [key] is absent in the map and
  /// returns `true`. Otherwise, returns false and ignores the entry.
  @override
  bool accept(I key, I? value) {
    if (_map.containsKey(key)) return false;
    _map[key] = value;
    return true;
  }

  @override
  I _resolveNode() => mapResolver(
    _map,
    collectionStyle,
    _tag ?? _defaultTo(mappingTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
