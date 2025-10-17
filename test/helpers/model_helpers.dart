import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

final flowDelimiters = Iterable.withIterator(
  () => [
    mappingStart,
    mappingEnd,
    flowSequenceStart,
    flowSequenceEnd,
    flowEntryEnd,
  ].map((e) => e.asString()).iterator,
);

Directives vanillaDirectives(String yaml) => parseDirectives(
  GraphemeScanner.of(yaml),
  onParseComment: (_) {},
  warningLogger: (_) {},
);

T _inferredValue<T>(Scalar<T> scalar) => scalar.value;

extension PreScalarHelper on Subject<PreScalar?> {
  void hasScalarStyle(ScalarStyle style) =>
      isNotNull().has((p) => p.scalarStyle, 'ScalarStyle').equals(style);

  void hasIndent(int indent) =>
      isNotNull().has((p) => p.scalarIndent, 'Inferred indent').equals(indent);

  void hasFormattedContent(String content) =>
      isNotNull().has((p) => p.content, 'Canonical Content').equals(content);

  void hasDocEndMarkers() => isNotNull()
      .has((p) => p.docMarkerType.stopIfParsingDoc, 'Document End Markers')
      .isTrue();

  void indentDidChangeTo(int indent) => isNotNull()
    ..has((p) => p.indentDidChange, 'Indent Change Indicator').isTrue()
    ..has((p) => p.indentOnExit, 'Indent on Exit').equals(indent);
}

extension ScalarHelper on Subject<Scalar> {
  void hasInferred<T>(String name, T expected) =>
      isNotNull().has(_inferredValue, name).isA<T>().equals(expected);

  void hasParsedInteger(int number) => hasInferred('Parsed Integer', number);

  void inferredBool(bool value) => hasInferred('Boolean', value);

  void inferredFloat(double value) => hasInferred('Float', value);

  void inferredNull() => has(_inferredValue, 'Null').isNull();
}

extension ParsedNodeHelper on Subject<YamlSourceNode?> {
  Subject<ResolvedTag?> withTag() =>
      isNotNull().has((n) => n.tag, 'Resolved tag');

  void hasNoTag() => withTag().isNull();

  void hasTag<T>(SpecificTag<T> tag, {TagShorthand? suffix}) => withTag()
      .isNotNull()
      .has((t) => t.verbatim, 'As verbatim')
      .equals(NodeTag(tag, suffix).verbatim);

  void asSimpleString(String node) => isNotNull()
      .has((n) => n.toString(), 'Node as simple string')
      .equals(node);
}

extension ParsedDocHelper on Subject<YamlDocument> {
  void hasVersionDirective(YamlDirective directive) =>
      has((d) => d.versionDirective, 'Yaml directive').equals(directive);

  void hasGlobalTags(Set<GlobalTag<dynamic>> tags) =>
      has((d) => d.tagDirectives, 'Global Tags').unorderedEquals(tags);

  void hasReservedDirective(List<String> directives) => has(
    (d) => d.otherDirectives.map((d) => d.toString()),
    'Reserved Directives',
  ).unorderedEquals(directives);

  Subject<bool> isDocEndExplicit() =>
      has((d) => d.hasExplicitEnd, 'Has document End Markers');

  Subject<bool> isDocStartExplicit() =>
      has((d) => d.hasExplicitStart, 'Has directive end markers');

  Subject<YamlSourceNode> hasNode() => has((d) => d.root, 'Root node');

  void isDocOfType(YamlDocType docType) =>
      has((d) => d.docType, 'Document Type').equals(docType);
}
