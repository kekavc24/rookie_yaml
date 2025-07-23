part of 'node.dart';

/// Any value that is not a collection in `YAML`, that is, not a [Sequence] or
/// [Mapping]
base class Scalar<T> extends ParsedYamlNode {
  Scalar(
    this.value, {
    required String content,
    required this.scalarStyle,
    required ResolvedTag? tag,
    required String? anchor,
  }) : _content = content,
       _tag = tag,
       _anchor = anchor;

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// Actual content parsed in YAML.
  final String _content;

  /// A native value represented by the parsed scalar.
  final T? value;

  @override
  final ResolvedTag? _tag;

  @override
  final String? _anchor;

  @override
  NodeStyle get nodeStyle => scalarStyle._nodeStyle;

  @override
  bool operator ==(Object other) =>
      other is Scalar && _tag == other._tag && _content == other._content;

  @override
  int get hashCode => _equality.hash([_tag, _content]);

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
  });

  /// Base in number system this scalar belongs to.
  final int radix;
}
