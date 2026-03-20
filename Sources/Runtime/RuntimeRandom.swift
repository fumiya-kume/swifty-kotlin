import Foundation

// MARK: - Random (STDLIB-165, STDLIB-514, STDLIB-515)

@_cdecl("kk_random_nextInt")
public func kk_random_nextInt(_: Int) -> Int {
    Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextInt_until")
public func kk_random_nextInt_until(_ randomRaw: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    // TODO(STDLIB-531): Implement seeded RNG support by extracting the seed
    // from the Kotlin Random instance (randomRaw) and using it to drive
    // a deterministic generator. Currently delegates to Swift's
    // SystemRandomNumberGenerator, which matches Random.Default behavior
    // but breaks the contract for seeded instances like Random(42).
    _ = randomRaw  // ABI parameter; will be used once seeded RNG is implemented
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextInt_range")
public func kk_random_nextInt_range(_: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextLong")
public func kk_random_nextLong(_: Int) -> Int {
    Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextLong_until")
public func kk_random_nextLong_until(_: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextLong_range")
public func kk_random_nextLong_range(_: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextFloat")
public func kk_random_nextFloat(_: Int) -> Int {
    kk_float_to_bits(Float.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextDouble")
public func kk_random_nextDouble(_: Int) -> Int {
    kk_double_to_bits(Double.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextBoolean")
public func kk_random_nextBoolean(_: Int) -> Int {
    kk_box_bool(Bool.random() ? 1 : 0)
}
