part of 'object_delegate.dart';

/// A delegate that stores parser information associated with a node when
/// parsing a `YAML` string. This delegate resets its [ParsedProperty] to `null`
/// after it has been resolved.
sealed class NodeDelegate<T> extends ObjectDelegate<T> {
  NodeDelegate({
    required this.indentLevel,
    required this.indent,
    required this.start,
  });

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  int indentLevel;

  /// Indent of the current node being parsed.
  int indent;

  /// Start offset.
  RuneOffset start;

  /// Exclusive end offset.
  RuneOffset? _end;

  /// Node's end offset. Always `null` until a node has been parsed completely.
  RuneOffset? get endOffset => _end;

  /// Resolved tag
  ResolvedTag? _tag;

  /// Anchor
  String? _anchor;

  /// Alias
  String? _alias;

  /// Tracks if a line break was encountered
  bool _hasLineBreak = false;

  /// Whether a line break was encountered while parsing.
  bool get encounteredLineBreak => _hasLineBreak;

  /// Whether any properties are present
  @override
  bool get hasProperty =>
      super.hasProperty || _tag != null || _anchor != null || _alias != null;

  /// Updates the end offset of a node. The [end] must be equal to or greater
  /// than the [start].
  set updateEndOffset(RuneOffset? end) {
    if (end == null) return;

    final startOffset = start.utfOffset;
    final currentOffset = end.utfOffset;

    if (currentOffset < startOffset) {
      throw StateError(
        [
          'Invalid end offset for delegate [$runtimeType] with:',
          'Start offset: $startOffset',
          'Current end offset: ${_end?.utfOffset}',
          'End offset provided: $currentOffset',
        ].join('\n\t'),
      );
    }

    if (_end == null || _end!.utfOffset < currentOffset) {
      _end = end;
    }
  }

  /// Updates a node's properties. Throws an [ArgumentError] if this delegate
  /// has a tag, alias or anchor.
  set updateNodeProperties(ParsedProperty? property) {
    if (property == null || !property.parsedAny) return;

    if (hasProperty) {
      throw ArgumentError(
        'Duplicate node properties provided to a node',
      );
    }

    start = property.structuralOffset ?? property.span.start;
    _hasLineBreak = _hasLineBreak || property.isMultiline;
    _property = property;
  }

  /// Updates whether the node span multiple lines within the source string.
  set hasLineBreak(bool foundLineBreak) =>
      _hasLineBreak = _hasLineBreak || foundLineBreak;

  /// A resolved node.
  T? _resolved;

  /// Whether a node's delegate was resolved.
  bool _isResolved = false;

  @override
  T parsed();

  /// Throws if the end offset was never set. Otherwise, returns the non-null
  /// [endOffset].
  RuneOffset _ensureEndIsSet() {
    if (_end == null) {
      throw StateError(
        '[$runtimeType] with start offset $start has no valid end offset',
      );
    }

    return _end!;
  }

  /// Span for this node.
  RuneSpan nodeSpan() => (start: start, end: _ensureEndIsSet());
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

  /// A dynamic resolver function assigned at runtime by the [DocumentParser].
  final AliasFunction<Ref> refResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) =>
      throw FormatException('An alias cannot have a "${tag.suffix}" kind');

  @override
  Ref _resolveNode() => refResolver(_alias ?? '', _reference, (
    start: start,
    end: _ensureEndIsSet(),
  ));
}
