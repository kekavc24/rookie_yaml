import 'dart:convert';

import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';

import '../test/helpers/test_resolvers.dart';

void main(List<String> args) {
  // Let's decode json embedded in a double quoted scalar. This is for demo
  // purposes.
  final object = ['This', 'is', 'my', 'json'];

  final jsonTag = TagShorthand.fromTagUri(TagHandle.primary(), 'json');

  final jsonResolver = ScalarResolver.onMatch(
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
    YamlSource.string(yaml),
    resolvers: [jsonResolver],
  )?.value;

  assert(decodeJson is List, 'Fake news!!');
  print(yamlCollectionEquality.equals(decodeJson, object)); // True
  print(decodeJson); // [This, is, my, json]

  // We can even take this further and load the scalar as the list we have
  // decoded directly as a Dart object
  final decodedList = loadDartObject<List>(
    YamlSource.string(yaml),
    triggers: TestTrigger(resolvers: [jsonResolver]),
  );

  print(decodedList); // [This, is, my, json]
}
