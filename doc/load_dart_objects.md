The package allows you load a YAML string as a built-in Dart type without worrying about any wrapper classes that act as a bridge. Built-in types also supported by YAML include:

- `int`, `double`, `bool`, `null`, `String`
- `List`
- `Map`

> [!TIP]
> Each loader accepts a utility extension type called `YamlSource`. You can pass in the `bytes` for a yaml string or the actual string via the `YamlSource.bytes` and `YamlSource.string` constructors respectively.

## Loading a scalar as a built-in Dart type

You can load a single Dart object from a YAML source string/bytes by calling `loadDartObject`. It allows you provide a type if are privy to the node present. The function returns a nullable type of the object your provide since the document may be empty.

```dart
// Type inferred automatically. A YAML spec philosophy!
print(loadDartObject<int>(source: YamlSource.string('24')));

print(loadDartObject<bool>(source: YamlSource.string('true')));

print(loadDartObject<double>(source: YamlSource.string('24.0')));

print(loadDartObject<String>(source: YamlSource.string('''
>+
 24
''')));
```

Any directives, tags, anchors and aliases are stripped.

```dart
print(loadDartObject<bool>(source: YamlSource.string('''
%YAML 1.2
%SOME directive
---
!!bool "true"
''')));

print(loadDartObject<String>(source: YamlSource.string('&anchor Am I a ship?'))); // Prints "Am I a ship?"
```

## Loading a Sequence/Mapping as a built-in Dart List/Map

List and Map are returned as `List<dynamic>` and `Map<dynamic, dynamic>`. This is intentional. Later versions may remove this restriction. You may need to explicitly cast it yourself to match the types you want. Providing `List<T>` or `Map<K, V>` will always throw.

The parser, however, guarantees that if a node only exists as type `R` in both Dart and YAML, calling `cast<R>` on the `List<dynamic>` returned by the parser will not throw a runtime error. This also applies to a `Map<K, V>` returned as `Map<dynamic, dynamic>`.

This ensures the parser just works out of the box and doesn't trip itself from any unexpected type constraints.

```dart
// Dart throws. Casting happens after the list is already List<dynamic> which Dart won't allow.
print(loadDartObject<List<int>>(source: YamlSource.string('[24, 25]')));

print(loadDartObject<List>(source: YamlSource.string('[24, 25]'))); // Okay. [24, 25]

// Enforce the cast later instead during iteration!
print(loadDartObject<List>(source: YamlSource.string('[24, 25]'))?.cast<int>()); // Okay. [24, 25]

print(loadDartObject<Map>(source: YamlSource.string('{ key: value }'))); // Okay. {key: value}

// Okay. {24: int, 25: cast}
print(
  loadDartObject<Map>(
    source: YamlSource.string('''
24: int
25: cast
'''),
  )?.cast<int, String>(),
);
```

Stripped anchors and aliases are evident in lists/maps. Each node is direct reference to the node it was aliased to (even maps and lists. Be careful!!)

```dart
// Prints: {value: [flow, value], flow: [flow, value]}
print(
  loadDartObject<Map>(
    source: YamlSource.string('''
&scalar value: &flow-list [ &flow flow, *scalar ]
*flow : *flow-list
'''),
  ),
);
```

> [!TIP]
> You can configure the parser to dereference `List` and `Map` aliases, by default. The `List` or `Map` alias will be copied each time the parser needs it.
>
> ```dart
>   final list = loadDartObject<List>(
>     source: YamlSource.string('''
> - &list [ flow, &map { key: value } ]
> - *list
> - *map
>   '''),
>   )!;
>
>   print(list[0] == list[1]); // Same list reference. True
>   print(list[0][1] == list[2]); // Same map reference. True
> ```
>
> ```dart
>   final list = loadDartObject<List>(
>     source: YamlSource.string('''
> - &list [ flow, &map { key: value } ]
> - *list
> - *map
>   '''),
>     dereferenceAliases: true,
>   )!;
>
>   print(list[0] == list[1]); // Copies list. False.
>   print(list[0][1] == list[2]); // Copies map. False
> ```

## Loading multiple documents

You can also load multiple documents by calling `loadAsDartObjects`. It explicitly returns a `List<dynamic>` which contains the built-in Dart types for every root node in each document in the order the parser encountered/parsed them.

```dart
// Prints: [first, second, third]
print(
  loadDartObjects(
    source: YamlSource.string('''
# This document has no directives but uses doc end chars "..."

"first"
...

%THIS document
--- # Has a custom directive

"second"

--- # This document start here
    # No directives. Direct to node

"third"
'''),
  ),
);
```
