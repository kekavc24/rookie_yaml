import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

export '../dumping/dumper_utils.dart' show CommentStyle;
export '../dumping/list_dumper.dart' show IterableEntry, IterableDumper;
export '../dumping/map_dumper.dart' show Entry, MapDumper;

part 'initialize_collections.dart';

typedef OnProperties =
    void Function(
      Iterable<MapEntry<TagHandle, GlobalTag>> tags,
      Iterable<(String anchor, Object? object)> anchors,
    );

final class ObjectDumper {
  ObjectDumper._(this.unpackAliases, this.commentDumper);

  /// Dumps comments associated with any node.
  final CommentDumper commentDumper;

  /// Whether aliases should be unpacked and dumped as the actual node.
  final bool unpackAliases;

  /// Dumps [Iterable]s.
  late final IterableDumper iterableDumper;

  /// Dumps [Map]s.
  late final MapDumper mapDumper;

  /// Dumps any object that is not a [Map] or [Iterable].
  late final ScalarDumper scalarDumper;

  /// Tracks the global tags associated with a specific tag handle.
  final _globalTags = <TagHandle, GlobalTag>{};

  /// Tracks the anchors in case a
  final _anchors = <String, ConcreteNode<Object?>>{};

  factory ObjectDumper.of({
    bool unpackAliases = false,
    CommentStyle commentStyle = CommentStyle.block,
    int commentStepSize = 0,
    ScalarStyle scalarStyle = ScalarStyle.plain,
    bool forceScalarsInline = false,
    bool flowIterableInline = false,
    bool flowMapInline = false,
    NodeStyle mapStyle = NodeStyle.block,
    NodeStyle iterableStyle = NodeStyle.block,
  }) {
    final commentDumper = CommentDumper(commentStyle, commentStepSize);
    final dumper = ObjectDumper._(unpackAliases, commentDumper);
    final onObject = dumper._dumpable;
    final validator = dumper._validateObject;

    final scalarDumper = ScalarDumper.fineGrained(
      replaceEmpty: true,
      onScalar: onObject,
      pushProperties: validator,
      style: scalarStyle,
      forceInline: forceScalarsInline,
    );

    final (iterable, map) = _initializeCollections(
      onObject: onObject,
      validator: validator,
      scalar: scalarDumper,
      comments: commentDumper,
      flowIterableInline: flowIterableInline,
      flowMapInline: flowMapInline,
      sequenceStyle: iterableStyle,
      mappingStyle: mapStyle,
    );

    return dumper
      ..scalarDumper = scalarDumper
      ..iterableDumper = iterable
      ..mapDumper = map;
  }

  void _reset() {
    _anchors.clear();
    _globalTags.clear();
  }

  /// Validates an [object]'s tag and tracks its [anchor] if present.
  String? _validateObject(
    ResolvedTag? objectTag,
    String? anchor,
    ConcreteNode<Object?> object,
  ) {
    if (anchor != null) {
      _anchors[anchor] = object;
    }

    if (objectTag == null) return null;
    final (:verbatim, :globalTag, :tag) = resolvedTagInfo(objectTag);

    // Cannot have verbatim and global/local tag.
    if (verbatim != null) return verbatim;

    var namedHasGlobal = false;

    if (globalTag != null) {
      final globalHandle = globalTag.tagHandle;

      // A global tag is like a anchor URI for a local tag's handle which acts
      // as the alias.
      if (globalHandle != tag?.tagHandle) {
        throw FormatException(
          '''
Global tag handle doesn't match local tag handle.
  Global tag handle: ${globalTag.tagHandle}
  Local tag handle: ${tag?.tagHandle}
''',
        );
      }

      final existing = _globalTags.putIfAbsent(globalHandle, () => globalTag);

      // Multiple global tags cannot alias the same handle multiple times in the
      // same document.
      if (existing != globalTag) {
        throw FormatException(
          '''
A global tag with the current tag handle already exists.
  Existing: $existing
  Update: $globalTag
''',
        );
      }

      namedHasGlobal = true;
    }

    if (tag == null) return null;

    // Ensure our named handle has a global tag.
    if (tag.tagHandle.handleVariant == TagHandleVariant.secondary &&
        !namedHasGlobal) {
      throw FormatException(
        'The named local tag "$tag" has no global tag for its named handle',
      );
    }

    return tag.toString();
  }

  /// Attempts to convert the [object] to a [DumpableNode]. Unpacks an [Alias]
  /// and return its true reference if [unpackAliases] is `true`.
  DumpableNode<Object?> _dumpable(Object? object) {
    final dumpable = dumpableObject(object, unpackAnchor: unpackAliases);

    if (dumpable is DumpableAsAlias) {
      if (_anchors[dumpable.alias] case ConcreteNode<Object?> anchor) {
        return unpackAliases ? anchor : dumpable;
      }

      throw ArgumentError('The alias "$dumpable" has no corresponding anchor');
    }

    return dumpable;
  }

