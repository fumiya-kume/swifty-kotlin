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
