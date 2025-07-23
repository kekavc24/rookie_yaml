import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/comment_parser.dart';
import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'document_parser.dart';
part 'document_events.dart';
part 'doc_parser_utils.dart';

/// Represents the type of YAML document based on the use of directives,
/// directives end marker (`---`) and document end marker (`...`)
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

  final List<ReservedDirective> _reservedDirectives;

  final SplayTreeSet<YamlComment> _comments;

  /// Node at the root of the document
  final ParsedYamlNode? root;

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

  /// Returns `true` if no nodes are prsent
  bool get isEmpty => root == null;
}