  /// Writes any document directives present to the [buffer].
  void _writeDocDirectives(
    StringBuffer buffer, {
    required bool includeYamlDirective,
    required Iterable<Directive>? docDirectives,
    required OnProperties? onProperties,
  }) {
    // The YAML global tag is always implied.
    bool dropGlobalYamlTag(GlobalTag? globalTag) => globalTag == yamlGlobalTag;

    /// Drops a global [directive] that [matches] the predicate.
    bool dropDirective(
      Directive directive, [
      bool Function(GlobalTag tag)? matches,
    ]) => directive is GlobalTag && (matches ?? dropGlobalYamlTag)(directive);

    if (includeYamlDirective) {
      buffer.writeln(parserVersion);
    }

    var directives = (docDirectives ?? Iterable<Directive>.empty())
      ..whereNot(dropDirective);

    if (onProperties != null) {
      onProperties(
        _globalTags.entries,
        _anchors.entries.map((e) => (e.key, e.value.dumpable)),
      );
    } else {
      // The YAML global tag is always implied.
      if (dropGlobalYamlTag(_globalTags[defaultYamlHandle])) {
        _globalTags.remove(defaultYamlHandle);
      }

      // Global tags before other external directives.
      directives = _globalTags.values.cast<Directive>().followedBy(
        directives.whereNot(
          (e) => dropDirective(
            e,
            (g) => _globalTags.containsKey(g.tagHandle),
          ),
        ),
      );
    }

    for (final directive in directives) {
      buffer.writeln(directive);
    }

    // In case any directives were present
    if (buffer.isNotEmpty) {
      buffer.writeln(DocumentMarker.directiveEnd.indicator);
    }
  }

  /// Applies any comments to the root object.
  String _applyCommentsIfAny(
    String object, {
    required List<String> comments,
    required int indent,
    required bool forceCommentsAsBlock,
    required int? offsetFromMargin,
  }) {
    if (comments.isEmpty) return object;
    return commentDumper.applyComments(
      object,
      comments: comments,
      forceBlock: forceCommentsAsBlock,
      indent: indent,
      offsetFromMargin:
          forceCommentsAsBlock || commentDumper.style == CommentStyle.block
          ? (offsetFromMargin ?? 0)
          : (offsetFromMargin ??
                switch (object.lastIndexOf('\n')) {
                  -1 => object.length + indent,
                  int offset => object.length - offset,
                }),
    );
  }

  /// Dumps an [object] with the specified [indent].
  ///
  /// If [includeYamlDirective] is `true`, a YAML directive will be included.
  /// The version directive represents the YAML version this dumper adheres to.
  /// In most cases, this matches the YAML version supported by
  /// `package:rookie_yaml`. See [parserVersion].
  ///
  /// Any global tags extracted while dumping the [object] are included as
  /// directives before the [object]'s YAML content. If [objectProperties] is
  /// provided, they will be omitted from the object string.
  ///
  /// Any additional [directives] provided will be dumped. However, any
  /// [GlobalTag]s found in the [object] take precedence over those present in
  /// [directives].
  String dump(
    Object? object, {
    int indent = 0,
    bool includeYamlDirective = false,
    Iterable<Directive>? directives,
    OnProperties? objectProperties,
    bool includeDocumendEnd = false,
  }) {
    _reset();
    final dumpable = _dumpable(object);

    var dumpedObject = '';
    var commentsAsBlock = true;
    int? offsetFromMargin;

    switch (dumpable.dumpable) {
      case Iterable<Object?> iterable:
        {
          final (
            :applyTrailingComments,
            :node,
            preferExplicit: _,
          ) = iterableDumper.dumpIterableLike(
            iterable,
            expand: (e) => e.map((e) => (e, null)),
            indent: indent,
            anchor: dumpable.anchor,
            tag: dumpable.tag,
          );

          commentsAsBlock = !applyTrailingComments;
          dumpedObject = node;
        }

      case Map<Object?, Object?> map:
        {
          final (
            :applyTrailingComments,
            :node,
            preferExplicit: _,
          ) = mapDumper.dumpMapLike(
            map,
            expand: (m) => m.entries.map((e) => (e, null)),
            indent: indent,
            anchor: dumpable.anchor,
            tag: dumpable.tag,
          );

          commentsAsBlock = !applyTrailingComments;
          dumpedObject = node;
        }

      default:
        {
          final (isMultiline: _, :node, :tentativeOffsetFromMargin) =
              scalarDumper.dump(dumpable, indent: indent, style: null);

          commentsAsBlock =
              scalarDumper.defaultStyle.nodeStyle == NodeStyle.block;
          offsetFromMargin = tentativeOffsetFromMargin;
          dumpedObject = node;
        }
    }

    final buffer = StringBuffer();

    _writeDocDirectives(
      buffer,
      includeYamlDirective: includeYamlDirective,
      docDirectives: directives,
      onProperties: objectProperties,
    );

    dumpedObject = _applyCommentsIfAny(
      dumpedObject,
      comments: dumpable.comments,
      indent: indent,
      forceCommentsAsBlock: commentsAsBlock,
      offsetFromMargin: offsetFromMargin,
    );

    buffer.write(dumpedObject.indented(indent));

    if (includeDocumendEnd) {
      buffer.write(
        '${dumpedObject.endsWith('\n') ? '' : '\n'}'
        '${DocumentMarker.documentEnd.indicator}',
      );
    }

    return buffer.toString();
  }
}
