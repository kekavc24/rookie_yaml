part of 'yaml_node.dart';

/// A read-only `YAML` [Map] which mirrors an actual Dart [Map] in equality
/// but not shape.
///
/// A mapping may allow a `null` key but it must be  wrapped by a [Scalar].
///
/// See [DynamicMapping] for a "no-cost" [Mapping] type cast.
///
/// {@category intro}
/// {@category yaml_nodes}
final class Mapping extends UnmodifiableMapView<YamlSourceNode, YamlSourceNode?>
    implements YamlSourceNode {
  /// Creates a [Mapping].
  ///
  /// Intentional. We don't want weird injections from a source with [YamlNode]
  /// keys. Use [DynamicMapping] instead which offers both type safety and
  /// laxity which this class cannot (and should not).
  Mapping(
    super.base, {
    required this.nodeStyle,
    required this.tag,
    required this.anchor,
    required this.nodeSpan,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  final RuneSpan nodeSpan;

  @override
  bool operator ==(Object other) => yamlCollectionEquality.equals(this, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(this);

  @override
  String? get alias => null;
}

/// A "no-cost" [Mapping] that allow arbitrary `Dart` values to be used as
/// keys to a [Mapping] without losing any type safety.
///
/// Optionally cast to [Map] of type [T] if you are sure all the keys match the
/// type. Values will still be [YamlSourceNode]s
///
/// {@category yaml_nodes}
extension type DynamicMapping<T>(Mapping mapping) implements YamlSourceNode {
  YamlSourceNode? operator [](T key) =>
      mapping[key is YamlNode ? key : DartNode<T>(key)];
}
