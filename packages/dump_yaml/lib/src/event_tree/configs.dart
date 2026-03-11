import 'dart:math';

import 'package:dump_yaml/src/utils.dart';
import 'package:rookie_yaml/rookie_yaml.dart' hide CommentStyle;

/// Style configuration for the document.
typedef NodeConfig = ({
  ScalarStyle scalarStyle,
  NodeStyle rootNodeStyle,
  NodeStyle mapStyle,
  NodeStyle iterableStyle,
  bool emptyAsNull,
  bool forceInline,
  bool includeSchemaTag,
});

/// Configuration applied to the node tree before it is dumped.
extension type TreeConfig._(NodeConfig config) {
  /// Creates a [TreeConfig] for a YAML document with a [NodeStyle.block] root
  /// node. YAML schema tags will be excluded unless [includeSchemaTag] is
  /// `true`.
  ///
  /// Block nodes can embed both [NodeStyle.block] and [NodeStyle.flow] nodes.
  /// Every child inherits the [mapStyle] and [iterableStyle].
  ///
  /// If [emptyAsNull] is `true`, an empty scalar is replaced with `null`.
  TreeConfig.block({
    ScalarStyle scalarStyle = classicScalarStyle,
    NodeStyle mapStyle = NodeStyle.block,
    NodeStyle iterableStyle = NodeStyle.block,
    bool emptyAsNull = true,
    bool includeSchemaTag = false,
  }) : this._((
         rootNodeStyle: NodeStyle.block,
         scalarStyle: scalarStyle,
         mapStyle: mapStyle,
         iterableStyle: iterableStyle,
         emptyAsNull: emptyAsNull,
         forceInline: false,
         includeSchemaTag: includeSchemaTag,
       ));

  /// Creates a [TreeConfig] for a YAML document with a [NodeStyle.flow] root
  /// node. Unlike block nodes, flow nodes can only embed [NodeStyle.flow]
  /// nodes.
  ///
  /// If [emptyAsNull] is `true`, an empty scalar is replaced with `null`.
  TreeConfig.flow({
    ScalarStyle scalarStyle = classicScalarStyle,
    bool emptyAsNull = true,
    bool forceInline = true,
    bool includeSchemaTag = false,
  }) : this._((
         rootNodeStyle: NodeStyle.flow,
         scalarStyle: scalarStyle.nodeStyle.isBlock
             ? classicScalarStyle
             : scalarStyle,
         mapStyle: NodeStyle.flow,
         iterableStyle: NodeStyle.flow,
         emptyAsNull: emptyAsNull,
         forceInline: forceInline,
         includeSchemaTag: includeSchemaTag,
       ));
}

/// Configuration options for the dumper.
typedef DumperConfig = ({
  /// Indent of the first node that may be a terminal node or collection of
  /// other nodes.
  int rootIndent,

  /// Level of indentation when moving to a node nested within another node.
  int indentationStep,
});

/// Formatting configuration for the node being dumped.
extension type Formatter._(DumperConfig config) {
  /// Creates a [Formatter] with the provided configuration.
  ///
  /// The [indentationStep] must be `>= 1` and the [rootIndent] `>= 0`. The
  /// comment [style] will be applied the entire document.
  Formatter.config({int rootIndent = 0, int indentationStep = 2})
    : this._((
        rootIndent: max(rootIndent, 0),
        indentationStep: max(indentationStep, 1),
      ));

  /// Creates a [Formatter] which uses [CommentStyle.block] for comments and
  /// an `indentationStep` of `2` spaces.
  Formatter.classic({int indent = 0}) : this.config(rootIndent: indent);
}

/// Dumper configuration.
extension type Config._(({TreeConfig styling, Formatter formatting}) config) {
  /// Creates a [Config] for the dumper with the provided [styling] and
  /// [formatting] configuration.
  Config.yaml({TreeConfig? styling, Formatter? formatting})
    : this._((
        styling: styling ?? TreeConfig.block(),
        formatting: formatting ?? Formatter.classic(),
      ));

  /// Creates the default dumper [Config].
  Config.defaults()
    : this.yaml(styling: TreeConfig.block(), formatting: Formatter.classic());
}
