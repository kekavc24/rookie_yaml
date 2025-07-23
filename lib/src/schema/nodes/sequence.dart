part of 'node.dart';

/// A read-only `YAML` [List]
final class Sequence extends UnmodifiableListView<ParsedYamlNode>
    implements ParsedYamlNode {
  Sequence(
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
      other is Sequence && _tag == other._tag && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([_tag, this]);

  @override
  ParsedYamlNode asDumpable() => this;
}
