part of 'yaml_node.dart';

/// A read-only `YAML` [Map]. A mapping may allow a `null` key but it must be
/// wrapped by a [Scalar].
///
/// For equality, it expects at least a Dart [Map]. However, it should be noted
/// that the value of a key will always be a [YamlSourceNode].
///
/// See [DynamicMapping] for a "no-cost" [Mapping] type cast.
final class Mapping extends UnmodifiableMapView<YamlNode, YamlSourceNode?>
    implements YamlSourceNode {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required this.tag,
    required this.anchorOrAlias,
    required this.start,
    required this.end,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchorOrAlias;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  bool operator ==(Object other) =>
      other is Map && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash(this);
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
