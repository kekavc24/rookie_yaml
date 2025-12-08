import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/yaml_loaders.dart';
import 'package:yaml_test_suite_runner/yaml_test_suite_runner.dart';

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
  ..addFlag(
    'save-failed',
    help: 'Whether the runner should save failing tests.',
  )
  ..addOption(
    'directory',
    abbr: 'd',
    help: 'Directory to save failed tests when "save-failed" is true.',
  );

extension on ArgResults {
  RunnerArgResult get argInfo {
    final saveFailed = this['save-failed'] as bool;

    return (
      showUsage: this['help'],
      mode: saveFailed ? 'rate' : this['mode'],
      saveFailed: saveFailed,
      directory: this['directory'],
    );
  }
}

typedef RunnerArgResult = ({
  bool showUsage,
  String mode,
  bool saveFailed,
  String? directory,
});

void _printUsage() {
  print('Usage: runner.dart <flags> [arguments]');
  print(_argParser.usage);
}

void main(List<String> arguments) async {
  try {
    final (:showUsage, :mode, :saveFailed, :directory) = _argParser
        .parse(arguments)
        .argInfo;

    if (showUsage) {
      return _printUsage();
    }

    final output = DummyWriter.forRunner(directory, saveFailed: saveFailed);
    final equality = DeepCollectionEquality();

    final runner = TestRunner(
      parseFunction: (yaml) => loadAsDartObjects(
        YamlSource.string(yaml),
        throwOnMapDuplicate: true,
        logger: (_, _) {},
      ),
      sourceComparator: (parsed, expected) =>
          equality.equals(parsed, expected) ||
          parsed.toString() == expected.toString(),
      writer: output,
    );

    await runner.runTestSuite();

    final (:passRate, :summary) = runner.counter.getSummary();
    print(mode == 'rate' ? passRate : summary);
    output.onComplete(summary);
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    _printUsage();
  }
}
