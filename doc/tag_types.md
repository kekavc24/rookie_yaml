Based on the tag's use, there are 4 ways you can declare a `YAML` tag:

- As a tag shorthand
- As a non-specific tag
- As a global tag
- As a verbatim tag

## Tag shorthand

This represents a valid `tag handle` and non-empty `suffix`. This is the tag declared with(out) the `anchor`. Using the example in the tag handle paragraph:

```yaml
%TAG !example! !named-must-have-global
---
[
  # Custom primary tag
  #
  # "!" - tag handle
  # "my-tag" - suffix
  #
  !my-tag scalar,

  # Secondary tag
  #
  # "!!" - tag handle
  # "int" - suffix
  #
  !!int 24,

  # Named tag
  #
  # "!example! - tag handle
  # "-tag" - suffix
  #
  !example!-tag just-a-value,
]
```

## Non-specific tag

This is a primary tag handle without a suffix which is, objectively, just a `tag shorthand` with an empty suffix.

```yaml
[
  # Non-specific tag "!"
  ! scalar,

  ! 24,

  ! just-a-value,
]
```

> [!IMPORTANT]
> No other tag handle can be used as a non-specific tag. Only primary tag handles.

## Global Tag

A global tag *MUST* be declared with other directives before the document is parsed. This is the only tag form that must be known ahead of time. It is restricted to a single line with three parts (separated by whitespace) in the following order:

1. Directive - `%TAG`

2. Handle - The `tag handle` this global is a prefix to.

3. Prefix - a valid uri or `tag shorthand` that is the prefix to the handle. The uri must have a scheme.

Every `handle` can only have a single global tag per document. Every global tag is restricted to the document it was declared in. This means a handle in one `YamlDocument` cannot be the same in another `YamlDocument`. This can only be true if you explicitly declare that global tag for each document!

By default, the secondary tag handle (`!!`) resolves to the `YAML` tag prefix, `tag:yaml.org,2002:`.

> [!IMPORTANT]
> A named tag handle must have a corresponding global tag

```yaml
%TAG ! !non-specific-looks-naked
%TAG !! !no-yaml-uri-in-
%TAG !meme! meme://look.at.me
---
[
  # Resolved as: !non-specific-looks-naked
  ! "I am so non-specific",

  # Resolved as: !no-yaml-uri-in-int
  !!int 24,

  # Resolved as: !meme://look.at.me:iAmTheCaptainNow
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]

--- # This next document has no global tags.
    # For the same node, the parser throws when it sees the named tag handle
[
  # Resolved as: !!str.
  # Non-specific tags let the parser resolve it to a specific tag based in its
  # kind (type)
  ! "I am so non-specific",

  # Resolved as: !!int
  !!int 24,

  # Parser throws here
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]
```

## Verbatim tag

Every valid (un)resolved tag can be declared in "verbatim" based on its resolution status. Using the global tag example:

```yaml
%TAG ! !non-specific-looks-naked
%TAG !! !no-yaml-uri-in-
%TAG !meme! meme://look.at.me
---
[
  # Resolved as: !non-specific-looks-naked
  # Suffixes for non-specific tags are empty.
  #
  # Verbatim: !<!non-specific-looks-naked>
  ! "I am so non-specific",

  # Resolved as: !no-yaml-uri-in-int
  #
  # Verbatim: !<!no-yaml-uri-in-int>
  !!int 24,

  # Resolved as: !meme://look.at.me:iAmTheCaptainNow
  #
  # Verbatim: !<!meme://look.at.me:iAmTheCaptainNow>
  !meme!iAmTheCaptainNow "Oh captain, my captain"
]

--- # This next document has no global tags.
    # Global tags are never carried over
[
  # Inferred as: !!str. This is its kind. Verbatim uses the actual tag
  #
  # Verbatim: !<!my-custom-tag>
  !my-custom-tag "I am so custom",

  # Resolved as: !!int. Uses the global yaml prefix for handle "!!"
  #
  # Verbatim: !<!tag:yaml.org,2002:int>
  !!int 24,
]
```

> [!NOTE]
> If a non-specific tag is declared for a node with no accompanying `GlobalTag` or custom `Resolver` (more on this later), it is resolved to its kind and the tag embedded within the node. In verbatim:
>
>- A flow/block map default to `!<!tag:yaml.org,2002:map>`.
>- A flow/block sequence defaults to `!<!tag:yaml.org,2002:seq>`.
>- A scalar's resolved secondary tag depends on the type inferred and embedded within the scalar itself. Never defaults to `!<!tag:yaml.org,2002:str>`.

A verbatim tag is a node's tag declared in verbatim rather than as a `tag shorthand`. Such tags are handed off "as is" with no resolution to any `global tag`.

```yaml

- !<!my-custom-tag> "I am so custom",

- !<!tag:yaml.org,2002:int> 24,
```

> [!IMPORTANT]
> Tags only accept characters considered valid `uri` characters. Therefore:
>
> 1. Any uri character that must be escaped as required by the [URI RFC](https://datatracker.ietf.org/doc/html/rfc3986) must also be escaped.
> 2. All collection flow indicators (`"{", "}", "[", "]" and ","`) must be escaped as hex using `%` indicator.
> 3. The tag indicator `!` must be escaped if used within the tag suffix.
