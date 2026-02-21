import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'utils.dart';

const _packagePrefix = 'package:';

final _testRunnerArgParser = ArgParser()
  ..addOption(
    'pr',
    help: 'Pull Request associated where this PR is being run',
    mandatory: true,
  )
  ..addOption(
    'working-directory',
    help: 'Root directory with repository',
    mandatory: true,
  )
  ..addOption('labels', help: 'Labels added to a PR', mandatory: true);

extension on ArgResults {
  ({String pr, String directory, List labels}) unpack() => (
    pr: this['pr'],
    directory: this['working-directory'],
    labels: json.decode(this['labels']) as List,
  );
}

void main(List<String> args) {
  final (:pr, :directory, :labels) = _testRunnerArgParser.parse(args).unpack();

  final packages = labels
      .map((l) => l.toString())
      .where((l) => l.startsWith(_packagePrefix))
      .map((e) => e.replaceFirst(_packagePrefix, ''));

  // Successful run either way.
  if (packages.isEmpty) {
    print('Naught');
    exit(0);
  } else if (packages.length > 1) {
    addBotComment(pr, directory, '''
Hello,

It seems you modified multiple packages in one PR:
${packages.map((e) => '  - `package:$e`').join('\n')}

Please read our contribution guidelines in the `CONTRIBUTING.md` file and create separate PRs for each package based on this guideline.
''');

    exit(1);
  }

  // Print directory
  print(path.joinAll([directory, 'packages', packages.first]));
}
