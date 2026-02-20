# YAML Test Suite Runner

The runner is simple and runs like any program but also explicitly catches the `Error` object and treats it as an `Exception`. This is intentional. The runner's entry point is the [runner.dart](./runner.dart).

```sh
# Clone/fork repo
git clone https://github.com/kekavc24/rookie_yaml.git

# Open folder. Run:
dart pub get

# Open and navigate to test suite runner directory
cd test/yaml_test_suite

# Run command to see usage
dart runner.dart -h
```

## Printing the current pass rate

> [!NOTE]
> This assumes you are in the `test/yaml_test_suite` directory

```sh
# Run command to get current test suite pass rate
dart runner.dart --mode rate

# Excluding the option still prints the pass rate
dart runner.dart
```

## Printing the test suite summary

> [!NOTE]
> This assumes you are in the `test/yaml_test_suite` directory

```sh
# Run command to get current test suite pass rate
dart runner.dart --mode summary
```

An example output is:

```yaml
Total Tests: 402
Test Summary:
  Total Tests Passing: 324
  Average Pass Accuracy (%): 80.60

  # Tests meant to be parsed correctly that passed
  Success Test Ratio (%):
    Of Success Tests: 78.41
    Of Tests Passing: 76.23

  # Tests meant to fail that failed
  Error Test Ratio (%):
    Of Error Tests: 88.51
    Of Tests Passing: 23.77

```

## Getting failed tests

> [!NOTE]
> This assumes you are in the `test/yaml_test_suite` directory

```sh
# Outputs the failed tests as `.md` files in the current directory
dart runner.dart --save-failed

# You override the output directory
dart runner.dart --save-failed --directory /path/to/some/directory

# Abbreviated
dart runner.dart --save-failed -d /path/to/some/directory
```

This command always prints the pass rate irrespective of the `--mode` option provided. The files written to the current directory include:

- `#_summary_#.yaml` - this contains the test [summary](#printing-the-test-suite-summary) highlighted earlier.

- `.md` files unique to each test that failed. Each `.md` file has the test id as its file name. The test id corresponds to a valid test in the official [YAML test suite](https://github.com/yaml/yaml-test-suite) as flattened in [here](https://github.com/kekavc24/yaml_test_suite_dart/tree/generated-tests-dart).

### Structure of failed test's `.md` file

- Heading
  - The test's unique test ID
  - The test's description

- `Test Input` - contains the yaml input for the test
- `Reason Test Failed` - describes why the test failed.
- `Stack Trace` - This section is exclusive to tests whose input was not parsed to completion.

All contributions are welcome (including issues). Use the test outputs above to hunt for:
  - Bugs that need to fixed.
  - Features that need to be implemented.
