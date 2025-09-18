part of 'yaml_node.dart';

/// A read-only `YAML` [Map] which mirrors an actual Dart [Map] in equality
/// but not shape.
///
/// A mapping may allow a `null` key but it must be  wrapped by a [Scalar].
///
/// See [DynamicMapping] for a "no-cost" [Mapping] type cast.
final class Mapping extends DelegatingMap<YamlNode, YamlSourceNode?>
    with UnmodifiableMapMixin<YamlNode, YamlSourceNode?>
    implements YamlSourceNode {
  /// Creates a [Mapping].
  ///
  /// Intentional. We don't want weird injections from a source with [YamlNode]
  /// keys. Use [DynamicMapping] instead which offers both type safety and
  /// laxity which this class cannot (and should not).
  Mapping._(
    super.base, {
    required this.nodeStyle,
    required this.tag,
    required this.anchor,
    required this.start,
    required this.end,
  });

  /// Creates a [Mapping] after a block/flow map has been fully parsed.
  Mapping.strict(
    Map<YamlSourceNode, YamlSourceNode?> source, {
    required NodeStyle nodeStyle,
    required ResolvedTag? tag,
    required String? anchor,
    required SourceLocation start,
    required SourceLocation end,
  }) : this._(
         source,
         nodeStyle: nodeStyle,
         tag: tag,
         anchor: anchor,
         start: start,
         end: end,
       );

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  bool operator ==(Object other) =>
      other is Map && yamlCollectionEquality.equals(this, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(this);

  @override
  String? get alias => null;

  @override
  void addEntries(Iterable<MapEntry<YamlNode, YamlSourceNode?>> entries) {
    // Copied from Dart internal
    throw UnsupportedError("Cannot modify a parsed mapping");
  }

  @override
  void removeWhere(bool Function(YamlNode key, YamlSourceNode value) test) {
    // Copied from Dart internal
    throw UnsupportedError("Cannot modify a parsed mapping");
  }

  @override
  YamlSourceNode update(
    YamlNode key,
    YamlSourceNode? Function(YamlSourceNode? value) update, {
    YamlSourceNode? Function()? ifAbsent,
  }) {
    // Copied from Dart internal
    throw UnsupportedError("Cannot modify a parsed mapping");
  }

  @override
  void updateAll(
    YamlSourceNode? Function(YamlNode key, YamlSourceNode? value) update,
  ) {
    // Copied from Dart internal
    throw UnsupportedError("Cannot modify a parsed mapping");
  }
}

/// A "no-cost" [Mapping] that allow arbitrary `Dart` values to be used as
/// keys to a [Mapping] without losing any type safety.
///
/// Optionally cast to [Map] of type [T] if you are sure all the keys match the
/// type. Values will still be [YamlSourceNode]s
extension type DynamicMapping<T>(Mapping mapping) implements YamlSourceNode {
  YamlSourceNode? operator [](T key) =>
      mapping[key is YamlNode ? key : DartNode<T>(key)];
}
