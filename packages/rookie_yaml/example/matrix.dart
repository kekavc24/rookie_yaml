import 'dart:typed_data';

import 'package:rookie_yaml/rookie_yaml.dart';

/// A matrix.
extension type Matrix._(List<Uint8List> matrix) {}

/// Buffers the lower level matrices from the parsed YAML.
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

void main(List<String> args) {
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

  final matrixTag = TagShorthand.named('matrix', 'View');
  final inputTag = TagShorthand.named('matrix', 'Input');

  final matrix = loadObject<Matrix>(
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
  );

  print(matrix);
}
