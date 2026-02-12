part of 'object_delegate.dart';

void throwIfNotMapTag(TagShorthand suffix) => throwOnTagMismatch(
  suffix,
  (t) => isYamlScalarTag(suffix) || suffix == sequenceTag,
  'mapping',
);

/// A delegate that behaves like a map.
mixin _MapDelegate<K, V> {
  /// Adds a [key]-[value] pair.
  ///
  /// Returning `false` makes the parser assume this is a duplicate key. Prefer
  /// returning `true` or throwing.
  bool accept(K key, V? value);
}

/// A delegate that directly maps a YAML map to an object [T] and accepts an
/// object key [K] and object value [V]. No intermediate [Map] is constructed.
/// Both the key and value are presented at the same time after the complete
/// entry has been parsed. You must override the `parsed` method.
///
/// {@category mapping_to_obj}
abstract base class MappingToObject<K, V, T> = ObjectDelegate<T>
    with _MapDelegate<K, V>;

/// A delegate that buffers to a map-like structure.
sealed class MapLikeDelegate<K, V, T> extends NodeDelegate<T>
    with _MapDelegate<K, V> {
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
    MappingToObject<K, V, T> delegate, {
    required NodeStyle collectionStyle,
    required int indentLevel,
    required int indent,
    required RuneOffset start,
    required AfterCollection<T> afterMapping,
  }) => _BoxedMap(
    delegate,
    collectionStyle: collectionStyle,
    indentLevel: indentLevel,
    indent: indent,
    start: start,
    afterMapping: afterMapping,
  );
}

/// Wraps an external [MappingToObject] and allows it to behave like a
/// [MapLikeDelegate] that the parser can interact with.
final class _BoxedMap<K, V, T> extends MapLikeDelegate<K, V, T>
    with _BoxedCallOnce<T> {
  _BoxedMap(
    this._delegate, {
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.afterMapping,
  });

  /// Delegate with external map implementation.
  final MappingToObject<K, V, T> _delegate;

  /// Called when the sequence is complete.
  final AfterCollection<T> afterMapping;

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
  T parsed() => _callOnce(
    _delegate.parsed(),
    ifNotCalled: (type) => afterMapping(
      collectionStyle,
      type,
      _anchor,
      nodeSpan(),
    ),
  );

  @override
  bool accept(K key, V? value) => _delegate.accept(key, value);
}

/// A delegate that resolves to a [Mapping] or [Map].
final class GenericMap<I> extends MapLikeDelegate<I, I, I>
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
    throwIfNotMapTag(tag.suffix);
    return overrideNonSpecific(tag, mappingTag);
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
