import 'package:rookie_yaml/rookie_yaml.dart';

final class YamlSet<T> extends MappingToObject<T, T?, Set<T>> {
  final _set = <T>{};

  @override
  bool accept(T key, T? value) {
    _set.add(key);
    return true;
  }

  @override
  Set<T> parsed() => _set;
}

void main() {
  // Set<String> for flow maps
  final setFromFLow = loadObject<Set<String>>(
    YamlSource.string('$setTag { hello, hello, world, world }'),
    triggers: CustomTriggers(
      advancedResolvers: {
        setTag: ObjectFromMap(
          onCustomMap: () => YamlSet<String>(),
        ),
      },
    ),
  );

  print(setFromFLow); // {hello, world}

  // Set<int> for block maps
  final setFromBlock = loadObject<Set<int>>(
    YamlSource.string('''
$setTag
? 10
? 10
? 20
? 24
'''),
    triggers: CustomTriggers(
      advancedResolvers: {
        setTag: ObjectFromMap(
          onCustomMap: () => YamlSet<int>(),
        ),
      },
    ),
  );

  print(setFromBlock); // {10, 20, 24}
}
