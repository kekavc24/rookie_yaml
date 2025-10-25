import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'collection_delegate.dart';
part 'scalar_delegate.dart';

/// Overrides the [current] node tag to a [kindDefault] if [current] is
/// non-specific.
NodeTag _overrideNonSpecific(NodeTag current, TagShorthand kindDefault) {
  if (!current.suffix.isNonSpecific) return current;

  // No need to override if the non-specific tag has a global tag prefix
  return current.resolvedTag is GlobalTag ? current : _defaultTo(kindDefault);
}

/// A delegate that stores parser information when parsing nodes of the `YAML`
/// tree.
abstract interface class ParserDelegate<T> {
  ParserDelegate({
    required this.indentLevel,
    required this.indent,
    required this.start,
    this.parent,
  });

  /// Level in the `YAML` tree. Must be equal or less than [indent].
  final int indentLevel;

  /// Indent of the current node being parsed
  int indent;

  /// Starting offset.
  final RuneOffset start;

  /// Exclusive
  RuneOffset? _end;

  RuneOffset? get endOffset => _end;

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

  RuneOffset _ensureEndIsSet() {
    if (_end == null) {
      throw StateError(
        '[$runtimeType] with start offset $start has no valid end offset',
      );
    }

    return _end!;
  }

  ///
  set updateNodeProperties(ParsedProperty property) {
    if (!property.parsedAny) return;

    if (_tag != null || _anchor != null || _alias != null) {
      throw ArgumentError(
        'Duplicate node properties provided to a node',
      );
    }

    switch (property) {
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
  }

  /// Validates the parsed [_tag].
  NodeTag _checkResolvedTag(NodeTag tag);

  /// Resolved tag
  ResolvedTag? _tag;

  /// Anchor
  String? _anchor;

  /// Alias
  String? _alias;

  /// Delegate's parent
  ParserDelegate? parent;

  /// Returns `true` if the node delegated to this parser is the root of the
  /// [YamlDocument]
  bool get isRootDelegate => parent == null;

  /// Tracks if a line break was encountered
  bool _hasLineBreak = false;

  /// Returns `true` if a line break was encountered while parsing.
  bool get encounteredLineBreak => _hasLineBreak;

  set hasLineBreak(bool foundLineBreak) =>
      _hasLineBreak = _hasLineBreak || foundLineBreak;

  /// A resolved node.
  T? _resolved;

  /// Returns the object's [T] whose source information this delegate is
  /// assigned to track.
  T parsed() {
    _resolved ??= _resolver();
    return _resolved as T;
  }

  /// Resolves the actual object [T].
  T _resolver();
}

typedef AliasFunction<Obj, Ref> =
    Obj Function(String alias, Ref reference, RuneSpan nodeSpan);

/// Represents a delegate that resolves to an [AliasNode]
final class AliasDelegate<Obj, Ref> extends ParserDelegate<Obj> {
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
  final AliasFunction<Obj, Ref> refResolver;

  @override
  NodeTag _checkResolvedTag(NodeTag tag) =>
      throw FormatException('An alias cannot have a "${tag.suffix}" kind');

  @override
  Obj _resolver() => refResolver(_alias ?? '', _reference, (
    start: start,
    end: _ensureEndIsSet(),
  ));
}
