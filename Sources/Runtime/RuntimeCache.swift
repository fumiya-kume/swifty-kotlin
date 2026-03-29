import Foundation

final class RuntimeCacheBox {
    let capacity: Int
    private var order: [Int] = []
    private var storage: [Int: Int] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func put(key: Int, value: Int) {
        storage[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > capacity, let evicted = order.first {
            order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    func get(key: Int) -> Int {
        guard let value = storage[key] else { return runtimeNullSentinelInt }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func size() -> Int {
        storage.count
    }
}

private func runtimeCacheBox(from raw: Int) -> RuntimeCacheBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeCacheBox.self)
}

@_cdecl("kk_cache_new")
public func kk_cache_new(_ capacityRaw: Int) -> Int {
    registerRuntimeObject(RuntimeCacheBox(capacity: capacityRaw))
}

@_cdecl("kk_cache_put")
public func kk_cache_put(_ cacheRaw: Int, _ keyRaw: Int, _ valueRaw: Int) -> Int {
    guard let cache = runtimeCacheBox(from: cacheRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cache_put received invalid cache handle")
    }
    cache.put(key: keyRaw, value: valueRaw)
    return 0
}

@_cdecl("kk_cache_get")
public func kk_cache_get(_ cacheRaw: Int, _ keyRaw: Int) -> Int {
    guard let cache = runtimeCacheBox(from: cacheRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cache_get received invalid cache handle")
    }
    return cache.get(key: keyRaw)
}

@_cdecl("kk_cache_size")
public func kk_cache_size(_ cacheRaw: Int) -> Int {
    guard let cache = runtimeCacheBox(from: cacheRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cache_size received invalid cache handle")
    }
    return cache.size()
}
