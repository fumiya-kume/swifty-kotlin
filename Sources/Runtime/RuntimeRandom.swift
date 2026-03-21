import Foundation

// MARK: - Seeded Random (STDLIB-516)

/// A deterministic PRNG using the xorshift64* algorithm.
/// Each `Random(seed)` call creates a new instance whose state evolves
/// independently so that two instances with the same seed produce identical
/// sequences.
final class SeededRandomBox {
    /// Internal PRNG state (xorshift64*).
    var state: UInt64

    init(seed: Int) {
        // Kotlin's Random(seed) internally mixes the seed.  We use the same
        // initial-state derivation so that behaviour is deterministic and
        // consistent across runs.  A seed of 0 would stall xorshift, so we
        // mix it first.
        var s = UInt64(bitPattern: Int64(seed))
        // Murmur-style finaliser to spread bits.
        s = s &+ 0x9E3779B97F4A7C15
        s = (s ^ (s >> 30)) &* 0xBF58476D1CE4E5B9
        s = (s ^ (s >> 27)) &* 0x94D049BB133111EB
        s = s ^ (s >> 31)
        if s == 0 { s = 1 }          // xorshift must never be 0
        self.state = s
    }

    /// Returns the next pseudo-random UInt64.
    func nextBits() -> UInt64 {
        var s = state
        s ^= s >> 12
        s ^= s << 25
        s ^= s >> 27
        state = s
        return s &* 0x2545F4914F6CDD1D
    }

    /// Returns a random Int in [0, bound).
    func nextInt(bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        return Int(nextBits() % b)
    }

    /// Returns a random Int in [from, until).
    func nextIntRange(from: Int, until: Int) -> Int {
        precondition(until > from)
        let range = UInt64(bitPattern: Int64(until) &- Int64(from))
        return from &+ Int(Int64(bitPattern: nextBits() % range))
    }

    /// Returns a random Int (full range).
    func nextFullInt() -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: nextBits()))
    }

    /// Returns a random Double in [0.0, 1.0).
    func nextDouble() -> Double {
        // Use 53 bits of randomness (IEEE-754 double significand width).
        let bits = nextBits() >> 11
        return Double(bits) / Double(1 << 53)
    }

    /// Returns a random Float in [0.0, 1.0).
    func nextFloat() -> Float {
        let bits = nextBits() >> 40
        return Float(bits) / Float(1 << 24)
    }

    /// Returns a random Bool.
    func nextBoolean() -> Bool {
        (nextBits() & 1) != 0
    }
}

/// Extract a SeededRandomBox from a raw receiver value.
/// Returns `nil` when the receiver is 0 (= Random.Default / companion object).
private func seededBox(from raw: Int) -> SeededRandomBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return Unmanaged<SeededRandomBox>.fromOpaque(ptr).takeUnretainedValue()
}

// MARK: - Constructor

@_cdecl("kk_random_create_seeded")
public func kk_random_create_seeded(_ seed: Int) -> Int {
    let box = SeededRandomBox(seed: seed)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

// MARK: - Random (STDLIB-165, STDLIB-514, STDLIB-515, STDLIB-516, STDLIB-654)

@_cdecl("kk_random_nextInt")
public func kk_random_nextInt(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return box.nextFullInt()
    }
    return Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextInt_until")
public func kk_random_nextInt_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextInt(bound: until)
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextInt_range")
public func kk_random_nextInt_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextIntRange(from: from, until: until)
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextLong")
public func kk_random_nextLong(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return box.nextFullInt()
    }
    return Int.random(in: Int.min ... Int.max)
}

@_cdecl("kk_random_nextLong_until")
public func kk_random_nextLong_until(_ receiver: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextInt(bound: until)
    }
    return Int.random(in: 0 ..< until)
}

@_cdecl("kk_random_nextLong_range")
public func kk_random_nextLong_range(_ receiver: Int, _ from: Int, _ until: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard until > from else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: receiver) {
        return box.nextIntRange(from: from, until: until)
    }
    return Int.random(in: from ..< until)
}

@_cdecl("kk_random_nextFloat")
public func kk_random_nextFloat(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_float_to_bits(box.nextFloat())
    }
    return kk_float_to_bits(Float.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextFloat_until")
public func kk_random_nextFloat_until(_ randomRaw: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = randomRaw
    outThrown?.pointee = 0
    let until = Float(bitPattern: UInt32(truncatingIfNeeded: untilBits))
    guard until > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive, but was \(until).")
        return 0
    }
    return kk_float_to_bits(Float.random(in: 0 ..< until))
}

@_cdecl("kk_random_nextDouble")
public func kk_random_nextDouble(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_double_to_bits(box.nextDouble())
    }
    return kk_double_to_bits(Double.random(in: 0 ..< 1))
}

@_cdecl("kk_random_nextDouble_until")
public func kk_random_nextDouble_until(_ randomRaw: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let until = kk_bits_to_double(untilBits)
    guard until > 0.0, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: until must be positive and finite, but was \(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_double_to_bits(box.nextDouble() * until)
    }
    return kk_double_to_bits(Double.random(in: 0.0 ..< until))
}

@_cdecl("kk_random_nextDouble_range")
public func kk_random_nextDouble_range(_ randomRaw: Int, _ fromBits: Int, _ untilBits: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let from = kk_bits_to_double(fromBits)
    let until = kk_bits_to_double(untilBits)
    guard until > from, from.isFinite, until.isFinite else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Random range is empty: \(from)..\(until).")
        return 0
    }
    if let box = seededBox(from: randomRaw) {
        return kk_double_to_bits(from + (box.nextDouble() * (until - from)))
    }
    return kk_double_to_bits(Double.random(in: from ..< until))
}

@_cdecl("kk_random_nextBoolean")
public func kk_random_nextBoolean(_ receiver: Int) -> Int {
    if let box = seededBox(from: receiver) {
        return kk_box_bool(box.nextBoolean() ? 1 : 0)
    }
    return kk_box_bool(Bool.random() ? 1 : 0)
}
