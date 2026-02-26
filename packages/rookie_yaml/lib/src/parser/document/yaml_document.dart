import 'dart:collection';

import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// A document representing the entire `YAML` string or a single
/// scalar/collection node within a group of documents in `YAML`.
///
/// {@category yaml_docs}
/// {@category dump_doc}
final class YamlDocument<T> {
  YamlDocument._(
    this.index,
    this._yamlDirective,
    this._globalTags,
    this._reservedDirectives,
    this._comments,
    this.root,
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
         documentInfo.index,
         directives.version,
         directives.tags.toSet(),
         directives.unknown,
         node.comments,
         node.root,
         documentInfo.docType,
         documentInfo.hasExplicitStart,
         documentInfo.hasExplicitEnd,
       );

  /// Position in the `YAML` string.
  final int index;

  /// Parsed version directive
  final YamlDirective? _yamlDirective;

  /// Global tags declared for the YAML document.
  final Set<GlobalTag<dynamic>> _globalTags;

  /// Reserved directives parsed
  final List<ReservedDirective> _reservedDirectives;

  /// Comments extracted from the document while parsing
  final List<YamlComment> _comments;

  /// Node at the root of the document
  final T root;

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
  Set<GlobalTag<dynamic>> get tagDirectives => UnmodifiableSetView(_globalTags);

  /// Any directive that is not a tag or version directive
  List<ReservedDirective> get otherDirectives =>
      UnmodifiableListView(_reservedDirectives);

  /// An ordered view of the [YamlComment]s within the document as they were
  /// extracted
  List<YamlComment> get comments => UnmodifiableListView(_comments);

  @override
  String toString() => root.toString();
}
