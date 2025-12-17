import Foundation

/// Thread-safe property wrapper for concurrent access
@propertyWrapper
final class Atomic<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(wrappedValue: Value) {
        self._value = wrappedValue
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    /// Perform atomic operation
    func mutate(_ transform: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&_value)
    }
}
