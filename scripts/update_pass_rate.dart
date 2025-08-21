import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

final _regex = RegExp(r'(^!\[test_suite\].*$)', multiLine: true);

const _label = '![test_suite]';
const _urlPrefix = 'https://img.shields.io/badge/YAML_Test_Suite';

final _argParser = ArgParser()
  ..addOption(
    'working-directory',
    abbr: 'w',
    mandatory: true,
    help: 'Working directory for repo',
  )
  ..addOption(
    'test-rate-input',
    abbr: 'i',
    mandatory: true,
    help: 'Test suite rate',
  );

extension on ArgResults {
  ({String directory, double passRate}) unpack() => (
    directory: this['working-directory'],
    passRate: double.parse(this['test-rate-input']),
  );
}

extension on double {
  String get color => switch (this) {
    < 50 => 'red',
    >= 50 && < 75 => 'yellow',
    _ => 'green',
  };
}

void main(List<String> args) {
  final (:directory, :passRate) = _argParser.parse(args).unpack();

  final file = File(path.join(directory, 'README.md'));

  final replacement = '$_label$_urlPrefix-$passRate%-${passRate.color}.svg';
  final updated = file.readAsStringSync().replaceFirst(_regex, replacement);
  file.writeAsStringSync(updated);
}
