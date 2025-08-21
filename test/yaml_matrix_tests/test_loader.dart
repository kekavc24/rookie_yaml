import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Result for the matrix test
enum MatrixResultType {
  /// Parsing failed
  fail,

  /// Parsing completed successfully
  pass,

  /// Parsing completed successfully but the result doesn't match the expected
  /// output
  invalidPass,
}

/// Result after a [MatrixTest] has been run to completion
typedef MatrixResult = ({
  String metaInfo,
  MatrixResultType resultType,
  List<String> messages,
});

/// A `YAML` test suite test
sealed class MatrixTest {
  /// Test description
  final String meta;

  /// `YAML` string to be used in test
  final String testAsYaml;

  /// Log messages
  final List<String> logs;

  MatrixTest(
    this.meta, {
    required this.testAsYaml,
    required this.logs,
  });

  /// Default [MatrixResultType] for the test
  MatrixResultType get expectedResult;

  /// Returns `true` if [result] matches [expectedResult].
  bool isSuccess(MatrixResultType result) => result == expectedResult;

  @override
  String toString() => meta;
}

/// A [MatrixTest] that must fail.
final class FailTest extends MatrixTest {
  FailTest(super.meta, {required super.testAsYaml, required super.logs});

  @override
  MatrixResultType get expectedResult => MatrixResultType.fail;
}

/// A [MatrixTest] that must pass.
final class SuccessTest extends MatrixTest {
  SuccessTest(
    super.meta, {
    required super.testAsYaml,
    required this.jsonAsDartStr,
    required super.logs,
  });

  /// A json-like `Dart` string that is used to validate the output of the
  /// successful test.
  final String jsonAsDartStr;

  @override
  MatrixResultType get expectedResult => MatrixResultType.pass;
}

/// A [StateError] thrown when a [MatrixTest] could not be loaded from a
/// stream test inputs
final class LoadingError extends StateError {
  LoadingError(String reason) : super('Failed to load matrix tests: $reason');
}

const _metaPath = '===';
const _jsonInputPath = 'jsonToDartStr';
const _yamlInputPath = 'in.yaml';
const _gitPath = '.git';

const _emptyMeta = 'No meta description was provided';

const _testSuiteCommitHash = '2c5d1b0b0b75e306175399d032bd4c9e8564be8c';
const _repoUrl = 'https://github.com/kekavc24/yaml_test_suite_dart';

/// Fetches the test data from the [_repoUrl]
String fetchTestData() {
  final testPath = path.joinAll([
    Directory.systemTemp.absolute.path,
    'yaml-test-suite',
  ]);

  final dir = Directory(testPath);

  // This directory is not empty and has data
  if (dir.existsSync()) return testPath;

  dir.createSync(recursive: true);

  // Set up our tests
  void runCommand(String command, List<String> args) {
    if (Process.runSync(
          command,
          args,
          workingDirectory: testPath,
        )
        case ProcessResult(:final exitCode) when exitCode != 0) {
      throw LoadingError(
        'Failed to load test suite repo. Process exited with a'
        ' "$exitCode" code',
      );
    }
  }

  void runGitCommand(List<String> args) => runCommand('git', args);

  runGitCommand(['init']); // Faux repo. No cloning baby.
  runGitCommand(['remote', 'add', 'origin', _repoUrl]);

  /// Fetch the generated tests from our test-suite fork. Load and run our own
  /// simple tests. Ergo, we can simply checkout the commit we are pinning
  /// ourself to without fetching the entire repo
  runGitCommand(['fetch', 'origin', _testSuiteCommitHash]);
  runGitCommand(['checkout', 'FETCH_HEAD']);
  return testPath;
}

/// Loads `YAML` test suite files from a [matrixDir].
Stream<MatrixTest> loadTests(String matrixDir) async* {
  final testDir = Directory(matrixDir);

  if (!await testDir.exists()) {
    throw LoadingError('Expected a test data directory at path "$matrixDir"');
  }

  /// YAML test data is arranged in directories in 2 distinct formats:
  ///   - Tests that should parse successfully
  ///   - Tests that should fail due to invalid yaml
  ///
  /// Tests that should parse (pun intended) successfully have:
  ///   - Canonical test description
  ///   - Expected output as json
  ///   - Input as yaml
  ///   - output as yaml by tool (not supported yet by this tool)
  ///
  /// Tests that should fail have:
  ///   - Canonical test description
  ///   - A blank error file
  ///   - Input as yaml
  await for (final dir in testDir.list()) {
    if (dir is! Directory) {
      throw LoadingError(
        'Found a test file. Expected a test directory at'
        '"${dir.absolute.path}"',
      );
    }

    final normalized = path.basename(dir.path);

    if (normalized == _gitPath) continue;

    yield await _loadTest(
      normalized,
      dir.list().where((f) => f is File).cast<File>(),
    );
  }
}

/// Loads a single [MatrixTest] from its directory. [testID] is usually the
/// directory's name that uniquely identifies the test.
Future<MatrixTest> _loadTest(String testID, Stream<File> testFiles) async {
  String? metadescription;
  String? yamlInput;
  String? jsonInput;

  final logs = <String>[];
  const snark = 'Was it important?';

  var isError = true;

  String readFileSync(File file) => file.readAsStringSync();

  await for (final file in testFiles) {
    final filename = path.basename(file.path);

    switch (filename) {
      case _jsonInputPath when jsonInput == null:
        isError = false;
        jsonInput = readFileSync(file).trim();

      case _yamlInputPath when yamlInput == null:
        yamlInput = readFileSync(file);

      case _metaPath when metadescription == null:
        metadescription = readFileSync(file);

      default:
        logs.add('Ignored "$filename". $snark');
    }
  }

  // We must have valid yaml input!
  if (yamlInput == null) {
    throw LoadingError('No yaml input found for testID: $testID');
  }

  final meta = '$testID: ${metadescription ?? _emptyMeta}';

  return isError
      ? FailTest(meta, testAsYaml: yamlInput, logs: logs)
      : SuccessTest(
          meta,
          testAsYaml: yamlInput,
          jsonAsDartStr: jsonInput!, // Can never be null if error is false :)
          logs: logs,
        );
}
