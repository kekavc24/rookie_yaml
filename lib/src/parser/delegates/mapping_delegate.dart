part of 'parser_delegate.dart';

/// A delegate that buffers to a map-like structure.
sealed class MapLikeDelegate<E, T> extends ParserDelegate<T> {
  /// Create a delegate that resolves a map-like structure.
  MapLikeDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// [NodeStyle] for the map-like node.
  final NodeStyle collectionStyle;

  /// Adds a [key]-[value] pair.
  bool accept(E key, E? value);
}

/// A delegate that directly maps a YAML map to an object [T]. No intermediate
/// [Map] is constructed. Both the key and value are presented at the same time
/// after the complete entry has been parsed. You must override the `parsed`
/// method.
///
/// This class is a mirror of the intermediate object created before the
/// parser strips any styles and properties. This is the abstraction the parser
/// sees and not your object. All properties from the super class that this
/// class needs will be provided by the parser.
///
/// Additionally, it has been forced to accept a nullable [Object] as a
/// key-value pair. All subclasses need to guarantee their own runtime safety in
/// case the shape of the YAML map doesn't match the desired object.
abstract base class MapToObjectDelegate<T> extends MapLikeDelegate<Object?, T> {
  MapToObjectDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// Adds a [key]-[value] pair.
  ///
  /// Returning `false` makes the parser assume this is a duplicate key. Prefer
  /// returning `true` or throwing.
  @override
  bool accept(Object? key, Object? value);
}

/// A delegate that resolves to a [Mapping].
final class MappingDelegate<I> extends MapLikeDelegate<I, I>
    with _ResolvingCache<I> {
  MappingDelegate({
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

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final MapFunction<I> mapResolver;

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

  /// Whether the map backing this delegate has no entries.
  bool get isEmpty => _map.isEmpty;

  @override
  I _resolveObject() => mapResolver(
    _map,
    collectionStyle,
    _tag ?? _defaultTo(mappingTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
