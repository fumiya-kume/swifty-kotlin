import Foundation

// MARK: - AtomicIntArray

/// Backing storage for kotlin.concurrent.atomics.AtomicIntArray.
final class AtomicIntArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        storage = Array(repeating: 0, count: max(0, size))
    }

    init(elements: [Int]) {
        storage = elements
    }

    private func withLockedStorage<R>(_ body: (inout [Int]) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }

    func size() -> Int {
        withLockedStorage { $0.count }
    }

    func snapshotElements() -> [Int] {
        withLockedStorage { Array($0) }
    }

    func loadAt(_ index: Int) -> Int? {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return nil
            }
            return storage[index]
        }
    }

    func storeAt(_ index: Int, _ newValue: Int) -> Bool {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return false
            }
            storage[index] = newValue
            return true
        }
    }

    func exchangeAt(_ index: Int, _ newValue: Int) -> Int? {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return nil
            }
            let oldValue = storage[index]
            storage[index] = newValue
            return oldValue
        }
    }

    func compareAndSetAt(_ index: Int, expectedValue: Int, newValue: Int) -> Bool {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return false
            }
            guard storage[index] == expectedValue else {
                return false
            }
            storage[index] = newValue
            return true
        }
    }

    func compareAndExchangeAt(_ index: Int, expectedValue: Int, newValue: Int) -> Int? {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return nil
            }
            let oldValue = storage[index]
            if oldValue == expectedValue {
                storage[index] = newValue
            }
            return oldValue
        }
    }

    func fetchAndAddAt(_ index: Int, _ delta: Int) -> Int? {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return nil
            }
            let oldValue = storage[index]
            storage[index] = oldValue &+ delta
            return oldValue
        }
    }

    func addAndFetchAt(_ index: Int, _ delta: Int) -> Int? {
        withLockedStorage { storage in
            guard storage.indices.contains(index) else {
                return nil
            }
            storage[index] = storage[index] &+ delta
            return storage[index]
        }
    }

    func fetchAndUpdateAt(
        _ index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> Int? {
        while true {
            guard let oldValue = loadAt(index) else {
                return nil
            }
            let newValue = maybeUnbox(transform(oldValue))
            if let thrown = outThrown, thrown.pointee != 0 {
                return oldValue
            }
            if compareAndSetAt(index, expectedValue: oldValue, newValue: newValue) {
                return oldValue
            }
        }
    }

    func updateAndFetchAt(
        _ index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> Int? {
        while true {
            guard let oldValue = loadAt(index) else {
                return nil
            }
            let newValue = maybeUnbox(transform(oldValue))
            if let thrown = outThrown, thrown.pointee != 0 {
                return oldValue
            }
            if compareAndSetAt(index, expectedValue: oldValue, newValue: newValue) {
                return newValue
            }
        }
    }

    func updateAt(
        _ index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> Bool {
        while true {
            guard let oldValue = loadAt(index) else {
                return false
            }
            let newValue = maybeUnbox(transform(oldValue))
            if let thrown = outThrown, thrown.pointee != 0 {
                return false
            }
            if compareAndSetAt(index, expectedValue: oldValue, newValue: newValue) {
                return true
            }
        }
    }
}

private func atomicIntArrayBox(from rawValue: Int) -> AtomicIntArrayBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: AtomicIntArrayBox.self)
}

private func atomicIntArrayMakeStringRaw(_ value: String) -> Int {
    let utf8 = Array(value.utf8)
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}

@_cdecl("kk_atomic_int_array_new")
public func kk_atomic_int_array_new(_ size: Int) -> Int {
    registerRuntimeObject(AtomicIntArrayBox(size: size))
}

@_cdecl("kk_atomic_int_array_fromArray")
public func kk_atomic_int_array_fromArray(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_atomic_int_array_fromArray expected RuntimeArrayBox")
    }
    return registerRuntimeObject(AtomicIntArrayBox(elements: Array(array.elements)))
}

@_cdecl("kk_atomic_int_array_create")
public func kk_atomic_int_array_create(
    _ size: Int,
    _ initFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let count = max(0, size)
    var elements = Array(repeating: 0, count: count)
    for index in 0 ..< count {
        var thrown = 0
        let value = kk_function_invoke(initFn, index, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return registerRuntimeObject(AtomicIntArrayBox(size: 0))
        }
        elements[index] = maybeUnbox(value)
    }
    return registerRuntimeObject(AtomicIntArrayBox(elements: elements))
}

@_cdecl("kk_atomic_int_array_size")
public func kk_atomic_int_array_size(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else {
        return 0
    }
    return box.size()
}

