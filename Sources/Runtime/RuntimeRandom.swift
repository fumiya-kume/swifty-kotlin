import Foundation

// MARK: - Random (STDLIB-165)

@_cdecl("kk_random_nextInt")
public func kk_random_nextInt(_ receiver: Int) -> Int {
    Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextInt_until")
public func kk_random_nextInt_until(_ receiver: Int, _ until: Int) -> Int {
    guard until > 0 else {
        return 0
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextInt_range")
public func kk_random_nextInt_range(_ receiver: Int, _ from: Int, _ until: Int) -> Int {
    guard until > from else {
        return from
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextDouble")
public func kk_random_nextDouble(_ receiver: Int) -> Int {
    let d = Double.random(in: 0 ..< 1)
    return kk_box_double(kk_double_to_bits(d))
}

@_cdecl("kk_random_nextBoolean")
public func kk_random_nextBoolean(_ receiver: Int) -> Int {
    kk_box_bool(Bool.random() ? 1 : 0)
}
