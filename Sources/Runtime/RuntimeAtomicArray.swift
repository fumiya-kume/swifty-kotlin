import Foundation

/// Backing storage for kotlin.concurrent.atomics.AtomicArray.
/// Stores raw intptr_t values and synchronizes access with a private lock.
final class AtomicArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(elements: [Int]) {
        self.storage = elements
    }

    init(length: Int, initialValue: Int = runtimeNullSentinelInt) {
        self.storage = Array(repeating: initialValue, count: max(0, length))
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    var elements: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func load(at index: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < storage.count else {
            return nil
        }
        return storage[index]
    }

    func store(at index: Int, value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < storage.count else {
            return false
        }
        storage[index] = value
        return true
    }

    func exchange(at index: Int, new: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < storage.count else {
            return nil
        }
        let old = storage[index]
        storage[index] = new
        return old
    }

    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < storage.count else {
            return nil
        }
        if storage[index] == expect {
            storage[index] = update
            return true
        }
        return false
    }

    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < storage.count else {
            return nil
        }
        let old = storage[index]
        if old == expect {
            storage[index] = update
        }
        return old
    }

    func fetchAndUpdate(
        at index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> Int? {
        while true {
            guard let old = load(at: index) else {
                return nil
            }
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return nil
            }
            if compareAndSet(at: index, expect: old, update: new) == true {
                return old
            }
        }
    }

    func updateAndFetch(
        at index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> Int? {
        while true {
            guard let old = load(at: index) else {
                return nil
            }
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return nil
            }
            if compareAndSet(at: index, expect: old, update: new) == true {
                return new
            }
        }
    }
}

private func runtimeAtomicArrayNullThrowable() -> Int {
    runtimeAllocateThrowable(message: "AtomicArray reference is null.")
}

private func runtimeAtomicArrayBoundsThrowable(index: Int, length: Int) -> Int {
    runtimeAllocateThrowable(message: "AtomicArray index \(index) out of bounds for length \(length).")
}

private func runtimeAtomicArraySizeThrowable(size: Int) -> Int {
    runtimeAllocateThrowable(message: "IllegalArgumentException: size must be non-negative, but was \(size).")
}

private func runtimeAtomicArrayStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
    }
}

@_cdecl("kk_atomic_array_create")
public func kk_atomic_array_create(_ sourceArrayRaw: Int) -> Int {
    guard let sourceArray = runtimeArrayBox(from: sourceArrayRaw) else {
        return registerRuntimeObject(AtomicArrayBox(elements: []))
    }
    return registerRuntimeObject(AtomicArrayBox(elements: sourceArray.elements))
}

@_cdecl("kk_atomic_array_new")
public func kk_atomic_array_new(_ size: Int, _ initFn: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard size >= 0 else {
        outThrown?.pointee = runtimeAtomicArraySizeThrowable(size: size)
        return 0
    }

    let box = AtomicArrayBox(length: size)
    for index in 0..<size {
        let value = kk_function_invoke(initFn, index, outThrown)
        if let thrown = outThrown, thrown.pointee != 0 {
            return 0
        }
        _ = box.store(at: index, value: value)
    }
    return registerRuntimeObject(box)
}

@_cdecl("kk_atomic_array_ofNulls")
public func kk_atomic_array_ofNulls(_ size: Int) -> Int {
    let box = AtomicArrayBox(length: size)
    return registerRuntimeObject(box)
}

@_cdecl("kk_atomic_array_size")
public func kk_atomic_array_size(_ receiver: Int) -> Int {
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        return 0
    }
    return box.count
}

@_cdecl("kk_atomic_array_loadAt")
public func kk_atomic_array_loadAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let value = box.load(at: index) else {
        outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        return 0
    }
    return value
}

@_cdecl("kk_atomic_array_storeAt")
public func kk_atomic_array_storeAt(
    _ receiver: Int,
    _ index: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard box.store(at: index, value: value) else {
        outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        return 0
    }
    return 0
}

@_cdecl("kk_atomic_array_exchangeAt")
public func kk_atomic_array_exchangeAt(
    _ receiver: Int,
    _ index: Int,
    _ new: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let old = box.exchange(at: index, new: new) else {
        outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        return 0
    }
    return old
}

@_cdecl("kk_atomic_array_compareAndSetAt")
public func kk_atomic_array_compareAndSetAt(
    _ receiver: Int,
    _ index: Int,
    _ expect: Int,
    _ update: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let result = box.compareAndSet(at: index, expect: expect, update: update) else {
        outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        return 0
    }
    return result ? 1 : 0
}

@_cdecl("kk_atomic_array_compareAndExchangeAt")
public func kk_atomic_array_compareAndExchangeAt(
    _ receiver: Int,
    _ index: Int,
    _ expect: Int,
    _ update: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let old = box.compareAndExchange(at: index, expect: expect, update: update) else {
        outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        return 0
    }
    return old
}

@_cdecl("kk_atomic_array_fetchAndUpdateAt")
public func kk_atomic_array_fetchAndUpdateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let old = box.fetchAndUpdate(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown) else {
        if outThrown?.pointee == 0 {
            outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        }
        return 0
    }
    return old
}

@_cdecl("kk_atomic_array_updateAndFetchAt")
public func kk_atomic_array_updateAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard let new = box.updateAndFetch(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown) else {
        if outThrown?.pointee == 0 {
            outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        }
        return 0
    }
    return new
}

@_cdecl("kk_atomic_array_updateAt")
public func kk_atomic_array_updateAt(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAtomicArrayNullThrowable()
        return 0
    }
    guard box.updateAndFetch(at: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown) != nil else {
        if outThrown?.pointee == 0 {
            outThrown?.pointee = runtimeAtomicArrayBoundsThrowable(index: index, length: box.count)
        }
        return 0
    }
    return 0
}

@_cdecl("kk_atomic_array_toString")
public func kk_atomic_array_toString(_ receiver: Int) -> UnsafeMutableRawPointer {
    guard let box = runtimeAtomicArrayBox(from: receiver) else {
        return runtimeAtomicArrayStringPointer("[]")
    }
    let rendered = box.elements.map(runtimeElementToString).joined(separator: ", ")
    return runtimeAtomicArrayStringPointer("[\(rendered)]")
}
