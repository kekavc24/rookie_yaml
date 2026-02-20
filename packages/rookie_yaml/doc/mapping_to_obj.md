The parser pushes a map's key and value at the same time after parsing them into a `MappingToObject<K, V, T>` delegate via its `accept` method.

## YamlSet example

The example is meant to provide the gist on how to implement a `MappingToObject`. This code can be found in the [example/yaml_set.dart](https://github.com/kekavc24/rookie_yaml/blob/main/example/yaml_set.dart) file.

Most (if not all) programming languages use a hashtable under-the-hood to implement a set which YAML [mentions][set_mention] but doesn't include as part of the official YAML 1.2 spec. Let's create a generic set that accepts elements.

- The delegate

```dart
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
```

- Binding it to the tag. The package exports the `!!set` tag which was supported in earlier YAML 1.1.* versions.

```dart
// {hello, world}
print(
  loadDartObject<Set<String>>(
    // flow map
    YamlSource.string('$setTag { hello, hello, world, world }'),
    triggers: CustomTriggers(
      advancedResolvers: {
        setTag: ObjectFromMap(
          onCustomMap: () => YamlSet<String>(),
        ),
      },
    ),
  ),
);

print(
  // {10, 20, 24}
  loadDartObject<Set<int>>(
    // block maps
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
  )
);
```

[set_mention]: https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models:~:text=Example%202.25%20Unordered%20Sets
