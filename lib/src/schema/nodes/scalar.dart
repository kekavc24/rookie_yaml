part of 'node.dart';

/// Any value that is not a [Sequence] or [Mapping]
final class Scalar<T> extends ParsedYamlNode {
  Scalar(
    this._type, {
    required this.scalarStyle,
    required this.tag,
    required this.anchor,
    required super.start,
    required super.end,
  });

  /// Type inferred from the scalar's content
  final ScalarValue<T> _type;

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// A native value represented by the parsed scalar.
  T get value => _type.value;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  NodeStyle get nodeStyle => scalarStyle._nodeStyle;

  @override
  bool operator ==(Object other) =>
      other is Scalar<T> && tag == other.tag && value == other.value;

  @override
  int get hashCode => _equality.hash([tag, value]);

  @override
  String toString() => _type.toString();
}
