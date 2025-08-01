import 'package:rookie_yaml/src/parser/document/yaml_document.dart';

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
