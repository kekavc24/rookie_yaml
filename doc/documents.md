A single YAML source string is considered a YAML document. The presence/absence of directives determines what type of document it is.

## Bare Documents

Clean `YamlDocument` with no directives.

```dart
  const yaml = '''

# Okay if empty
...

Wow! Nice! This looks clean
...
''';

final docs = YamlParser.ofString(yaml).parseDocuments();

print(docs.length); // 2

// True
print(
  docs.every(
    (doc) =>
        doc.hasExplicitEnd &&
        !doc.hasExplicitStart &&
        doc.docType == YamlDocType.bare,
  ),
);
```

## Explicit Documents

Documents with  directive end markers (`---`) and optionally document end markers (`...`). Why optionally? The directive end markers signify the start of a document.

```dart
  const yaml = '''
--- # Ends after the next comment
    # LFG
...

---
"This one has a double quoted scalar, but no doc end"

---
status: Started immediately the marker was seen.
''';

final docs = YamlParser.ofString(yaml).parseDocuments();

print(docs.length); // 3

// True
print(
  docs.every(
    (doc) => doc.hasExplicitStart && doc.docType == YamlDocType.explicit,
  ),
);
```

## Directive Documents

Documents with directives. The directives must always end with marker (`---`) even if the document is empty!

```dart
  const yaml = '''
%YAML 1.1
%SUPPORT on that version is limited
%TAG !for-real! !yah-for-real
---

"You can just do this things. Do them with version 1.2+ features"
''';

final doc = YamlParser.ofString(yaml).parseDocuments().first;

// True
print(
  doc.hasExplicitStart &&
      doc.docType == YamlDocType.directiveDoc &&
      doc.tagDirectives.isNotEmpty &&
      doc.otherDirectives.isNotEmpty &&
      doc.versionDirective == YamlDirective.ofVersion('1.1'),
);
```
