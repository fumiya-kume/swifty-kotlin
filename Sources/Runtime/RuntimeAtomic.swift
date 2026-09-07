import Foundation

// MARK: - AtomicInt

/// Backing storage for kotlin.concurrent.AtomicInt.
final class AtomicIntBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if storage == expect {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = old &+ delta
        return old
    }

    func addAndFetch(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage = storage &+ delta
        return storage
    }
}

private func atomicIntBox(from raw: Int) -> AtomicIntBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicIntBox.self)
}

@_cdecl("kk_atomic_int_create")
public func kk_atomic_int_create(_ initial: Int) -> Int {
    let box = AtomicIntBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_int_load")
public func __kk_atomic_int_load(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_int_store")
public func __kk_atomic_int_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_int_exchange")
public func __kk_atomic_int_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_int_compareAndSet")
public func kk_atomic_int_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("__kk_atomic_int_compareAndExchange")
public func __kk_atomic_int_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("__kk_atomic_int_fetchAndAdd")
public func __kk_atomic_int_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("__kk_atomic_int_addAndFetch")
public func __kk_atomic_int_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("__kk_atomic_int_fetchAndIncrement")
public func __kk_atomic_int_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("__kk_atomic_int_fetchAndDecrement")
public func __kk_atomic_int_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("__kk_atomic_int_incrementAndFetch")
public func __kk_atomic_int_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("__kk_atomic_int_decrementAndFetch")
public func __kk_atomic_int_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

// MARK: - AtomicLong

/// Backing storage for kotlin.concurrent.AtomicLong.
final class AtomicLongBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if storage == expect {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = old &+ delta
        return old
    }

    func addAndFetch(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage = storage &+ delta
        return storage
    }
}

private func atomicLongBox(from raw: Int) -> AtomicLongBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicLongBox.self)
}

@_cdecl("kk_atomic_long_create")
public func kk_atomic_long_create(_ initial: Int) -> Int {
    let box = AtomicLongBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_long_load")
public func __kk_atomic_long_load(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_long_store")
public func __kk_atomic_long_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_long_exchange")
public func __kk_atomic_long_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_long_compareAndSet")
public func kk_atomic_long_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("__kk_atomic_long_compareAndExchange")
public func __kk_atomic_long_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("__kk_atomic_long_fetchAndAdd")
public func __kk_atomic_long_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("__kk_atomic_long_addAndFetch")
public func __kk_atomic_long_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("__kk_atomic_long_fetchAndIncrement")
public func __kk_atomic_long_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("__kk_atomic_long_fetchAndDecrement")
public func __kk_atomic_long_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("__kk_atomic_long_incrementAndFetch")
public func __kk_atomic_long_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("__kk_atomic_long_decrementAndFetch")
public func __kk_atomic_long_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

// MARK: - AtomicBoolean

/// Backing storage for kotlin.concurrent.AtomicBoolean.
/// Boolean values are stored as Int: 1 = true, 0 = false.
final class AtomicBooleanBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Bool) {
        self.storage = initial ? 1 : 0
    }

    func load() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage != 0
    }

    func store(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        storage = value ? 1 : 0
    }

    func exchange(_ new: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = storage != 0
        storage = new ? 1 : 0
        return old
    }

    func compareAndExchange(expect: Bool, update: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = storage != 0
        if storage == (expect ? 1 : 0) {
            storage = update ? 1 : 0
        }
        return old
    }
}

private func atomicBoolBox(from raw: Int) -> AtomicBooleanBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicBooleanBox.self)
}

@_cdecl("kk_atomic_bool_create")
public func kk_atomic_bool_create(_ initial: Int) -> Int {
    let box = AtomicBooleanBox(initial: initial != 0)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_bool_load")
public func __kk_atomic_bool_load(_ receiver: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.load() ? 1 : 0
}

@_cdecl("__kk_atomic_bool_store")
public func __kk_atomic_bool_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    box.store(value != 0)
    return 0
}

@_cdecl("__kk_atomic_bool_exchange")
public func __kk_atomic_bool_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.exchange(new != 0) ? 1 : 0
}

@_cdecl("__kk_atomic_bool_compareAndExchange")
public func __kk_atomic_bool_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect != 0, update: update != 0) ? 1 : 0
}

