import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'initialize_collections.dart';

/// A class used to dump objects.
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

  /// Creates a reusable dumper.
  ///
  /// If [unpackAliases] is `true`, any aliases are dumped as the objects they
  /// reference.
  ///
  /// [commentStyle] and [commentStepSize] are used to configure how comments
  /// are dumped. See [CommentStyle] and [CommentDumper].
  ///
  /// The [scalarStyle] represents the style used to encode scalars. If
  /// [forceScalarsInline] is `true`, the [scalarStyle] is respected only if
  /// no line breaks are encountered. Otherwise, the line breaks are normalized
  /// and it defaults to [ScalarStyle.doubleQuoted]. Additionally, if the scalar
  /// is not compatible with the [scalarStyle]'s rules, it defaults to
  /// [ScalarStyle.doubleQuoted].
  ///
  /// [mapStyle] and [iterableStyle] represents the collection style used to
  /// encode [Map]s and [Iterable]s respectively. If [forceMapsInline] or
  /// [forceIterablesInline] is `true`, a [Map] or [Iterable] will be inlined
  /// only if the style is not [NodeStyle.block]. Flow nodes can be inlined
  /// because indent or whitespace before nodes has no significant meaning.
  factory ObjectDumper.of({
    bool unpackAliases = false,
    CommentStyle commentStyle = CommentStyle.block,
    int commentStepSize = 0,
    ScalarStyle scalarStyle = ScalarStyle.plain,
    bool forceScalarsInline = false,
    bool forceIterablesInline = false,
    bool forceMapsInline = false,
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

    final scalarDumper = ScalarDumper.fineGrained(
      replaceEmpty: true,
      onScalar: onObject,
      asLocalTag: validator,
      style: scalarStyle,
      forceInline: forceScalarsInline,
    );

    final (iterable, map) = _initializeCollections(
      onObject: onObject,
      pushAnchor: dumper.pushAnchor,
      asLocalTag: validator,
      scalar: scalarDumper,
      comments: commentDumper,
      flowIterableInline: forceIterablesInline,
      flowMapInline: forceMapsInline,
      sequenceStyle: iterableStyle,
      mappingStyle: mapStyle,
    );

    return dumper
      ..scalarDumper = scalarDumper
      ..iterableDumper = iterable
      ..mapDumper = map;
  }

  /// Creates a resuable dumper that outputs a compact YAML string.
  ///
  /// The [ObjectDumper] dumps [Map]s and [Iterable]s as block nodes with any
  /// explicit flow nodes forced inline.
  ///
  /// Scalars are styled as [ScalarStyle.plain] and forced inline. When line
  /// breaks are encountered, the dumper uses [ScalarStyle.doubleQuoted] as a
  /// fallback style.
  ///
  /// Aliases are not dumped as the node they alias.
  factory ObjectDumper.compact() => ObjectDumper.of(
    forceScalarsInline: true,
    forceIterablesInline: true,
    forceMapsInline: true,
  );

  /// Tracks an [object]'s [anchor] only if it's not an alias.
  static void _pushAnchor(String? anchor, DumpableNode<Object?> object) {
    if (anchor == null || object is DumpableAsAlias) return;
    _anchors[anchor] = object as ConcreteNode<Object?>;
  }

  /// Validates an [objectTag] and returns a stringified local/verbatim tag if
  /// present.
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
  DumpableNode<Object?> dumpable(Object? object) {
    // Ignore explicit concrete node in case the node style is different.
    if (object is ConcreteNode) return object;
    final dumpable = dumpableObject(object, unpackAnchor: unpackAliases);

    if (dumpable is DumpableAsAlias) {
      if (_anchors[dumpable.alias] case ConcreteNode<Object?> anchor) {
        return unpackAliases ? anchor : dumpable;
      }

      throw ArgumentError('The alias "$dumpable" has no corresponding anchor');
    }

    final concrete = dumpable as ConcreteNode<Object?>;
    return object is Iterable
        ? (concrete..nodeStyle = iterableDumper.iterableStyle)
        : object is Map
        ? (concrete..nodeStyle = mapDumper.mapStyle)
        : concrete;
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

void forceReset() {
  ObjectDumper._anchors.clear();
  ObjectDumper._globalTags.clear();
}
