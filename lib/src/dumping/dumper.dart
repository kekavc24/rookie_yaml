import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

/// Callback for properties captured after a [YamlDumper] has fully dumped an
/// object.
typedef OnProperties =
    void Function(
      Iterable<MapEntry<TagHandle, GlobalTag>> tags,
      Iterable<(String anchor, Object? object)> anchors,
    );

/// Anchors and [GlobalTag]s obtained from a dumped object.
typedef ObjectProperties = ({
  Map<String, Object?> anchors,
  Map<TagHandle, GlobalTag> globalTags,
});

/// A yaml dumper.
abstract class YamlDumper {
  YamlDumper({
    required this.unpackAliases,
    required this.pushAnchor,
    required this.readAnchor,
    required this.asLocalTag,
    CommentDumper? commentDumper,
  }) : commentDumper = commentDumper ?? CommentDumper(CommentStyle.block, 0);

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

  /// A callback for accessing aliases of an anchor.
  final ConcreteNode<Object?>? Function(String anchor) readAnchor;

  /// A callback for pushing anchors.
  final PushAnchor pushAnchor;

  /// A callback for validating, tracking and normalizing a resolved tag.
  final AsLocalTag asLocalTag;

  /// Attempts to convert the [object] to a [DumpableNode]. Unpacks an [Alias]
  /// and return its true reference if [unpackAliases] is `true`.
  ///
  /// If your object has a special steps before it can be a dumpable
  DumpableNode<Object?> dumpable(Object? object) => dumpableType(object);

  /// Anchors and tags captured when dumping objects after unpacking a
  /// [ResolvedTag]. The map with the [GlobalTag]s must be modifiable.
  ObjectProperties? capturedProperties();

  /// Resets a dumper after an object has been dumped. Override and clean up
  /// your dumper's internal state.
  void onComplete();
}

/// Writes any document [Directive]s present to the [buffer].
void _writeDirectives(
  YamlDumper dumper,
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

  if (dumper.capturedProperties() case ObjectProperties properties) {
    final (:globalTags, :anchors) = properties;

    if (onProperties != null) {
      onProperties(
        globalTags.entries,
        anchors.entries.map((e) => (e.key, e.value)),
      );
    } else {
      // The YAML global tag is always implied.
      if (dropGlobalYamlTag(globalTags[defaultYamlHandle])) {
        globalTags.remove(defaultYamlHandle);
      }

      // Global tags before other external directives.
      directives = globalTags.values.cast<Directive>().followedBy(
        directives.whereNot(
          (e) => dropDirective(e, (g) => globalTags.containsKey(g.tagHandle)),
        ),
      );
    }
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
  CommentDumper commentDumper,
  String object, {
  required List<String> comments,
  required int indent,
  required bool forceCommentsAsBlock,
  required int? offsetFromMargin,
}) => comments.isEmpty
    ? object
    : commentDumper.applyComments(
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

/// Dumps an [object] with the specified [indent]. Uses the [dumper] provided.
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
String dumpObject(
  Object? object, {
  required YamlDumper dumper,
  int indent = 0,
  bool includeYamlDirective = false,
  Iterable<Directive>? directives,
  OnProperties? objectProperties,
  bool includeDocumendEnd = false,
}) {
  final dumpable = dumper.dumpable(object);

  var dumpedObject = '';
  var commentsAsBlock = true;
  int? offsetFromMargin;

  // Saves the output from a dumped map/iterable.
  void dumpedCollection(DumpedCollection dumped) {
    commentsAsBlock = !dumped.applyTrailingComments;
    dumpedObject = dumped.node;
  }

  unwrappedDumpable(
    dumpable,
    onIterable: (iterable) => dumpedCollection(
      dumper.iterableDumper.dumpIterableLike(
        iterable,
        expand: identity,
        indent: indent,
        tag: dumpable.tag,
        anchor: dumpable.anchor,
      ),
    ),
    onMap: (map) => dumpedCollection(
      dumper.mapDumper.dumpMapLike(
        map,
        expand: identity,
        indent: indent,
        tag: dumpable.tag,
        anchor: dumpable.anchor,
      ),
    ),
    onScalar: () {
      final (isMultiline: _, :node, :tentativeOffsetFromMargin) = dumper
          .scalarDumper
          .dump(dumpable, indent: indent, style: null);

      commentsAsBlock =
          dumper.scalarDumper.defaultStyle.nodeStyle == NodeStyle.block;
      offsetFromMargin = tentativeOffsetFromMargin;
      dumpedObject = node;
    },
  );

  final buffer = StringBuffer();

  _writeDirectives(
    dumper,
    buffer,
    includeYamlDirective: includeYamlDirective,
    docDirectives: directives,
    onProperties: objectProperties,
  );

  dumpedObject = _applyCommentsIfAny(
    dumper.commentDumper,
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

  dumper.onComplete();
  return buffer.toString();
}
