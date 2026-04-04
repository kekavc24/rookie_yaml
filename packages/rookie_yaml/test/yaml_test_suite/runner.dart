import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';
import 'package:yaml_test_suite_runner/yaml_test_suite_runner.dart';

import 'reporter.dart';

final _argParser = ArgParser()
  ..addFlag('help', abbr: 'h', help: 'Prints usage')
  ..addOption(
    'mode',
    abbr: 'm',
    defaultsTo: 'rate',
    allowed: ['rate', 'summary'],
    allowedHelp: {
      'rate': 'Prints the test suite pass rate.',
      'summary': 'Prints the test summary.',
    },
  )
  ..addMultiOption(
    'filters',
    abbr: 'f',
    help:
        'Triggers the runner to save skipped/failed tests based on the'
        ' options provided.',
    allowed: ['skipped', 'failed'],
  )
  ..addOption(
    'directory',
    abbr: 'd',
    help: 'Directory to save failed tests when "save-failed" is true.',
  );

extension on ArgResults {
  RunnerArgResult get argInfo {
    final filtered = multiOption('filters').toSet();

    return (
      showUsage: flag('help'),
      mode: option('mode')!,
      filters: filtered,
      directory: option('directory'),
    );
  }
}

typedef RunnerArgResult = ({
  bool showUsage,
  String mode,
  Set<String> filters,
  String? directory,
});

void _printUsage() {
  print('Usage: runner.dart <flags> [arguments]');
  print(_argParser.usage);
}

void main(List<String> arguments) async {
  try {
    final (:showUsage, :mode, :filters, :directory) = _argParser
        .parse(arguments)
        .argInfo;

    if (showUsage) {
      return _printUsage();
    }

    final runnerDir =
        directory ?? path.joinAll([Directory.current.path, 'suite-results']);
    final reporter = filters.isNotEmpty
        ? TestSuiteReporter(runnerDir, filters)
        : Metrics();

    final runner = TestSuiteRunner(
      runner: TestRunner(
        reporter,
        multiDocLoader: (yaml) => loadAllObjects(
          YamlSource.simpleString(yaml),
          throwOnMapDuplicate: true,
          logger: (_, _) {},
        ),
        comparator: (parsed, expected) =>
            yamlCollectionEquality.equals(parsed, expected) ||
            parsed.toString() == expected.toString(),
      ),
    );

    await runner.runTestSuite();
    print(
      mode == 'rate'
          ? calculatePassRate(reporter).toStringAsFixed(2)
          : suiteSummary(reporter),
    );
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    _printUsage();
  }
}
