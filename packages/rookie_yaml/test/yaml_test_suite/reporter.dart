import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml_test_suite_runner/yaml_test_suite_runner.dart';

/// Writes the preamble information for a failing/skipped [test] to a `.md`
/// [file].
void _writeTestPreamble(IOSink file, YamlTest test) {
  final YamlTest(:testID, :name, :tags, :yaml) = test;
  file
    ..writeln('# ${test.testID}${name == null ? '' : ': $name'}')
    ..writeln();

  if (tags != null && tags.isNotEmpty) {
    file
      ..writeln('Test suite tags:')
      ..writeln(tags.map((t) => '- $t').join('\n'))
      ..writeln();
  }

  if (yaml.isNotEmpty) {
    file
      ..writeln('## Test Input\n')
      ..writeln('```yaml\n$yaml\n```')
      ..writeln();
  }
}

/// Helper function that opens a files.
@pragma('vm:prefer-inline')
Future<void> _writeFile({
  required String directory,
  required String filename,
  required void Function(IOSink file) write,
}) async {
  try {
    final file = (File(
      path.joinAll([directory, filename]),
    )..createSync(recursive: true)).openWrite(mode: FileMode.append);

    write(file);
    await file.flush();
    await file.close();
  } on IOException catch (e) {
    print(e.toString());
  }
}

/// Creates an `.md` file for a skipped [test].
Future<void> _skippedTest(String directory, YamlTest test) async => _writeFile(
  directory: directory,
  filename: '${test.testID}-skipped.md',
  write: (file) => _writeTestPreamble(file, test),
);

/// Writes the content of a [failing] test that was expected to pass to its
/// respective `.md` [file].
void _writeFailedInput(IOSink file, List<FailedOutputCheck> failing) {
  file.writeln(
    'Each subtitle indicates at what stage the parser failed when trying to'
    ' compare the parsed input with the provided reference outputs.\n',
  );

  for (final (:reference, :input, :error, :trace) in failing) {
    final (title, desc) = reference.isEmpty
        ? (
            'Actual Test Input',
            "The parser failed when parsing the actual test's input.",
          )
        : (reference, "The parsed object doesn't match the reference output");

    file
      ..writeln('### $title')
      ..writeln()
      ..writeln(desc)
      ..writeln();

    if (input.isNotEmpty) {
      file
        ..writeln('```yaml')
        ..writeln(input)
        ..writeln('```')
        ..writeln();
    }

    file
      ..writeln('```text')
      ..writeln(error)
      ..writeln('```');

    if (trace case String str when str.isNotEmpty) {
      file.writeln('\n```text\n$str\n```');
    }
  }
}

/// Creates a `.md` file for a failed test.
Future<void> _failedTest(String directory, FailingTest result) async {
  final FailingTest(:onFail, :test) = result;

  return _writeFile(
    directory: directory,
    filename: '${test.testID}-failed.md',
    write: (file) {
      _writeTestPreamble(file, test);
      file.writeln('## Reason Test Failed\n');
      return test.fail
          ? file.writeln(onFail)
          : _writeFailedInput(file, onFail as List<FailedOutputCheck>);
    },
  );
}

/// No operation.
void _noOp<T>(T object) {}

/// A custom test suite reporter for `package:rookie_yaml`.
final class TestSuiteReporter extends Metrics {
  TestSuiteReporter(String directory, Set<String> filters)
    : onSkipped = filters.contains('skipped')
          ? ((t) => _skippedTest(directory, t))
          : _noOp,
      onFailed = filters.contains('failed')
          ? ((r) => _failedTest(directory, r))
          : _noOp;

  /// Called when a test is skipped.
  final void Function(YamlTest test) onSkipped;

  /// Called when a test fails.
  final void Function(FailingTest result) onFailed;

  @override
  void reportSkipped(TestResult result) {
    onSkipped(result.test);
    super.reportSkipped(result);
  }

  @override
  void reportFailed(TestResult result) {
    onFailed(result as FailingTest);
    super.reportFailed(result);
  }
}

/// Calculates the pass rate.
double calculatePassRate(Metrics metrics) =>
    (metrics.totalPassing / metrics.totalRan) * 100;

/// Creates a summary from the suite's [metrics].
String suiteSummary(Metrics metrics) =>
    '''
Tests present: ${metrics.total}
Tests skipped: ${metrics.totalSkipped}
Tests that ran: ${metrics.totalRan}
Tests passing: ${metrics.totalPassing}
Tests failing: ${metrics.totalFailing}''';
