part of 'node.dart';

/// Any value that is not a collection in `YAML`, that is, not a [Sequence] or
/// [Mapping]
base class Scalar<T> extends Node {
  Scalar(
    this.value, {
    required String content,
    required this.scalarStyle,
    required super.anchors,
    required super.tags,
  }) : _content = content,
       super(nodeStyle: scalarStyle._nodeStyle);

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// Actual content parsed in YAML.
  final String _content;

  /// A native value represented by the parsed scalar.
  final T? value;

  @override
  bool operator ==(Object other) =>
      other is Scalar &&
      _equality.equals(_tags, other._tags) &&
      _content == other._content;

  @override
  int get hashCode => _equality.hash([_tags, _content]);

  @override
  String toString() => '${value?.toString()}';
}

final class IntScalar extends Scalar<int> {
  IntScalar(
    int super.value, {
    required this.radix,
    required super.anchors,
    required super.content,
    required super.scalarStyle,
    required super.tags,
  });

  /// Base in number system this scalar belongs to.
  final int radix;
}
