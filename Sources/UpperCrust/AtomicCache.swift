/// A class that lazily, atomically creates reference type objects.
class AtomicCache<Value: AnyObject> {
  /// The underlying mutable cached variable that will only be set once.
  private var value: AnyObject?

  /// Accesses the value in the cache or creates it atomically using the
  /// provided closure.
  func value(_ create: () -> Value) -> Value {
    return withUnsafeMutablePointer(to: &value) { ptr in
      // Try to load the value.
      if let value = _stdlib_atomicLoadARCRef(object: ptr) as? Value {
        // If we got it, then return it.
        _onFastPath()
        return value
      }

      // Otherwise, create the value.
      let value = create()

      // Try to atomically swap the value into the cache pointer.
      if _stdlib_atomicInitializeARCRef(object: ptr, desired: value) {
        // If we won the race, return it.
        return value
      }

      // Otherwise, load _again_ and let the value we created die.
      return _stdlib_atomicLoadARCRef(object: ptr) as! Value
    }
  }
}