// MARK: - AtomicReference<T>

/// Backing storage for kotlin.concurrent.AtomicReference<T>.
/// Values are stored as opaque intptr_t (object pointers or boxed values).
final class AtomicRefBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    /// Kotlin `AtomicReference` CAS uses reference identity, so raw handles
    /// are compared rather than their structural values.
    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }
}

private func atomicRefBox(from raw: Int) -> AtomicRefBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicRefBox.self)
}

@_cdecl("kk_atomic_ref_create")
public func kk_atomic_ref_create(_ initial: Int) -> Int {
    let box = AtomicRefBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_ref_load")
public func __kk_atomic_ref_load(_ receiver: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_ref_store")
public func __kk_atomic_ref_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_ref_exchange")
public func __kk_atomic_ref_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("__kk_atomic_ref_compareAndExchange")
public func __kk_atomic_ref_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

// MARK: - AtomicIntArray

/// Backing storage for kotlin.concurrent.atomics.AtomicIntArray.
/// All accesses are serialized through the same lock to provide
/// consistent atomicity and acquire/release visibility between operations.
final class AtomicIntArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        self.storage = Array(repeating: 0, count: max(0, size))
    }

    func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func load(at index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        return storage[index]
    }

    func store(at index: Int, value: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return }
        storage[index] = value
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        storage[index] = newValue
        return old
    }

    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return false }
        if storage[index] == expect {
            storage[index] = update
            return true
        }
        return false
    }

    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        if old == expect {
            storage[index] = update
        }
        return old
    }

    func fetchAndAdd(at index: Int, delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        storage[index] = old &+ delta
        return old
    }

    func addAndFetch(at index: Int, delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        storage[index] = storage[index] &+ delta
        return storage[index]
    }
}

private func atomicIntArrayBox(from raw: Int) -> AtomicIntArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicIntArrayBox.self)
}

// (a) RF-DEAD-002: 配線予定 → MIGRATION-ATOMIC-001 (AtomicIntArray / AtomicLongArray サポート)
@_cdecl("kk_atomic_int_array_create")
public func kk_atomic_int_array_create(_ size: Int) -> Int {
    let box = AtomicIntArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_int_array_size")
public func kk_atomic_int_array_size(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.size()
}

// KSP-672: The public `*At` boundary layer and bounds checks now live in Kotlin
// (Stdlib/kotlin/concurrent/AtomicArrayMigration.kt). These `__kk_*` bridges are
// the raw synchronized core: they assume the index has already been validated by
// the Kotlin caller and never allocate exceptions.
@_cdecl("__kk_atomic_int_array_load")
public func __kk_atomic_int_array_load(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@_cdecl("__kk_atomic_int_array_store")
public func __kk_atomic_int_array_store(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("__kk_atomic_int_array_exchange")
public func __kk_atomic_int_array_exchange(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("__kk_atomic_int_array_compareAndExchange")
public func __kk_atomic_int_array_compareAndExchange(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int
) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("__kk_atomic_int_array_fetchAndAdd")
public func __kk_atomic_int_array_fetchAndAdd(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("__kk_atomic_int_array_addAndFetch")
public func __kk_atomic_int_array_addAndFetch(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(at: index, delta: delta)
}

// MARK: - AtomicLongArray

/// Backing storage for kotlin.concurrent.atomics.AtomicLongArray.
final class AtomicLongArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        self.storage = Array(repeating: 0, count: max(0, size))
    }

    func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func load(at index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        return storage[index]
    }

    func store(at index: Int, value: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return }
        storage[index] = value
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        storage[index] = newValue
        return old
    }

    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return false }
        if storage[index] == expect {
            storage[index] = update
            return true
        }
        return false
    }

    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        if old == expect {
            storage[index] = update
        }
        return old
    }

    func fetchAndAdd(at index: Int, delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        storage[index] = old &+ delta
        return old
    }

    func addAndFetch(at index: Int, delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        storage[index] = storage[index] &+ delta
        return storage[index]
    }
}

private func atomicLongArrayBox(from raw: Int) -> AtomicLongArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicLongArrayBox.self)
}

