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

    func getAndUpdate(transform: (Int) -> Int) -> (old: Int, new: Int) {
        lock.lock()
        let old = storage
        let new = transform(old)
        storage = new
        lock.unlock()
        return (old, new)
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
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
    return result.old
}

@_cdecl("kk_atomic_int_updateAndGet")
public func kk_atomic_int_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
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

    func getAndUpdate(transform: (Int) -> Int) -> (old: Int, new: Int) {
        lock.lock()
        let old = storage
        let new = transform(old)
        storage = new
        lock.unlock()
        return (old, new)
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
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
    return result.old
}

@_cdecl("kk_atomic_long_updateAndGet")
public func kk_atomic_long_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
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

    func getAndUpdate(transform: (Bool) -> Bool) -> (old: Bool, new: Bool) {
        lock.lock()
        let old = storage != 0
        let new = transform(old)
        storage = new ? 1 : 0
        lock.unlock()
        return (old, new)
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

@_cdecl("kk_atomic_bool_getAndUpdate")
public func kk_atomic_bool_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }
    return result.old ? 1 : 0
}

@_cdecl("kk_atomic_bool_updateAndGet")
public func kk_atomic_bool_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }
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

    func getAndUpdate(transform: (Int) -> Int) -> (old: Int, new: Int) {
        lock.lock()
        let old = storage
        let new = transform(old)
        storage = new
        lock.unlock()
        return (old, new)
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

@_cdecl("kk_atomic_ref_getAndUpdate")
public func kk_atomic_ref_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
    return result.old
}

@_cdecl("kk_atomic_ref_updateAndGet")
public func kk_atomic_ref_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate { old in
        kk_function_invoke(updateFn, old, outThrown)
    }
    return result.new
}
