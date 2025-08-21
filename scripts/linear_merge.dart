import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

const _repo = 'kekavc24/rookie_yaml';
const _defaultBranch = 'main';

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
  ({String directory, int prNumber, String headSHA}) unpack() => (
    //token: this['token'],
    directory: this['working-directory'],
    prNumber: int.parse(this['pr-num']),
    headSHA: this['head-SHA'].toString().trim(),
  );
}

typedef _ContributorInfo = ({
  String contributor,
  String repo,
  String branch,
  bool isExternalRepo,
});

extension on String {
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
  }) {
    final ProcessResult(:exitCode, :stdout, :stderr) = Process.runSync(
      command,
      args,
      workingDirectory: directory,
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

  runCommand(
    'git',
    args: ['push', '--force-with-lease', 'origin', _defaultBranch],
  );
}
