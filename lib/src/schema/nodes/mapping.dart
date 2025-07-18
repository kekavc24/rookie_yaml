part of 'node.dart';

/// A read-only `YAML` [Map].
///
/// A mapping may allow a `null` key but it must be wrapped by a [Scalar].
final class Mapping extends UnmodifiableMapView<Node, Node> with Node {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required ResolvedTag? tag,
    required String? anchor,
  }) : _tag = tag,
       _anchor = anchor;

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? _tag;

  @override
  final String? _anchor;

  @override
  bool operator ==(Object other) =>
      other is Mapping && _tag == other._tag && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tag, this]);
}
