import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

part 'document_parser.dart';

/// A document representing the entire `YAML` string or a single
/// scalar/collection node within a group of documents in `YAML`.
///
/// {@category yaml_docs}
/// {@category dump_doc}
final class YamlDocument {
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
    required RootNode<YamlSourceNode> node,
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
  final YamlSourceNode root;

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
  String toString() => root.node.toString();
}
