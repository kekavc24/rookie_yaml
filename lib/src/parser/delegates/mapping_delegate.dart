part of 'parser_delegate.dart';

/// A delegate that resolves to a [Mapping]
final class MappingDelegate<I, M extends Map<I, I?>> extends ParserDelegate<M> {
  MappingDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.mapResolver,
  });

  final NodeStyle collectionStyle;

  /// Map backing this delegate
  final _map = <I, I?>{};

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final MapFunction<I, M> mapResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (isYamlScalarTag(suffix) || isYamlSequenceTag(suffix)) {
      throw FormatException('A mapping cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, mappingTag);
  }

  /// Adds an [key]-[value] pair only if the [key] is absent in the map and
  /// returns `true`. Otherwise, returns false and ignores the entry.
  bool accept(I key, I? value) {
    if (_map.containsKey(key)) return false;
    _map[key] = value;
    return true;
  }

  /// Whether the map backing this delegate has no entries.
  bool get isEmpty => _map.isEmpty;

  @override
  M _resolver() => mapResolver(
    _map,
    collectionStyle,
    _tag ?? _defaultTo(mappingTag),
    _anchor,
    (start: start, end: _ensureEndIsSet()),
  );
}
