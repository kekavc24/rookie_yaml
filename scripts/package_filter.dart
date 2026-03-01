import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

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
  );

extension on ArgResults {
  ({String pr, String directory}) unpack() =>
      (pr: this['pr'], directory: this['working-directory']);
}

/// Fetches the labels of a [pr].
List<String> _fetchLabels(String pr, String directory) {
  return runCommand(
    'gh',
    args: ['pr', 'view', pr, '--repo', rootRepository, '--json', 'labels'],
    directory: directory,
    mapper: (stdout) {
      return (json.decode(stdout)['labels'] as List)
          .whereType<Map>()
          .map((m) => m['name']?.toString())
          .whereType<String>()
          .toList();
    },
  );
}

void main(List<String> args) {
  final (:pr, :directory) = _testRunnerArgParser.parse(args).unpack();

  final labels = _fetchLabels(pr, directory).toSet();

  final packages = labels
      .where((l) => l.startsWith(_packagePrefix))
      .map((e) => e.replaceFirst(_packagePrefix, ''));

  // Successful run either way.
  if (packages.isEmpty || labels.contains('skip-package-check')) {
    print('Naught');
    exit(0);
  } else if (packages.length > 1) {
    addBotComment(pr, directory, '''
Hello,

It seems you modified multiple packages in one PR:
${packages.map((e) => '  - `package:$e`').join('\n')}

Please read our contribution guidelines in the `CONTRIBUTING.md` file and create separate PRs for each package based on those guidelines.
''');

    exit(1);
  }

  // Print package
  print(packages.first);
}
