The secondary tag handle `!!` is limited to tags below which all resolve to the YAML global tag prefix, `tag:yaml.org,2002`.

- `YAML` schema tags
  - `!!map` - `Map`
  - `!!seq` - `List`
  - `!!str` - `String`

- `JSON` schema tags
  - `!!null` - `null`
  - `!!bool` - Boolean.
  - `!!int` - Integer. `hex`, `octal` and `base 10` should use this.
  - `!!float` - double.

- `Dart`-specific schema tags (More will be supported)
  - `!!uri` - URI
