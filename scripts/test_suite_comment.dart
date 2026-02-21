import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'utils.dart';

final _commentArgParser = ArgParser()
  ..addOption(
    'pr',
    help: 'Pull Request associated where this PR is being run',
    mandatory: true,
  )
  ..addOption(
    'tip-SHA',
    help: 'Commit SHA at the tip of PR branch',
    mandatory: true,
  )
  ..addOption(
    'working-directory',
    help: 'Root directory with repository',
    mandatory: true,
  );

extension on ArgResults {
  ({String pr, String headCommit, String directory}) unpack() => (
    pr: this['pr'],
    headCommit: this['tip-SHA'],
    directory: this['working-directory'],
  );
}

const _keyInSummary = 'Average Pass Accuracy (%):';

/// Compares the current pass rate in the repo and the latest pass rate obtained
/// from the current PR.
({double currentPassRate, String diff}) _passRateDiff(
  String rootDirectory,
  String summary,
) {
  final rateOnPR = double.parse(
    summary
        .split('\n')
        .map((e) => e.trim())
        .firstWhere((l) => l.startsWith(_keyInSummary), orElse: () => '0.0')
        .replaceFirst(_keyInSummary, '')
        .trim(),
  );

  final currentInRepo = getCurrentPassRate(rootDirectory);

  return (
    currentPassRate: currentInRepo,
    diff: currentInRepo == rateOnPR
        ? 'No change ☑️'
        : currentInRepo > rateOnPR
        ? 'Regression detected ‼️'
        : 'Possible fix ✅',
  );
}

void main(List<String> args) {
  final (:pr, :headCommit, :directory) = _commentArgParser.parse(args).unpack();

  // Run test suite and get the summary
  final summary = runCommand<String>(
    'dart',
    args: ['runner.dart', '--mode', 'summary'],
    directory: path.joinAll([directory, 'test', 'yaml_test_suite']),
  );

  final (:currentPassRate, :diff) = _passRateDiff(directory, summary);
  addBotComment(pr, directory, '''
$diff
---
* Head SHA commit: $headCommit
* Base Repository Pass Rate: `$currentPassRate%`

```yaml
$summary
```
''');
}
