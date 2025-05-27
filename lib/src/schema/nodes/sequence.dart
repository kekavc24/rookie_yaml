part of 'node.dart';

/// A read-only `YAML` [List]
final class Sequence extends UnmodifiableListView<Node> implements Node {
  Sequence(
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
      other is Sequence &&
      _equality.equals(_tags, other._tags) &&
      _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tags, this]);
}
