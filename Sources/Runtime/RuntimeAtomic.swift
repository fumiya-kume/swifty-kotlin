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

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicIntBox(from raw: Int) -> AtomicIntBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicIntBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_int_create")
public func kk_atomic_int_create(_ initial: Int) -> Int {
    let box = AtomicIntBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_int_load")
public func kk_atomic_int_load(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_int_store")
public func kk_atomic_int_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_int_exchange")
public func kk_atomic_int_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_int_compareAndSet")
public func kk_atomic_int_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_int_compareAndExchange")
public func kk_atomic_int_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_atomic_int_asJavaAtomic")
public func kk_atomic_int_asJavaAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_int_asKotlinAtomic")
public func kk_java_atomic_int_asKotlinAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_int_fetchAndAdd")
public func kk_atomic_int_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("kk_atomic_int_addAndFetch")
public func kk_atomic_int_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("kk_atomic_int_fetchAndIncrement")
public func kk_atomic_int_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("kk_atomic_int_fetchAndDecrement")
public func kk_atomic_int_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("kk_atomic_int_incrementAndFetch")
public func kk_atomic_int_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("kk_atomic_int_decrementAndFetch")
public func kk_atomic_int_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

@_cdecl("kk_atomic_int_getAndUpdate")
public func kk_atomic_int_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_int_updateAndGet")
public func kk_atomic_int_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
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

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicLongBox(from raw: Int) -> AtomicLongBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicLongBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_long_create")
public func kk_atomic_long_create(_ initial: Int) -> Int {
    let box = AtomicLongBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_load")
public func kk_atomic_long_load(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_long_store")
public func kk_atomic_long_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_long_exchange")
public func kk_atomic_long_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_long_compareAndSet")
public func kk_atomic_long_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_long_compareAndExchange")
public func kk_atomic_long_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_java_atomic_long_asKotlinAtomic")
public func kk_java_atomic_long_asKotlinAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_long_asJavaAtomic")
public func kk_atomic_long_asJavaAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_long_fetchAndAdd")
public func kk_atomic_long_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("kk_atomic_long_addAndFetch")
public func kk_atomic_long_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("kk_atomic_long_fetchAndIncrement")
public func kk_atomic_long_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("kk_atomic_long_fetchAndDecrement")
public func kk_atomic_long_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("kk_atomic_long_incrementAndFetch")
public func kk_atomic_long_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("kk_atomic_long_decrementAndFetch")
public func kk_atomic_long_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

@_cdecl("kk_atomic_long_getAndUpdate")
public func kk_atomic_long_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_long_updateAndGet")
public func kk_atomic_long_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
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

    func compareAndSet(expect: Bool, update: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let expectInt = expect ? 1 : 0
        if storage == expectInt {
            storage = update ? 1 : 0
            return true
        }
        return false
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

    func getAndUpdate(transform: (Bool) -> Bool, outThrown: UnsafeMutablePointer<Int>?) -> (old: Bool, new: Bool) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicBoolBox(from raw: Int) -> AtomicBooleanBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicBooleanBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_bool_create")
public func kk_atomic_bool_create(_ initial: Int) -> Int {
    let box = AtomicBooleanBox(initial: initial != 0)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_bool_load")
public func kk_atomic_bool_load(_ receiver: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.load() ? 1 : 0
}

@_cdecl("kk_atomic_bool_store")
public func kk_atomic_bool_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    box.store(value != 0)
    return 0
}

@_cdecl("kk_atomic_bool_exchange")
public func kk_atomic_bool_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.exchange(new != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_compareAndSet")
public func kk_atomic_bool_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect != 0, update: update != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_compareAndExchange")
public func kk_atomic_bool_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect != 0, update: update != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_asJavaAtomic")
public func kk_atomic_bool_asJavaAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_bool_asKotlinAtomic")
public func kk_java_atomic_bool_asKotlinAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_bool_getAndUpdate")
public func kk_atomic_bool_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }, outThrown: outThrown)
    return result.old ? 1 : 0
}

@_cdecl("kk_atomic_bool_updateAndGet")
public func kk_atomic_bool_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }, outThrown: outThrown)
    return result.new ? 1 : 0
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

    /// Kotlin `AtomicReference` CAS uses value equality (e.g. same string contents),
    /// not pointer identity — match JVM `kotlin.concurrent.atomics` behaviour.
    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if runtimeValuesEqual(storage, expect) {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if runtimeValuesEqual(old, expect) {
            storage = update
        }
        return old
    }

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicRefBox(from raw: Int) -> AtomicRefBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicRefBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_ref_create")
public func kk_atomic_ref_create(_ initial: Int) -> Int {
    let box = AtomicRefBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_ref_load")
public func kk_atomic_ref_load(_ receiver: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_ref_store")
public func kk_atomic_ref_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_ref_exchange")
public func kk_atomic_ref_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_ref_compareAndSet")
public func kk_atomic_ref_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_ref_compareAndExchange")
public func kk_atomic_ref_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_atomic_ref_asJavaAtomic")
public func kk_atomic_ref_asJavaAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_ref_asKotlinAtomic")
public func kk_java_atomic_ref_asKotlinAtomic(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_ref_getAndUpdate")
public func kk_atomic_ref_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_ref_updateAndGet")
public func kk_atomic_ref_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
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

    func fetchAndUpdate(at index: Int, transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load(at: index)
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(at: index, expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicIntArrayBox(from raw: Int) -> AtomicIntArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicIntArrayBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_int_array_create")
public func kk_atomic_int_array_create(_ size: Int) -> Int {
    let box = AtomicIntArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_int_array_size")
public func kk_atomic_int_array_size(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_int_array_loadAt")
public func kk_atomic_int_array_loadAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.load(at: index)
}

@_cdecl("kk_atomic_int_array_storeAt")
public func kk_atomic_int_array_storeAt(
    _ receiver: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("kk_atomic_int_array_exchangeAt")
public func kk_atomic_int_array_exchangeAt(
    _ receiver: Int, _ index: Int, _ newValue: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("kk_atomic_int_array_compareAndSetAt")
public func kk_atomic_int_array_compareAndSetAt(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.compareAndSet(at: index, expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_int_array_compareAndExchangeAt")
public func kk_atomic_int_array_compareAndExchangeAt(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("kk_atomic_int_array_asJavaAtomicArray")
public func kk_atomic_int_array_asJavaAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_int_array_asKotlinAtomicArray")
public func kk_java_atomic_int_array_asKotlinAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_int_array_fetchAndUpdateAt")
public func kk_atomic_int_array_fetchAndUpdateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    let result = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_int_array_fetchAndAddAt")
public func kk_atomic_int_array_fetchAndAddAt(
    _ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("kk_atomic_int_array_addAndFetchAt")
public func kk_atomic_int_array_addAndFetchAt(
    _ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: delta)
}

@_cdecl("kk_atomic_int_array_fetchAndIncrementAt")
public func kk_atomic_int_array_fetchAndIncrementAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: 1)
}

@_cdecl("kk_atomic_int_array_incrementAndFetchAt")
public func kk_atomic_int_array_incrementAndFetchAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: 1)
}

@_cdecl("kk_atomic_int_array_fetchAndDecrementAt")
public func kk_atomic_int_array_fetchAndDecrementAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: -1)
}

@_cdecl("kk_atomic_int_array_decrementAndFetchAt")
public func kk_atomic_int_array_decrementAndFetchAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: -1)
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

    func fetchAndUpdate(at index: Int, transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load(at: index)
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(at: index, expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicLongArrayBox(from raw: Int) -> AtomicLongArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicLongArrayBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_long_array_create")
public func kk_atomic_long_array_create(_ size: Int) -> Int {
    let box = AtomicLongArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_array_size")
public func kk_atomic_long_array_size(_ receiver: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_long_array_loadAt")
public func kk_atomic_long_array_loadAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.load(at: index)
}

@_cdecl("kk_atomic_long_array_storeAt")
public func kk_atomic_long_array_storeAt(
    _ receiver: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("kk_atomic_long_array_exchangeAt")
public func kk_atomic_long_array_exchangeAt(
    _ receiver: Int, _ index: Int, _ newValue: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("kk_atomic_long_array_compareAndSetAt")
public func kk_atomic_long_array_compareAndSetAt(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.compareAndSet(at: index, expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_long_array_compareAndExchangeAt")
public func kk_atomic_long_array_compareAndExchangeAt(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("kk_atomic_long_array_asJavaAtomicArray")
public func kk_atomic_long_array_asJavaAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_long_array_asKotlinAtomicArray")
public func kk_java_atomic_long_array_asKotlinAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_long_array_fetchAndUpdateAt")
public func kk_atomic_long_array_fetchAndUpdateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    let result = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_long_array_fetchAndAddAt")
public func kk_atomic_long_array_fetchAndAddAt(
    _ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("kk_atomic_long_array_addAndFetchAt")
public func kk_atomic_long_array_addAndFetchAt(
    _ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: delta)
}

@_cdecl("kk_atomic_long_array_fetchAndIncrementAt")
public func kk_atomic_long_array_fetchAndIncrementAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: 1)
}

@_cdecl("kk_atomic_long_array_incrementAndFetchAt")
public func kk_atomic_long_array_incrementAndFetchAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: 1)
}

@_cdecl("kk_atomic_long_array_fetchAndDecrementAt")
public func kk_atomic_long_array_fetchAndDecrementAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.fetchAndAdd(at: index, delta: -1)
}

@_cdecl("kk_atomic_long_array_decrementAndFetchAt")
public func kk_atomic_long_array_decrementAndFetchAt(
    _ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let size = box.size()
    guard index >= 0 && index < size else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: index \(index) out of bounds for size \(size)"
        )
        return 0
    }
    return box.addAndFetch(at: index, delta: -1)
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

    /// Identity-based CAS: succeeds iff storage[index] == expect (pointer identity).
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

    /// Identity-based compareAndExchange: returns the previous value regardless of success.
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

    func fetchAndUpdate(at index: Int, transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        guard index >= 0 && index < size() else { return (0, 0) }
        while true {
            let old = load(at: index)
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(at: index, expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicRefArrayBox(from raw: Int) -> AtomicRefArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicRefArrayBox>.fromOpaque(ptr).takeUnretainedValue()
}

private func registerAtomicRefArrayBox(_ box: AtomicRefArrayBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
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

@_cdecl("kk_atomic_ref_array_asJavaAtomicArray")
public func kk_atomic_ref_array_asJavaAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_java_atomic_ref_array_asKotlinAtomicArray")
public func kk_java_atomic_ref_array_asKotlinAtomicArray(_ receiver: Int) -> Int {
    receiver
}

@_cdecl("kk_atomic_ref_array_fetchAndUpdateAt")
public func kk_atomic_ref_array_fetchAndUpdateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    let result = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_ref_array_updateAt")
public func kk_atomic_ref_array_updateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    _ = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return 0
}

@_cdecl("kk_atomic_ref_array_updateAndFetchAt")
public func kk_atomic_ref_array_updateAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    let result = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}
