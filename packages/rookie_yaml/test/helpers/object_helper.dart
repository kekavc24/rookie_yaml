import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_parser.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

const doc = [
  '# Nothing here',
  'plain scalar',
  '"double quoted"',
  "'single quoted'",
  '|\nliteral',
  '>\nfolded',
  '{flow: map}',
  '[flow, sequence]',

  '- block\n- sequence',

  'implicit: map',

  '? explicit\n'
      ': map',
];

const parsed = <String>[
  'null',
  'plain scalar',
  'double quoted',
  'single quoted',
  'literal\n',
  'folded\n',
  '{flow: map}',
  '[flow, sequence]',
  '[block, sequence]',
  '{implicit: map}',
  '{explicit: map}',
];

const _directiveEnd = '---';
const _docEnd = '...';
const _lf = '\n';

String docStringAs(YamlDocType docType) {
  final hasDirectiveEnd = docType != YamlDocType.bare;

  return doc
      .expand((node) sync* {
        if (hasDirectiveEnd) {
          yield _directiveEnd;
        }

        yield node;
        yield _docEnd;
      })
      .join(_lf);
}

List<YamlDocument<TestNode<Object>>> loadDoc(String doc) => loadYamlDocuments(
  DocumentParser(
    UnicodeIterator.ofString(doc),
    aliasFunction: (alias, reference, _) => TestAlias(reference, alias),
    collectionFunction: (object, objectStyle, tag, anchor, _) =>
        TestNode(object, objectStyle, tag: tag, anchor: anchor),
    scalarFunction: (object, objectStyle, tag, anchor, _) =>
        TestNode(object, objectStyle, tag: tag, anchor: anchor),
    logger: (_, _) {},
    onMapDuplicate: (_, _, _) {},
    builder: (directives, documentInfo, rootNode) => YamlDocument.parsed(
      directives: directives,
      documentInfo: documentInfo,
      node: rootNode,
    ),
  ),
);

class TestNode<S> extends CompactYamlNode {
  TestNode(this.object, this.style, {this.tag, this.anchor});

  final Object? object;

  final S style;

  @override
  NodeStyle get nodeStyle => style is NodeStyle
      ? style as NodeStyle
      : (style as ScalarStyle).nodeStyle;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchor;

  @override
  bool operator ==(Object other) =>
      yamlCollectionEquality.equals(object, other);

  @override
  int get hashCode => yamlCollectionEquality.hash(object);

  @override
  String toString() => object.toString();
}

final class TestAlias extends TestNode<NodeStyle> {
  TestAlias(TestNode<Object> node, this.alias) : super(node, NodeStyle.flow);

  @override
  final String alias;

  @override
  bool operator ==(Object other) {
    return other is TestAlias &&
        alias == other.object &&
        identical(object, other.object);
  }

  @override
  int get hashCode => Object.hashAll([alias, object.hashCode]);
}