@_cdecl("kk_atomic_long_array_create")
public func kk_atomic_long_array_create(_ size: Int) -> Int {
    let box = AtomicLongArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_array_size")
public func kk_atomic_long_array_size(_ receiver: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.size()
}

// KSP-672: Raw synchronized core for AtomicLongArray. Bounds checks and the
// public `*At` layer live in Kotlin (AtomicArrayMigration.kt); these bridges
// assume a pre-validated index and never allocate exceptions.
@_cdecl("__kk_atomic_long_array_load")
public func __kk_atomic_long_array_load(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@_cdecl("__kk_atomic_long_array_store")
public func __kk_atomic_long_array_store(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("__kk_atomic_long_array_exchange")
public func __kk_atomic_long_array_exchange(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("__kk_atomic_long_array_compareAndExchange")
public func __kk_atomic_long_array_compareAndExchange(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int
) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("__kk_atomic_long_array_fetchAndAdd")
public func __kk_atomic_long_array_fetchAndAdd(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("__kk_atomic_long_array_addAndFetch")
public func __kk_atomic_long_array_addAndFetch(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(at: index, delta: delta)
}

// MARK: - AtomicArray<T> (generic reference-typed array)

/// Backing storage for kotlin.concurrent.atomics.AtomicArray<T>.
/// Elements are stored as opaque intptr_t (object pointers or boxed values).
/// CAS uses identity semantics: two values compare equal iff their raw Int
/// representation is identical (i.e. pointer identity, not structural equality).
final class AtomicRefArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        self.storage = Array(repeating: 0, count: max(0, size))
    }

    func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func load(at index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        return storage[index]
    }

    func store(at index: Int, value: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return }
        storage[index] = value
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        storage[index] = newValue
        return old
    }

    /// Identity-based CAS, with string boxes compared structurally because aggregate
    /// string lowering may materialize an equivalent RuntimeStringBox at ABI edges.
    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return false }
        if runtimeAtomicRefValuesMatch(storage[index], expect) {
            storage[index] = update
            return true
        }
        return false
    }

    /// Identity-based compareAndExchange: returns the previous value regardless of success.
    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard storage.indices.contains(index) else { return 0 }
        let old = storage[index]
        if runtimeAtomicRefValuesMatch(old, expect) {
            storage[index] = update
        }
        return old
    }
}

private func atomicRefArrayBox(from raw: Int) -> AtomicRefArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicRefArrayBox.self)
}

private func registerAtomicRefArrayBox(_ box: AtomicRefArrayBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeAtomicRefValuesMatch(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    guard
        let lhsPointer = UnsafeMutableRawPointer(bitPattern: lhs),
        let rhsPointer = UnsafeMutableRawPointer(bitPattern: rhs),
        let lhsString = tryCast(lhsPointer, to: RuntimeStringBox.self),
        let rhsString = tryCast(rhsPointer, to: RuntimeStringBox.self)
    else {
        return false
    }
    return lhsString.value == rhsString.value
}

@_cdecl("kk_atomic_ref_array_new")
public func kk_atomic_ref_array_new(_ size: Int) -> Int {
    let box = AtomicRefArrayBox(size: size)
    return registerAtomicRefArrayBox(box)
}

@_cdecl("kk_atomic_ref_array_of")
public func kk_atomic_ref_array_of(_ arrayRaw: Int) -> Int {
    let elements = runtimeArrayBox(from: arrayRaw)?.elements ?? []
    let box = AtomicRefArrayBox(size: elements.count)
    for (index, element) in elements.enumerated() {
        box.store(at: index, value: element)
    }
    return registerAtomicRefArrayBox(box)
}

@_cdecl("kk_atomic_ref_array_size")
public func kk_atomic_ref_array_size(_ receiver: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_ref_array_loadAt")
public func kk_atomic_ref_array_loadAt(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@discardableResult
@_cdecl("kk_atomic_ref_array_storeAt")
public func kk_atomic_ref_array_storeAt(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("kk_atomic_ref_array_exchangeAt")
public func kk_atomic_ref_array_exchangeAt(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("kk_atomic_ref_array_compareAndSetAt")
public func kk_atomic_ref_array_compareAndSetAt(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.compareAndSet(at: index, expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_ref_array_compareAndExchangeAt")
public func kk_atomic_ref_array_compareAndExchangeAt(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}
