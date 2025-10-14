import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'doc_parser_utils.dart';
part 'document_parser.dart';

/// Represents the type of YAML document based on the use of directives,
/// directives end marker (`---`) and document end marker (`...`)
///
/// {@category yaml_docs}
enum YamlDocType {
  /// Yaml document without any directives or directives end markers
  ///
  /// ```yaml
  /// # Bare document
  /// ...
  /// # Bare document with node
  /// key: value
  /// ...
  /// ```
  bare,

  /// A YAML document with an explicit directives end marker at the beginning
  /// but no directives
  ///
  /// ```yaml
  /// ---
  /// # Explicit empty doc
  /// ...
  /// ---
  /// # Explicit doc with node
  /// key: value
  /// ...
  /// ```
  explicit,

  /// A YAML document with directives, an explicit directives end marker and
  /// an optional document end marker.
  ///
  /// The document marker is not required if this is the last document. It is
  /// implied.
  directiveDoc;

  static YamlDocType inferType({
    required bool hasDirectives,
    required bool isDocStartExplicit,
  }) => switch (hasDirectives) {
    true => YamlDocType.directiveDoc,
    _ when isDocStartExplicit => YamlDocType.explicit,
    _ => YamlDocType.bare,
  };
}

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
}