@_cdecl("kk_atomic_int_array_loadAt")
public func kk_atomic_int_array_loadAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard let value = box.loadAt(index) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return value
}

@_cdecl("kk_atomic_int_array_storeAt")
public func kk_atomic_int_array_storeAt(
    _ receiver: Int,
    _ index: Int,
    _ newValue: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard box.storeAt(index, newValue) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return 0
}

@_cdecl("kk_atomic_int_array_exchangeAt")
public func kk_atomic_int_array_exchangeAt(
    _ receiver: Int,
    _ index: Int,
    _ newValue: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard let oldValue = box.exchangeAt(index, newValue) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return oldValue
}

@_cdecl("kk_atomic_int_array_compareAndSetAt")
public func kk_atomic_int_array_compareAndSetAt(
    _ receiver: Int,
    _ index: Int,
    _ expectedValue: Int,
    _ newValue: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard box.loadAt(index) != nil else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return box.compareAndSetAt(index, expectedValue: expectedValue, newValue: newValue) ? 1 : 0
}

@_cdecl("kk_atomic_int_array_compareAndExchangeAt")
public func kk_atomic_int_array_compareAndExchangeAt(
    _ receiver: Int,
    _ index: Int,
    _ expectedValue: Int,
    _ newValue: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard let oldValue = box.compareAndExchangeAt(index, expectedValue: expectedValue, newValue: newValue) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return oldValue
}

@_cdecl("kk_atomic_int_array_fetchAndAddAt")
public func kk_atomic_int_array_fetchAndAddAt(
    _ receiver: Int,
    _ index: Int,
    _ delta: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard let oldValue = box.fetchAndAddAt(index, delta) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return oldValue
}

@_cdecl("kk_atomic_int_array_addAndFetchAt")
public func kk_atomic_int_array_addAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ delta: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    guard let newValue = box.addAndFetchAt(index, delta) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return newValue
}

@_cdecl("kk_atomic_int_array_fetchAndIncrementAt")
public func kk_atomic_int_array_fetchAndIncrementAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_atomic_int_array_fetchAndAddAt(receiver, index, 1, outThrown)
}

@_cdecl("kk_atomic_int_array_incrementAndFetchAt")
public func kk_atomic_int_array_incrementAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_atomic_int_array_addAndFetchAt(receiver, index, 1, outThrown)
}

@_cdecl("kk_atomic_int_array_fetchAndDecrementAt")
public func kk_atomic_int_array_fetchAndDecrementAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_atomic_int_array_fetchAndAddAt(receiver, index, -1, outThrown)
}

@_cdecl("kk_atomic_int_array_decrementAndFetchAt")
public func kk_atomic_int_array_decrementAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_atomic_int_array_addAndFetchAt(receiver, index, -1, outThrown)
}

@_cdecl("kk_atomic_int_array_fetchAndUpdateAt")
public func kk_atomic_int_array_fetchAndUpdateAt(
    _ receiver: Int,
    _ index: Int,
    _ transformFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    let result = box.fetchAndUpdateAt(index, transform: { old in
        kk_function_invoke(transformFn, old, outThrown)
    }, outThrown: outThrown)
    guard let value = result else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return value
}

@_cdecl("kk_atomic_int_array_updateAndFetchAt")
public func kk_atomic_int_array_updateAndFetchAt(
    _ receiver: Int,
    _ index: Int,
    _ transformFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    let result = box.updateAndFetchAt(index, transform: { old in
        kk_function_invoke(transformFn, old, outThrown)
    }, outThrown: outThrown)
    guard let value = result else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return value
}

@_cdecl("kk_atomic_int_array_updateAt")
public func kk_atomic_int_array_updateAt(
    _ receiver: Int,
    _ index: Int,
    _ transformFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = atomicIntArrayBox(from: receiver) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "AtomicIntArray reference is null.")
        return 0
    }
    let success = box.updateAt(index, transform: { old in
        kk_function_invoke(transformFn, old, outThrown)
    }, outThrown: outThrown)
    guard success || box.loadAt(index) != nil else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "AtomicIntArray index \(index) out of bounds for length \(box.size())."
        )
        return 0
    }
    return 0
}

@_cdecl("kk_atomic_int_array_toString")
public func kk_atomic_int_array_toString(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else {
        return atomicIntArrayMakeStringRaw("[]")
    }
    let parts = box.snapshotElements().map(String.init)
    return atomicIntArrayMakeStringRaw("[" + parts.joined(separator: ", ") + "]")
}
