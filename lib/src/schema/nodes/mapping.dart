part of 'node.dart';

/// A read-only `YAML` [Map].
///
/// A mapping may allow a `null` key.
final class Mapping extends UnmodifiableMapView<Node, Node> implements Node {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required Set<ResolvedTag> tags,
    required Set<String> anchors,
  }) : _tags = tags,
       _anchors = anchors;

  @override
  final Set<ResolvedTag> _tags;

  @override
  final NodeStyle nodeStyle;

  @override
  final Set<String> _anchors;

  @override
  bool operator ==(Object other) =>
      other is Mapping &&
      _equality.equals(_tags, other._tags) &&
      _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tags, this]);
}
