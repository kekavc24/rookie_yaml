import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

const _repo = 'kekavc24/rookie_yaml';
const _defaultBranch = 'main';

/// Test suite badge uri regex
final _regex = RegExp(r'(^!\[test_suite\].*$)', multiLine: true);

const _label = '![test_suite]';
const _urlPrefix = 'https://img.shields.io/badge/YAML_Test_Suite';

/// Argument parser to validate args for this script
final _argParser = ArgParser()
  ..addOption(
    'working-directory',
    abbr: 'w',
    mandatory: true,
    help: 'Repo directory',
  )
  ..addOption(
    'pr-num',
    abbr: 'p',
    mandatory: true,
    help: 'Github PR json event',
  )
  ..addOption(
    'head-SHA',
    abbr: 's',
    mandatory: true,
    help: 'Commit ID at the tip of the PR branch',
  );

extension on ArgResults {
  /// Unpacks the arguments passed and returns:
  ///   - A directory where the current workflow is running
  ///   - PR number of PR that triggered the merging worflow
  ///   - SHA signature of the commit at the tip of the PR branch. This ensures
  ///     we merge branches in the state they were approved.
  ({String directory, int prNumber, String headSHA}) unpack() => (
    //token: this['token'],
    directory: this['working-directory'],
    prNumber: int.parse(this['pr-num']),
    headSHA: this['head-SHA'].toString().trim(),
  );
}

/// Contributor information
typedef _ContributorInfo = ({
  String contributor,
  String repo,
  String branch,
  bool isExternalRepo,
});

extension on String {
  /// Parses the PR info of the branch to be merged
  _ContributorInfo parseContributorInfo() {
    final parsed = json.decode(this);

    if (parsed case {
      'headRepositoryOwner': {'login': final contributor},
      'headRepository': {'name': final repo},
      'headRefName': final branch,
      'isCrossRepository': bool isExternalRepo,
    }) {
      return (
        contributor: contributor.toString(),
        repo: repo.toString(),
        branch: branch.toString(),
        isExternalRepo: isExternalRepo,
      );
    }

    throw Exception('Incorrect API response: $parsed');
  }
}

extension on int {
  bool get isSuccess => this == 0;
}

extension on double {
  String get color => switch (this) {
    < 50 => 'red',
    >= 50 && < 75 => 'yellow',
    _ => 'green',
  };
}

/// Update the `YAML` test suite [passRate] in the README.
///
/// [directory] refers to path of the directory with the README.
void _updatePassRate(String directory, double passRate) {
  final file = File(path.join(directory, 'README.md'));

  final replacement = '$_label($_urlPrefix-$passRate%25-${passRate.color})';
  final updated = file.readAsStringSync().replaceFirst(_regex, replacement);
  file.writeAsStringSync(updated);
}

void main(List<String> args) {
  final (:directory, :prNumber, :headSHA) = _argParser.parse(args).unpack();

  assert(
    directory.isNotEmpty && headSHA.isNotEmpty,
    'Expected a directory and SHA signature, found "$directory" && "$headSHA"',
  );

  /// Run command in the current directory and returns output
  T runCommand<T>(
    String command, {
    required List<String> args,
    String? messageOnFail,
    T Function(String stdout)? mapper,
    String? dirOverride,
  }) {
    final ProcessResult(:exitCode, :stdout, :stderr) = Process.runSync(
      command,
      args,
      workingDirectory: dirOverride ?? directory,
    );

    if (!exitCode.isSuccess) {
      throw Exception(messageOnFail ?? stderr);
    }

    return mapper != null ? mapper(stdout) : stdout as T;
  }

  // Fetch PR info
  final (:contributor, :repo, :branch, :isExternalRepo) = runCommand(
    'gh',
    args: [
      'pr',
      'view',
      '$prNumber',
      '--repo',
      _repo,
      '--json',
      'headRepository',
      '--json',
      'headRepositoryOwner',
      '--json',
      'headRefName',
      '--json',
      'isCrossRepository',
    ],
    mapper: (stdout) => stdout.parseContributorInfo(),
    messageOnFail: 'Failed to fetch pull request info',
  );

  var origin = 'origin';

  // Fetch the external repo to local
  if (isExternalRepo) {
    origin = 'forked';

    runCommand(
      'git',
      args: [
        'remote',
        'add',
        origin,
        'https://github.com/$contributor/$repo',
      ],
    );
  }

  runCommand('git', args: ['fetch', origin]);

  final actualMergeBranch = '$origin/$branch';

  print(actualMergeBranch);

  runCommand('git', args: ['remote', 'show', 'origin']);

  runCommand('git', args: ['checkout', _defaultBranch]); // Just be safe

  // Most people may find this offputting.
  runCommand('git', args: ['merge', '--ff-only', actualMergeBranch]);

  // Check if the head commits match. Injector, no injecting
  if (runCommand(
        'git',
        args: ['rev-parse', 'HEAD'],
        mapper: (stdout) => stdout.trim(),
      )
      case final commitID when commitID != headSHA) {
    throw Exception('''
$actualMergeBranch found in a dirty state.
Expected tip SHA: $headSHA
Current tip SHA: $commitID
''');
  }

  // Leave bot approval once merge was successful
  runCommand(
    'gh',
    args: ['pr', 'review', '--approve', '$prNumber', '--repo', _repo],
  );

  // Regenerate latest test suite pass rate before push
  final passRate = runCommand(
    'dart',
    args: ['matrix_runner.dart', '--no-file-output'],
    dirOverride: path.joinAll([directory, 'test', 'yaml_matrix_tests']),
    mapper: (stdout) => double.parse(stdout.trim()),
  );

  // Update README
  _updatePassRate(directory, passRate);

  // Check if we can actually commit it
  if (runCommand(
    'git',
    args: ['status', '--porcelain'],
    mapper: (stdout) => stdout.trim(),
  ).isNotEmpty) {
    runCommand('git', args: ['add', 'README.md']);
    runCommand('git', args: ['commit', '-m', 'Test Suite Update: $passRate%']);
  }

  runCommand(
    'git',
    args: ['push', '--force-with-lease', 'origin', _defaultBranch],
  );
}
