import Foundation

// MARK: - Random (STDLIB-165)

@_cdecl("kk_random_nextInt")
public func kk_random_nextInt(_: Int) -> Int {
    Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextInt_until")
public func kk_random_nextInt_until(_: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
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

@_cdecl("kk_random_nextDouble")
public func kk_random_nextDouble(_: Int) -> Int {
    let d = Double.random(in: 0 ..< 1)
    return kk_box_double(kk_double_to_bits(d))
}

@_cdecl("kk_random_nextBoolean")
public func kk_random_nextBoolean(_: Int) -> Int {
    kk_box_bool(Bool.random() ? 1 : 0)
}
