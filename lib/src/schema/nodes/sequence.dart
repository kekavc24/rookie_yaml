part of 'node.dart';

/// A read-only `YAML` [List]
final class Sequence extends UnmodifiableListView<ParsedYamlNode>
    implements ParsedYamlNode {
  Sequence(
    super.source, {
    required this.nodeStyle,
    required this.tag,
    required this.anchor,
  });

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  bool operator ==(Object other) =>
      other is Sequence && tag == other.tag && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([tag, this]);

  @override
  ParsedYamlNode asDumpable() => this;
}
