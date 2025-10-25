import 'dart:convert';

import 'package:rookie_yaml/rookie_yaml.dart';

void main(List<String> args) {
  /// Let's decode json embedded in a double quoted scalar. This is for
  /// demo purposes.
  final object = ['This', 'is', 'my', 'json'];

  final jsonTag = TagShorthand.fromTagUri(TagHandle.primary(), 'json');

  final jsonResolver = Resolver.content(
    jsonTag,
    contentResolver: json.decode,
    toYamlSafe: json.encode,
  );

  final yaml =
      '''
# Embed json object in a double quoted scalar.
# It works bro. Trust

$jsonTag "${json.encode(object).replaceAll('"', r'\"')}"
''';

  // Embedded in the scalar
  final decodeJson = loadYamlNode<Scalar>(
    source: yaml,
    resolvers: [jsonResolver],
  )?.value;

  assert(decodeJson is List, 'Fake news!!');
  print(yamlCollectionEquality.equals(decodeJson, object)); // True
  print(decodeJson); // [This, is, my, json]
}
