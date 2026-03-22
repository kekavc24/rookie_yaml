import 'dart:collection';

import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A document representing the entire `YAML` string or a single
/// scalar/collection node within a group of documents in `YAML`.
abstract class YamlDocument<T, C extends Iterable<YamlComment>> {
  YamlDocument._(
    this._yamlDirective,
    this.docType,
    this.hasExplicitStart,
    this.hasExplicitEnd,
  );

  /// Creates a [YamlDocument] from a parsed YAML string or bytes.
  YamlDocument.parsed({
    required ParsedDirectives directives,
    required DocumentInfo documentInfo,
    required RootNode<T> node,
  }) : this._(
         directives.version,
         documentInfo.docType,
         documentInfo.hasExplicitStart,
         documentInfo.hasExplicitEnd,
       );

  /// Position in the `YAML` string.
  int get index;

  /// Start offset for the document.
  RuneOffset get startOffset;

  /// Parsed version directive
  final YamlDirective? _yamlDirective;

  /// Node at the root of the document
  T get root;

  /// Generic type of document based on the use of directives, directives end
  /// markers (`---`) and document end markers (`...`) as described by the
  /// YAML spec.
  ///
  /// See also [hasExplicitStart] and [hasExplicitEnd] for fine-grained info.
  final YamlDocType docType;

  /// Whether `---` is present at the beginning which marks the end of doc's
  /// directives and its start.
  final bool hasExplicitStart;

  /// Whether `...` is present at the end which marks the end of the document.
  final bool hasExplicitEnd;

  /// Version directive for the document
  YamlDirective get versionDirective => _yamlDirective ?? parserVersion;

  /// Tag directives declared at start of the document.
  Set<GlobalTag<dynamic>> get tagDirectives;

  /// Any directive that is not a tag or version directive
  List<ReservedDirective> get otherDirectives;

  /// An ordered view of the [YamlComment]s within the document as they were
  /// extracted
  C get comments;

  @override
  String toString() => root.toString();
}

/// An unmodifiable YAML document.
final class UnModifiableDocument<T> extends YamlDocument<T, List<YamlComment>> {
  UnModifiableDocument.parsed({
    required super.directives,
    required super.documentInfo,
    required super.node,
  }) : index = documentInfo.index,
       root = node.root,
       startOffset = documentInfo.start,
       tagDirectives = UnmodifiableSetView(directives.tags.toSet()),
       otherDirectives = UnmodifiableListView(directives.unknown),
       comments = UnmodifiableListView(node.comments),
       super.parsed();

  @override
  final int index;

  @override
  final T root;

  @override
  final RuneOffset startOffset;

  @override
  final Set<GlobalTag<dynamic>> tagDirectives;

  @override
  final List<ReservedDirective> otherDirectives;

  @override
  final List<YamlComment> comments;
}
