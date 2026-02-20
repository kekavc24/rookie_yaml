The parser writes directly to a `BytesToScalar` after stripping the non-content parts of the scalar based on various heuristics stated in the YAML spec. This "write" behaviour is limited to scalars since most YAML source strings are just scalars or a collection of scalars (map or sequence/list).

## Examples

All examples are meant to provide the gist on how to implement a custom `BytesToScalar`. They can be found in the [example/base_64_decoding.dart](https://github.com/kekavc24/rookie_yaml/blob/main/example/base_64_decoding.dart) file.

- [Simple Base64 example](#simple-base64-example)
- [Base64 with Sinks](#pedantic-base64-with-sinks)

### Simple Base64 example

Let's try implementing a delegate that decodes it directly at the parser level.

- The delegate.

```dart
final class SimpleBase64 extends BytesToScalar<String> {
  final _buffer = StringBuffer();

  @override
  void onComplete() {}

  @override
  CharWriter get onWriteRequest => _buffer.writeCharCode;

  @override
  String parsed() => String.fromCharCodes(base64Decode(_buffer.toString()));
}
```

- Binding it to a tag.

```dart
const stringToEncode = 'Wooohoo! Base64 support in YAML for Dart!';
final base64 = base64Encode(stringToEncode.codeUnits);

// Do not take the tag suffix below as a naming convetion. It's just a choice.
final base64Tag = TagShorthand.primary('dart/base64');

// Wooohoo! Base64 support in YAML for Dart!
print(
  loadDartObject<String>(
    YamlSource.string('$base64Tag $base64'),

    // Just that simple!
    triggers: CustomTriggers(
      advancedResolvers: {
        base64Tag: ObjectFromScalarBytes(
          onCustomScalar: () => SimpleBase64(),
        ),
      },
    ),
  ),
);

```

### Base64 with Sinks

Another approach would be using the sinks provided by Dart to decode the string. Using the same string above:

- The delegate

```dart
final class Base64FromBytes extends BytesToScalar<String> {
  Base64FromBytes() {
    _decoder = Base64Decoder()
        .startChunkedConversion(
          StringConversionSink.fromStringSink(_decoded).asUtf8Sink(false),
        )
        .asStringSink();
  }

  /// Buffer for decoded base64
  final _decoded = StringBuffer();

  /// Sink where code points are written.
  late final ClosableStringSink _decoder;

  @override
  void onComplete() {
    _decoder.close();
  }

  @override
  CharWriter get onWriteRequest => _decoder.writeCharCode;

  @override
  String parsed() => _decoded.toString();
}
```

- Decoding

```dart
// Wooohoo! Base64 support in YAML for Dart!
print(
  loadDartObject<String>(
    YamlSource.string('$base64Tag $base64'),
    triggers: CustomTriggers(
      advancedResolvers: {
        base64Tag: ObjectFromScalarBytes(
          onCustomScalar: () => Base64FromBytes(),
        ),
      },
    ),
  ),
);

```
