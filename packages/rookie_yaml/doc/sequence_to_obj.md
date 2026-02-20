The parser pushes sequence/list entries after parsing them into a `SequenceToObject<E, T>` delegate via its `accept` method.

## Matrix example

The example is meant to show you how to implement a `SequenceToObject` and use the `TagInfo` mixin. This code can be found in the [example/matrix.dart](https://github.com/kekavc24/rookie_yaml/blob/main/example/matrix.dart) file.

Consider a 2D matrix that can have an arbitrary number of sequences with a random number of integers as entries whose sequences can be referenced more than once. Thus we have 3 levels:

- A top level matrix
  - A sequence/list/array of integers.
    - integers.

### Matrix input delegate

Since integers are built-in Dart types, we don't need to have a tag for them.

```dart
/// Buffers the bytes in each list.
final class MatrixInput extends SequenceToObject<int, Uint8List> with TagInfo {
  MatrixInput() {
    _persisted = null;
  }

  /// Persisted for all objects that use it during parsing.
  static final _input = BytesBuilder(copy: false);

  /// Persists this object in case it's an anchor.
  static Uint8List? _persisted;

  @override
  void accept(int input) => _input.addByte(input);

  @override
  Uint8List parsed() {
    _persisted ??= _input.takeBytes();
    print(localTagInfo());
    return _persisted!;
  }
}
```

### Matrix delegate

Our actual matrix. Let's say we don't trust the parser at this level.

```dart
/// A matrix.
extension type Matrix._(List<Uint8List> matrix) {}

/// Buffers the lower level matrices from the parsed YAML
final class YamlMatrix extends SequenceToObject<Uint8List, Matrix>
    with TagInfo {
  final _matrix = <Uint8List>[];

  @override
  void accept(Uint8List input) => _matrix.add(input);

  @override
  Matrix parsed() {
    print(localTagInfo());
    return Matrix._(_matrix);
  }
}
```

### Bring it all together

```dart
final matrixTag = TagShorthand.named('matrix', 'View');
final inputTag = TagShorthand.named('matrix', 'Input');

const yaml = '''
%TAG !matrix! !dart/matrix
---
!matrix!View
- !matrix!Input &repeat [1, 6, 19, 63]
- *repeat
- *repeat
- !matrix!Input [12, 12, 19, 63]
- !matrix!Input [20, 10, 10, 10]
- !matrix!Input [1, 4, 20, 24]
''';

// MatrixInput's resolved tag:
//    - globalTag: %TAG !matrix! !dart/matrix
//    - suffix: !matrix!Input
//
// YamlMatrix's resolved tag:
//    - globalTag: %TAG !matrix! !dart/matrix
//    - suffix: !matrix!View
//
// Output (prettified) with aliases unpacked:
//   [
//    [1, 6, 19, 63], [1, 6, 19, 63], [1, 6, 19, 63],
//    [12, 12, 19, 63], [20, 10, 10, 10], [1, 4, 20, 24]
//   ]
print(
  loadDartObject<Matrix>(
    YamlSource.string(yaml),
    triggers: CustomTriggers(
      advancedResolvers: {
        matrixTag: ObjectFromIterable(
          onCustomIterable: () => YamlMatrix(),
        ),
        inputTag: ObjectFromIterable(
          onCustomIterable: () => MatrixInput(),
        ),
      },
    ),
  ),
);
```
