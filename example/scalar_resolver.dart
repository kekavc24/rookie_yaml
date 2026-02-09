import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

typedef Interval = ({int min, int max});

void main() {
  //
  // BigInt example. From Dart.
  final resolver = ScalarResolver.onMatch(
    integerTag,
    contentResolver: BigInt.parse,
    toYamlSafe: (value) => '0x${value.toRadixString(16)}',
  );

  var yaml = YamlSource.string('!!int 0x1ffffffffffffffff');

  // As Built-int Dart type
  final parsed = loadDartObject<BigInt>(
    yaml,
    triggers: CustomTriggers(resolvers: [resolver]),
  );

  print(parsed); // 36893488147419103231

  // As a YamlSourceNode which preserves its state.
  final scalar = loadYamlNode<Scalar>(yaml, resolvers: [resolver])!;

  print(scalar.node); // 36893488147419103231
  print(scalar); // 0x1ffffffffffffffff

  //
  //

  //
  // Range in YAML spec example 6.19
  final specResolver = ScalarResolver<Interval>.onMatch(
    integerTag,
    contentResolver: (s) {
      final [min, max] = s.split('-');
      return (min: int.parse(min.trim()), max: int.parse(max.trim()));
    },
    toYamlSafe: (range) => '${range.min} - ${range.max}',
  );

  yaml = YamlSource.string('!!int 1 - 3');

  final range = loadDartObject<Interval>(
    yaml,
    triggers: CustomTriggers(resolvers: [specResolver]),
  );

  print(range); // (min: 1, max: 3)

  // As a YamlSourceNode which preserves its state.
  print(loadYamlNode(yaml, resolvers: [specResolver])); // 1 - 3

  //
  //

  //
  // rookie_yaml doesn't infer DateTime. Create resolver for such a tag.
  final dateTag = TagShorthand.primary('dart/datetime');

  final dateResolver = ScalarResolver<DateTime>.onMatch(
    dateTag,
    contentResolver: DateTime.parse, // Simple. Not complicated.
    toYamlSafe: (date) => date.toString(), // Just for show
  );

  final date = loadDartObject<DateTime>(
    YamlSource.string('$dateTag 19631212 12:12'),
    triggers: CustomTriggers(resolvers: [dateResolver]),
  );

  print(date);
}
