# YAML Test Suite Runner

The runner is simple and runs like any program but also explicitly catches the `Error` object and treats it as an `Exception`. This is intentional. The runner's entry point is the [matrix_runner.dart](./matrix_runner.dart).

```sh
# Clone/fork repo
git clone https://github.com/kekavc24/rookie_yaml.git

# Open and navigate to test suite runner directory
cd test/yaml_matrix_tests

# Run command to get current test suite pass rate
dart matrix_runner.dart --no-file-output
```

Running the command above prints the current pass rate. If you need a file with the captured errors, omit the `--no-file-output` flag. In this case, the script will also create a `test.rate` file in the directory you run the command from.

## `test.rate` format

- The first two lines contain the summary:
  - `Test Info` - provides a simple ratio of the number of tests that passed to the number of tests run. eg. `282/402`
  - `Test Success Rate` - percentage of tests that passed.

- Self contained blocks of information for each test that failed in the format described below:

### Header

The header contains the test id and meta description of the test surrounded by a leading `<++++` and trailing `++++>`.

- The test id accurately describes a flattened directory where the test was extracted from in the official raw [`YAML` test suite](https://github.com/yaml/yaml-test-suite/tree/data) data. The subdirectories are preceded by a `-` where `DK95-05` would represent `DK95/05`.

- The test description.

Examples:

- `<++++ DK95-05: Tabs that look like indentation ++++>` - a test found in `DK95/05` directory that tests for `Tabs that look like indentation`
- `<++++ X38W: Aliases in Flow Objects ++++>` - a test found in `X38W` directory that tests for `Aliases in Flow Objects`

## Body

Describes why the test failed when the parser attempted to parse the yaml input.

### Test Output examples

> [!IMPORTANT]
> This is a fail-fast parser.
>
> The errors will reflect the errors thrown by the copy of the parser (repo) you have locally.

- The node was parsed successfully but the test failed because the expected node output doesn't match that provided by YAML.

```text
<++++ L24T-01: Trailing line of spaces ++++>

Failed with the following messages:
  Expected node string: [{foo: x

}]
  Found: [{foo: x
 }]

<------------------------------------------>
```

- The test was supposed to pass but the parser threw an error.

```text
<++++ X38W: Aliases in Flow Objects ++++>

Failed with the following messages:
  ParserException[Line 0, Column 25, Offset 25]: Flow map cannot contain duplicate entries by the same key

  { &a [a, &b b]: *b, *a : [c, *b, d]}
                      ^^^^^^

<--------------------------------------->
```

- The test was supposed to fail but the parser parsed a complete node. This is a great indicator of a bug.

```text
<++++ Y79Y-009: Tabs in various contexts ++++>

Failed with the following messages:
  Expected test to fail but found parsed node: [{{key: null}: {key: null}}],

<-------------------------------------------->
```

- The test completely and no node could be parsed. This is a great indicator of a feature/behaviour not supported by the parser.

```text
<++++ 9KAX: Various combinations of tags and anchors ++++>

Failed with the following messages:
  ParserException[Line 13, Column 0, Offset 80]: Internal Parser Error. Should not be parsing block node here

  &a4 !!map
  ^^^^^^^^^
  &a5 !!str key5: value4
  ^

<-------------------------------------------------------->
```

All contributions are welcome (including issues). Use the test outputs above to hunt for:
  - Bugs that need to fixed.
  - Features that need to be implemented.
