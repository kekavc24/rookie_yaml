import 'dart:convert';

import 'package:rookie_yaml/rookie_yaml.dart';

final class SimpleBase64 extends BytesToScalar<String> {
  final _buffer = StringBuffer();

  @override
  void onComplete() {}

  @override
  CharWriter get onWriteRequest => _buffer.writeCharCode;

  @override
  String parsed() => String.fromCharCodes(base64Decode(_buffer.toString()));
}

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

void main(List<String> args) {
  const stringToEncode = 'Wooohoo! Base64 support in YAML for Dart!';
  final base64 = base64Encode(stringToEncode.codeUnits);

  // Do not take the tag suffix below as a naming convetion. It's just a choice.
  final base64Tag = TagShorthand.primary('dart/base64');

  // Using [SimpleBase64] that parses when [parsed] is called.
  final base64StrToString = loadObject<String>(
    YamlSource.string('$base64Tag $base64'),
    triggers: CustomTriggers(
      advancedResolvers: {
        base64Tag: ObjectFromScalarBytes(
          onCustomScalar: () => SimpleBase64(),
        ),
      },
    ),
  );

  // Using [Base64FromBytes] with sinks
  final bytesToString = loadObject<String>(
    YamlSource.string('$base64Tag $base64'),
    triggers: CustomTriggers(
      advancedResolvers: {
        base64Tag: ObjectFromScalarBytes(
          onCustomScalar: () => Base64FromBytes(),
        ),
      },
    ),
  );

  print(bytesToString == stringToEncode); // True
  print(base64StrToString == stringToEncode); // True
}
