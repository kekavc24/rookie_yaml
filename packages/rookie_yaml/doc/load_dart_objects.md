The package allows you to load a YAML string as a built-in Dart type without worrying about any wrapper classes that act as a bridge. Built-in types also supported by YAML include:

- `int`, `double`, `bool`, `null`, `String`
- `List`
- `Map`

> [!TIP]
> Each loader accepts a utility extension type called `YamlSource`. You can pass in the `bytes` for a yaml string or the actual string via the `YamlSource.bytes` and `YamlSource.string` constructors respectively.

## Loading a scalar as a built-in Dart type

You can load a single Dart object from a YAML source string/bytes by calling `loadDartObject` which also accepts type params. The function returns a nullable type of the object your provide since the document may be empty.

```dart
// Type inferred automatically. A YAML spec philosophy!
print(
  loadObject<int>(
    YamlSource.string('24'),
  ),
);

print(
  loadObject<bool>(
    YamlSource.string('true'),
  ),
);

print(
  loadObject<double>(
    YamlSource.string('24.0'),
  ),
);

print(
  loadObject<String>(
    YamlSource.string('''
>+
24
'''),
  ),
);
```

Any directives, tags, anchors and aliases are stripped.

```dart
// true
print(loadObject<bool>(
  YamlSource.string('''
%YAML 1.2
%SOME directive
---
!!bool "true"
'''),
  ),
);

// Prints "Am I a ship?"
print(
  loadObject<String>(
    YamlSource.string('&anchor Am I a ship?'),
  ),
);
```

## Loading a Sequence/Mapping as a built-in Dart List/Map

List and Map are returned as `List<Object?>` and `Map<Object?, Object?>`. This is intentional. Later versions may remove this restriction. You may need to explicitly cast it yourself to match the types you want. Providing `List<T>` or `Map<K, V>` will always throw.

The parser, however, guarantees that if a node only exists as type `R` in both Dart and YAML, calling `cast<R>` on the `List<Object?>` returned by the parser will not throw a runtime error. This also applies to a `Map<K, V>` returned as `Map<Object?, Object?>`.

This ensures the parser just works out of the box and doesn't trip itself from any unexpected type constraints.

```dart
// Dart throws. Casting happens after the list is already List<Object?> which Dart won't allow.
print(
  loadObject<List<int>>(
    YamlSource.string('[24, 25]'),
  ),
);

// Okay. [24, 25]
print(
  loadObject<List>(
    YamlSource.string('[24, 25]'),
  ),
);

// Enforce the cast later instead during iteration! Okay. [24, 25]
print(
  loadObject<List>(
    YamlSource.string('[24, 25]'),
  )?.cast<int>(),
);

// Okay. {key: value}
print(
  loadObject<Map>(
    YamlSource.string('{ key: value }'),
  ),
);

// Okay. {24: int, 25: cast}
print(
  loadObject<Map>(
    YamlSource.string('''
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
  loadObject<Map>(
    YamlSource.string('''
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
>   final list = loadObject<List>(
>     YamlSource.string('''
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
>   final list = loadObject<List>(
>     YamlSource.string('''
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

You can also load multiple documents by calling `loadAsDartObjects`. It explicitly returns a `List<Object?>` which contains the built-in Dart types for every root node in each document in the order the parser encountered/parsed them.

```dart
// Prints: [first, second, third]
print(
  loadAllObjects(
    YamlSource.string('''
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
