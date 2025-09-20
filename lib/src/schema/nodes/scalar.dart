part of 'yaml_node.dart';

/// Any value that is not a [Sequence] or [Mapping].
///
/// For equality, a scalar uses the inferred value [T] for maximum
/// compatibility with `Dart` objects that can be scalars.
///
/// {@category yaml_nodes}
final class Scalar<T> extends YamlSourceNode {
  Scalar(
    this._type, {
    required this.scalarStyle,
    required this.tag,
    required this.anchor,
    required this.start,
    required this.end,
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
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  NodeStyle get nodeStyle => scalarStyle.nodeStyle;

  @override
  bool operator ==(Object other) => other == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => _type.toString();
}
