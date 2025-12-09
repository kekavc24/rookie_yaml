import 'dart:collection';

import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'mapping_delegate.dart';
part 'scalar_delegate.dart';
part 'sequence_delegate.dart';

/// Creates a default [NodeTag] with the [yamlGlobalTag] as its prefix. [tag]
/// must be a secondary tag.
NodeTag _defaultTo(TagShorthand tag) => NodeTag(yamlGlobalTag, tag);

/// Overrides the [current] node tag to a [kindDefault] if [current] is
/// non-specific.
NodeTag _overrideNonSpecific(NodeTag current, TagShorthand kindDefault) {
  if (!current.suffix.isNonSpecific) return current;

  // No need to override if the non-specific tag has a global tag prefix
  return current.resolvedTag is GlobalTag ? current : _defaultTo(kindDefault);
}

/// A constructor for any object that delegates its builder to a
/// [ParserDelegate].
typedef YamlObjectBuilder<S, I, O> =
    O Function(
      I object,
      S objectStyle,
      ResolvedTag? tag,
      String? anchor,
      RuneSpan nodeSpan,
    );

/// A constructor for collection-like builders.
typedef YamlCollectionBuilder<I, O> = YamlObjectBuilder<NodeStyle, I, O>;

/// A builder function for [List] or [Sequence].
typedef ListFunction<I, C extends Iterable<I>> =
    YamlCollectionBuilder<Iterable<I>, C>;

/// A builder function for [Map] or [Mapping]
typedef MapFunction<I, C extends Map<I, I?>> =
    YamlCollectionBuilder<Map<I, I?>, C>;

/// A builder function for a scalar or a Dart built-in type that is not a [Map]
/// or [List]
typedef ScalarFunction<T> = YamlObjectBuilder<ScalarStyle, ScalarValue, T>;

/// A delegate that stores parser information when parsing nodes of the `YAML`
/// tree.
abstract base class ParserDelegate<T> {
  ParserDelegate({
    required this.indentLevel,
    required this.indent,
    required this.start,
  });

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  int indentLevel;

  /// Indent of the current node being parsed
  int indent;

  /// Starting offset.
  RuneOffset start;

  /// Exclusive
  RuneOffset? _end;

  /// End offset
  RuneOffset? get endOffset => _end;

  ParsedProperty? _property;

  /// Updates the end offset of a node. The [end] must be equal to or greater
  /// than the [start]
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

  /// Updates a node's properties. Throws an [ArgumentError] if this delegate
  /// has a tag, alias or anchor.
  set updateNodeProperties(ParsedProperty? property) {
    if (property == null || !property.parsedAny) return;

    if (hasProperties) {
      throw ArgumentError(
        'Duplicate node properties provided to a node',
      );
    }

    start = property.span.start;
    _hasLineBreak = _hasLineBreak || property.isMultiline;
    _property = property;
  }

  /// Validates the parsed [_tag].
  NodeTag _checkResolvedTag(NodeTag tag);

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
  bool get hasProperties =>
      _property != null || _tag != null || _anchor != null || _alias != null;

  ParsedProperty? get property => _property;

  set hasLineBreak(bool foundLineBreak) =>
      _hasLineBreak = _hasLineBreak || foundLineBreak;

  /// Validates if parsed properties are valid only when [parsed] is called.
  void _resolveProperties() {
    switch (_property) {
      case Alias(:final alias):
        _alias = alias;

      case NodeProperty(:final anchor, :final tag):
        {
          switch (tag) {
            case TypeResolverTag(:final resolvedTag):
              {
                /// Cannot override the captured tag; only validate it.
                /// Non-specific tags not allowed in cannot be resolved to a
                /// type other than YAML defaults.
                _checkResolvedTag(resolvedTag);
                _tag = tag;
              }

            /// Node tags with only non-specific tags and no global tag prefix
            /// will default to str, mapping or seq based on its schema kind.
            case NodeTag nodeTag:
              _tag = _checkResolvedTag(nodeTag);

            default:
              _tag = tag;
          }

          _anchor = anchor;
        }

      default:
        return;
    }

    _property = null;
  }

  /// A resolved node.
  T? _resolved;

  /// Whether a node's delegate was resolved.
  bool _isResolved = false;

  /// Returns the object's [T] whose source information this delegate is
  /// assigned to track.
  T parsed() {
    if (!_isResolved) {
      _resolveProperties();
      _resolved ??= _resolver();
      _isResolved = true;
    }

    return _resolved as T;
  }

  /// Resolves the actual object [T].
  T _resolver();
}

/// A builder function for an [Alias] or any referenced Dart-built in type.
typedef AliasFunction<Ref> =
    Ref Function(String alias, Ref reference, RuneSpan nodeSpan);

/// Represents a delegate that resolves to an [AliasNode]
final class AliasDelegate<Ref> extends ParserDelegate<Ref> {
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
  Ref _resolver() => refResolver(_alias ?? '', _reference, (
    start: start,
    end: _ensureEndIsSet(),
  ));
}
