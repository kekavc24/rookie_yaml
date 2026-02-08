part of 'object_delegate.dart';

/// A mixin that resolves and caches the object [T] for a delegate.
base mixin _ResolvingCache<T> on NodeDelegate<T> {
  /// Validates the parsed [_tag].
  NodeTag _checkResolvedTag(NodeTag tag);

  /// Validates if parsed properties are valid only when [parsed] is called.
  void _resolveProperties() {
    switch (_property) {
      case Alias(:final alias):
        _alias = alias;

      case NodeProperty(:final anchor, :final tag):
        {
          switch (tag) {
            case ContentResolver(:final resolvedTag):
              {
                // Cannot override the captured tag; only validate it. This
                // allows a non-specific tag to be captured and resolved by
                // any scalar.
                _checkResolvedTag(resolvedTag);
                _tag = tag;
              }

            // Node tags with only non-specific tags and no global tag prefix
            // will default to str, mapping or seq based on its schema kind.
            case NodeTag nodeTag:
              _tag = _checkResolvedTag(nodeTag);

            default:
              _tag = tag;
          }

          _anchor = anchor;
        }

      default:
        return;
    }

    _property = null;
  }

  @override
  T parsed() {
    if (!_isResolved) {
      _resolveProperties();
      _resolved = _resolveNode();
      _isResolved = true;
    }

    return _resolved as T;
  }

  /// Resolves the actual object.
  T _resolveNode();
}

mixin _BoxedCallOnce<T> {
  /// Whether a resolving function provided
  var _called = false;

  /// Calls a resolving function once for delegates that sandbox other
  /// delegates.
  @pragma('vm:prefer-inline')
  T _callOnce(T object, {required void Function(T object) ifNotCalled}) {
    if (_called) return object;
    _called = true;
    ifNotCalled(object);
    return object;
  }
}
