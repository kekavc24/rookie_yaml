## Process Model

You can build a decomposed [pseudo-representation tree](https://yaml.org/spec/1.2.2/#chapter-3-processes-and-models) by using the `TreeBuilder` utility class exported by this package. It emits a `TreeNode` which is just a YAML node ready to be dumped.

### ContentNode

A YAML scalar is always a string and must be scanned to guarantee compatibility with the style assigned to it. It is:

- Split.
- Unfolded (optional based on style).
- Processed to match the style's output in YAML.

This node contains an `Iterable<String>` as its internal node whose lines can be dumped directly to YAML if the indent information is available. Any additional post-processing can be done but caution must be exercised.

### CollectionNode

An abtraction for both a `MapNode` and `ListNode`. Both contain a sequence of entries with a `MapNode` enforcing uniqueness via the key. Additionally, a `MapNode` contains  unnamed Dart `tuple`s (records) rather than `MapEntry`.

## Example

Custom objects must be wrapped with a `DumpableView` matching the YAML data structure you want. The builder instantianted can be reused multiple times.

```dart
final builder = TreeBuilder(TreeConfig.block())..buildFor(['hello', 'there']);
print(builder.builtNode().nodeType); // list
```
