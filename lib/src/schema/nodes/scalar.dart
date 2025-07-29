part of 'node.dart';

/// Any value that is not a collection in `YAML`, that is, not a [Sequence] or
/// [Mapping]
base class Scalar<T> extends ParsedYamlNode {
  Scalar(
    this.value, {
    required String content,
    required this.scalarStyle,
    required this.tag,
    required this.anchor,
    required super.start,
    required super.end,
  }) : _content = content;

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// Actual content parsed in YAML.
  final String _content;

  /// A native value represented by the parsed scalar.
  final T? value;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  NodeStyle get nodeStyle => scalarStyle._nodeStyle;

  @override
  bool operator ==(Object other) =>
      other is Scalar && tag == other.tag && _content == other._content;

  @override
  int get hashCode => _equality.hash([tag, _content]);

  @override
  String toString() => '${value?.toString()}';
}

final class IntScalar extends Scalar<int> {
  IntScalar(
    int super.value, {
    required this.radix,
    required super.content,
    required super.scalarStyle,
    required super.tag,
    required super.anchor,
    required super.start,
    required super.end,
  });

  /// Base in number system this scalar belongs to.
  final int radix;
}
