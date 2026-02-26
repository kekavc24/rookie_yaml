/// A wrapper class that safely wraps types inferred from content parsed
/// within a scalar.
sealed class ScalarValue<T> {
  ScalarValue();

  /// Inferred value
  T get value;

  @override
  String toString() => value.toString();

  @override
  bool operator ==(Object other) => value == other;

  @override
  int get hashCode => value.hashCode;
}

/// Any `Dart` type abstraction.
abstract base class _InferredValue<T> extends ScalarValue<T> {
  _InferredValue(this.value);

  @override
  final T value;
}

/// A safe representation of an integer parsed from a `YAML` source string.
/// This wrapper guarantees that an integer will be dumped in the same form
/// as it was parsed.
final class YamlSafeInt extends _InferredValue<int> {
  YamlSafeInt(super.value, this.radix);

  /// A valid number base
  final int radix;

  @override
  String toString() {
    final prefix = switch (radix) {
      8 => '0o',
      16 => '0x',
      _ => '',
    };

    return '$prefix${value.toRadixString(radix)}';
  }
}

/// A wrapper class for `null`. While it may seem counterintuitive, some
/// `null`s in `YAML` cannot be represented/non-existent but are implicit such
/// as:
///   - Missing key from a flow/block map
///   - Missing value from a block list
final class NullView extends _InferredValue<String?> {
  NullView(String nullStr) : isVirtual = nullStr.isEmpty, super(null);

  final bool isVirtual;

  @override
  String toString() => 'null';
}

/// Any `Dart` value that is not an [int] or `null`.
final class DartValue<T> extends _InferredValue<T> {
  DartValue(super.value);
}

/// A value inferred using a custom [ContentResolver] tag.
final class CustomValue<T> extends _InferredValue<T> {
  CustomValue(super.value, {required this.toYamlSafe});

  /// Maps the [T] object back to a dumpable string.
  final String Function(T value) toYamlSafe;

  @override
  String toString() => toYamlSafe(value);
}
