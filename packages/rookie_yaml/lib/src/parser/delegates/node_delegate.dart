part of 'object_delegate.dart';

/// A delegate that stores parser information associated with a node when
/// parsing a `YAML` string. This delegate resets its [ParsedProperty] to `null`
/// after it has been resolved.
sealed class NodeDelegate<T> extends ObjectDelegate<T> {
  NodeDelegate({
    required this.indentLevel,
    required this.indent,
    required RuneOffset start,
  }) : nodeSpan = YamlSourceSpan(start);

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  int indentLevel;

  /// Indent of the current node being parsed.
  int indent;

  /// Span for the node represented by this delegate.
  final YamlSourceSpan nodeSpan;

  /// Resolved tag
  ResolvedTag? _tag;

  /// Anchor
  String? _anchor;

  /// Alias
  String? _alias;

  /// Whether a line break was encountered while parsing.
  bool encounteredLineBreak() {
    final start =
        nodeSpan.structuralOffset ??
        nodeSpan.propertySpan?.start ??
        nodeSpan.nodeStart;

    return start.lineIndex != nodeSpan.nodeEnd.lineIndex;
  }

  /// Whether any properties are present
  @override
  bool get hasProperty =>
      super.hasProperty || _tag != null || _anchor != null || _alias != null;

  /// Updates a node's properties. Throws an [ArgumentError] if this delegate
  /// has a tag, alias or anchor.
  set updateNodeProperties(ParsedProperty? property) {
    if (property == null) return;

    if (hasProperty) {
      throw ArgumentError(
        'Duplicate node properties provided to a node',
      );
    }

    nodeSpan
      ..structuralOffset = property.structuralOffset
      ..propertySpan = property.span;
    _property = property;
  }

  /// A resolved node.
  T? _resolved;

  /// Whether a node's delegate was resolved.
  bool _isResolved = false;

  @override
  T parsed();
}

/// Represents a delegate that resolves to an [AliasNode]
final class AliasDelegate<Ref> extends NodeDelegate<Ref>
    with _ResolvingCache<Ref> {
  AliasDelegate(
    this._reference, {
    required super.indentLevel,
    required super.indent,
    required super.start,
    required this.refResolver,
  });

  /// Object referenced as an alias
  final Ref _reference;

  /// A dynamic resolver function assigned at runtime by the parser.
  final AliasFunction<Ref> refResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) =>
      throw FormatException('An alias cannot have a "${tag.suffix}" kind');

  @override
  Ref _resolveNode() => refResolver(_alias ?? '', _reference, nodeSpan);
}
