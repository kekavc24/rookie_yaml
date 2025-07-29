part of 'node.dart';

/// A read-only `YAML` [Map].
///
/// A mapping may allow a `null` key but it must be wrapped by a [Scalar].
final class Mapping extends UnmodifiableMapView<ParsedYamlNode, ParsedYamlNode?>
    implements ParsedYamlNode {
  Mapping(
    super.source, {
    required this.nodeStyle,
    required this.tag,
    required this.anchor,
    required this.start,
    required this.end,
  });

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
      other is Mapping && tag == other.tag && _equality.equals(this, other);

  @override
  int get hashCode => _equality.hash([tag, this]);

  @override
  ParsedYamlNode asDumpable() => this;
}
