import 'dart:math';

import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

/// Config for the document.
typedef DocConfig = ({
  bool includeParserVersion,
  Set<Directive> directives,
  bool addDocEndChars,
});

/// Config for nodes in the document.
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

  /// Line ending for the dumper.
  String lineEnding,
});

/// Validates if the [lineEnding] is a valid YAML line ending.
String yamlLineBreaks(String lineEnding) => switch (lineEnding) {
  '\r\n' || '\r' || '\n' => lineEnding,
  _ => '\n',
};

/// Formatting configuration for the node being dumped.
extension type Formatter._(DumperConfig config) {
  /// Creates a [Formatter] with the provided configuration.
  ///
  /// The [indentationStep] must be `>= 1` and the [rootIndent] `>= 0`. The
  /// [lineEnding] defaults to `\n` if not `\r\n` or `\r` or `\n`.
  Formatter.config({
    required int rootIndent,
    int indentationStep = 2,
    String lineEnding = '\n',
  }) : this._((
         rootIndent: max(rootIndent, 0),
         indentationStep: max(indentationStep, 1),
         lineEnding: yamlLineBreaks(lineEnding),
       ));

  /// Creates a [Formatter] which uses `indentationStep` of `2` spaces and
  /// defaults to a linefeed `\n` as its line ending.
  Formatter.classic({int indent = 0}) : this.config(rootIndent: indent);
}

/// Config for entire YAML document.
typedef YamlConfig = ({
  DocConfig docConfig,
  TreeConfig styling,
  Formatter formatting,
});

/// Dumper configuration.
extension type Config._(YamlConfig yamlConfig) {
  /// Creates a [Config] for the dumper with the provided [styling] and
  /// [formatting] configuration.
  Config.yaml({
    TreeConfig? styling,
    Formatter? formatting,
    bool includeYamlDirective = false,
    Set<Directive> directives = const {},
    bool includeDocEnd = false,
  }) : this._((
         styling: styling ?? TreeConfig.block(),
         formatting: formatting ?? Formatter.classic(),
         docConfig: (
           includeParserVersion: includeYamlDirective,
           directives: directives,
           addDocEndChars: includeDocEnd,
         ),
       ));

  /// Creates the default dumper [Config].
  ///
  /// Nodes in the document are dumped as [NodeStyle.block]. Internally, nodes
  /// wrapped with a [DumpableView] may override this behaviour. The dumper
  /// uses an indentation step of value `2` and a linefeed `\n` as its line
  /// break. The root node will have an indentation of `0`.
  ///
  /// At the document level, the dumper will attempt to dump a clean YAML
  /// document with no [YamlDirective] (YAML version), [GlobalTag]s,
  /// [ReservedDirective]s or a document end directive. A [GlobalTag], however,
  /// may be included if any node in the document uses a named tag or a custom
  /// tag that resolves to a [GlobalTag].
  Config.defaults()
    : this.yaml(styling: TreeConfig.block(), formatting: Formatter.classic());
}
