# YAML Test Suite Runner

The runner is simple and runs like any program but also explicitly catches the `Error` object and treats it as an `Exception`. This is intentional. The runner's entry point is the [runner.dart](./runner.dart).

```sh
# Clone/fork repo
git clone https://github.com/kekavc24/yaml_dart.git

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
# Run command to get current test suite summary. (abbreviated)
dart runner.dart -m summary
```

An example output is:

```yaml
Tests present: 406
Tests skipped: 8
Tests that ran: 398
Tests passing: 337
Tests failing: 61
```

## Filtering tests

> [!NOTE]
> This assumes you are in the `test/yaml_test_suite` directory

You can only capture tests that failed or were skipped.

```sh
# Outputs the failed tests as `.md` files in the current directory
dart runner.dart --filter skipped failed

# You override the output directory. Defaults to the current directory.
dart runner.dart --filter failed --directory /path/to/some/directory

# Abbreviated
dart runner.dart -f skipped -d /path/to/some/directory
```

This writes `.md` files unique to each test that failed. Each `.md` file has the test id prefixed to the file name and the filter applied as the suffix. The test id corresponds to a valid test in the official [YAML test suite](https://github.com/yaml/yaml-test-suite).

### Structure of failed test's `.md` file

- Heading
  - The test's unique test ID
  - The test's name

- `Test Input` - contains the yaml input for the test
- `Reason Test Failed` - describes why the test failed.
- `Stack Trace` - This section is exclusive to tests whose input was not parsed to completion.

> [!NOTE]
> `Reason Test Failed` and  `Stack Trace` are excluded for skipped tests.

All contributions are welcome (including issues). Use the test outputs above to hunt for:
  - Bugs that need to fixed.
  - Features that need to be implemented.
