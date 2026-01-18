import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'initialize_collections.dart';

final class ObjectDumper extends YamlDumper {
  ObjectDumper._({required super.unpackAliases, required CommentDumper dumper})
    : super(
        commentDumper: dumper,
        pushAnchor: _pushAnchor,
        readAnchor: (anchor) => _anchors[anchor],
        asLocalTag: _validateTag,
      );

  /// Tracks the global tags associated with a specific tag handle.
  static final _globalTags = <TagHandle, GlobalTag>{};

  /// Tracks the anchors in case a
  static final _anchors = <String, ConcreteNode<Object?>>{};

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
    final dumper = ObjectDumper._(
      unpackAliases: unpackAliases,
      dumper: commentDumper,
    );
    final onObject = dumper.dumpable;
    final validator = dumper.asLocalTag;
    final pushAnchor = dumper.pushAnchor;

    final scalarDumper = ScalarDumper.fineGrained(
      replaceEmpty: true,
      onScalar: onObject,
      asLocalTag: validator,
      style: scalarStyle,
      forceInline: forceScalarsInline,
    );

    final (iterable, map) = _initializeCollections(
      onObject: onObject,
      pushAnchor: pushAnchor,
      asLocalTag: validator,
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

  /// Tracks an [object]'s [anchor] only if it's not an alias.
  static void _pushAnchor(String? anchor, DumpableNode<Object?> object) {
    if (anchor == null || object is DumpableAsAlias) return;
    _anchors[anchor] = object as ConcreteNode<Object?>;
  }

  /// Validates an [objectTag] and returns a stringified local tag/verbatim tag
  /// if present.
  static String? _validateTag(ResolvedTag? objectTag) {
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

  @override
  ObjectProperties? capturedProperties() => (
    anchors: _anchors,
    globalTags: _globalTags,
  );

  @override
  void onComplete() {
    _anchors.clear();
    _globalTags.clear();
  }
}
