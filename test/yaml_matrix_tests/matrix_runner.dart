import 'dart:io';

import 'package:rookie_yaml/src/parser/yaml_loaders.dart';

import 'test_loader.dart';

/// A runner that asynchronously runs the tests and captures all [Exception]s
/// and [Error]s in the current isolate. Doesn't use zones.
final class MatrixRunner {
  /// [MatrixTest]s to run.
  final Stream<MatrixTest> tests;

  MatrixRunner(this.tests);

  /// Runs all [tests] asynchronously.
  Stream<MatrixResult> runTests() async* {
    await for (final test in tests) {
      yield _runTest(test);
    }
  }

  /// Blocks and runs a single test and returns a [MatrixResult].
  MatrixResult _runTest(MatrixTest test) {
    final MatrixTest(:meta, :expectedResult, :testAsYaml) = test;

    MatrixResultType result;
    final messages = <String>[];
    var parsedNodeString = '';

    void markAsInvalid() => result = MatrixResultType.invalidPass;

    try {
      parsedNodeString = loadNodes(source: testAsYaml).toList().toString();
      result = MatrixResultType.pass;
    } catch (e) {
      result = MatrixResultType.fail;
      messages.addAll(e.toString().split('\n'));
    }

    final ranSuccessfully = test.isSuccess(result);

    switch (test) {
      case SuccessTest(:final jsonAsDartStr):
        {
          if (!ranSuccessfully) {
            markAsInvalid();
          } else if (jsonAsDartStr != parsedNodeString) {
            markAsInvalid();
            messages.addAll([
              'Expected node string: $jsonAsDartStr',
              'Found: $parsedNodeString',
            ]);
          }
        }

      case FailTest _:
        {
          if (!ranSuccessfully) {
            markAsInvalid();
            messages.add(
              'Expected test to fail but found parsed node: $parsedNodeString',
            );
          }
        }
    }

    return (metaInfo: meta, resultType: result, messages: messages);
  }
}

String _footer(int headerLength) => '<${'-' * (headerLength - 2)}>';

void main(List<String> args) async {
  final runner = MatrixRunner(loadTests(fetchTestData()));

  const pad = '  ';

  var testCount = 0;
  var success = 0;

  final fails = <String>[];

  await for (final (:resultType, :messages, :metaInfo) in runner.runTests()) {
    ++testCount;

    if (resultType == MatrixResultType.invalidPass) {
      final header = '<++++ ${metaInfo.trim()} ++++>';

      fails.add('''
$header

Failed with the following messages:
${messages.map((e) => '$pad$e').join('\n')}

${_footer(header.length)}''');
    } else {
      ++success;
    }
  }

  final passRate = ((success * 100) / testCount);

  // Output to console
  print('${passRate.floor()}');

  // Create file if no flag was passed in
  if (!args.contains('--no-file-output')) {
    File('test.rate').writeAsStringSync(
      '''
Test Info: $success/$testCount tests
Test Success Rate: ${passRate.toStringAsFixed(2)}%

${fails.join('\n\n')}
''',
    );
  }
}
