The package provides an expressive way to declare any `handle`, `tag` or `directive` which favours intent to minimize errors. Let's look at a few examples from earlier.

## Tag Handles

```dart
print(TagHandle.primary()); // !
print(TagHandle.secondary()); // !!
print(TagHandle.named('example')); // !example!
```

## Tag Shorthands

```dart
print(TagShorthand.primary('primary')); // !primary
print(TagShorthand.secondary('int')); // !!int
print(TagShorthand.named('example', 'named')); // !example!named
```

## Global Tags

```dart
// Global tags allow uri or tag shorthand prefixes

/// %TAG !! !no-yaml-uri
///
/// Has 3 parts
///   - %TAG - is implied in the type `GlobalTag`
///   - !! - Secondary tag handle
///   - !no-yaml-uri - tag shorthand with primary tag handle
///
/// The syntax matches the YAML format discussed earlier
print(
  GlobalTag.fromTagShorthand(
    TagHandle.secondary(),
    TagShorthand.primary('no-yaml-uri'),
  ),
);


/// %TAG !meme! meme://look.at.me
///
/// Unlike the previous example, this is a URI.
print(
  GlobalTag.fromTagUri(
    TagHandle.named('meme'),
    'meme://look.at.me',
  ),
);

// %TAG ! !non-specific-looks-naked
print(
  GlobalTag.fromTagShorthand(
    TagHandle.primary(),
    TagShorthand.primary('non-specific-looks-naked'),
  ),
);
```

## Verbatim Tags

Verbatim tags are, well, verbatim. You are to provide the tag in its fully resolved verbatim form unless its a tag shorthand.

```dart
/// Declaring !!int in verbatim:
///
/// 1. Has secondary tag handle. Use the "tag:yaml.org,2002" prefix
/// 2. Kind is "int".
/// 3. Use ":" or "/" as separator
/// 4. However, since this is a uri. We need to escape the "," in the prefix
///   as %2C
///
/// Final uri: "tag:yaml.org%2C2002:int". The object automatically wraps it for
/// you to match yaml requirements.
///
/// In verbatim: !<!tag:yaml.org,2002:int>
print(VerbatimTag.fromTagUri('tag:yaml.org,2002:int'));

/// Tag shorthand: "!my-custom-tag"
///
/// In verbatim: !<!my-custom-tag>
print(
  VerbatimTag.fromTagShorthand(
    TagShorthand.primary('my-custom-tag'),
  ),
);
```

> [!IMPORTANT]
> If you declared a tag shorthand in verbatim:
>
> 1. It cannot have a named tag handle. All verbatim tags are resolved to their global tag prefixes
> 2. It cannot be a `non-specific` tag.
