import Foundation

/// 関数型のランタイム実装 (STDLIB-HOF-029)
/// Function0-22 のインターフェースと拡張関数を提供

// MARK: - Function0

public protocol Function0 {
    associatedtype R
    func invoke() -> R
}

public extension Function0 {
    func call() -> R {
        return invoke()
    }
}

// MARK: - Function1

public protocol Function1 {
    associatedtype P1
    associatedtype R
    func invoke(_ p1: P1) -> R
}

public extension Function1 {
    func call(_ p1: P1) -> R {
        return invoke(p1)
    }
    
    /// 関数合成: f.andThen(g) = { x -> g(f(x)) }
    func andThen<NewR>(_ g: @escaping (R) -> NewR) -> (P1) -> NewR {
        return { [self] p1 in
            g(self.invoke(p1))
        }
    }
    
    /// 関数合成: f.compose(g) = { x -> f(g(x)) }
    func compose<NewT>(_ g: @escaping (NewT) -> P1) -> (NewT) -> R {
        return { [self] newT in
            self.invoke(g(newT))
        }
    }
}

// MARK: - Function2

public protocol Function2 {
    associatedtype P1
    associatedtype P2
    associatedtype R
    func invoke(_ p1: P1, _ p2: P2) -> R
}

public extension Function2 {
    func call(_ p1: P1, _ p2: P2) -> R {
        return invoke(p1, p2)
    }
    
    /// カリー化: (P1, P2) -> R -> P1 -> (P2 -> R)
    func curried() -> (P1) -> (P2) -> R {
        return { [self] p1 in
            return { p2 in
                self.invoke(p1, p2)
            }
        }
    }
}

// MARK: - Function3-22 (基本的な実装)

public protocol Function3 {
    associatedtype P1
    associatedtype P2
    associatedtype P3
    associatedtype R
    func invoke(_ p1: P1, _ p2: P2, _ p3: P3) -> R
}

public extension Function3 {
    func call(_ p1: P1, _ p2: P2, _ p3: P3) -> R {
        return invoke(p1, p2, p3)
    }
}

public protocol Function4 {
    associatedtype P1
    associatedtype P2
    associatedtype P3
    associatedtype P4
    associatedtype R
    func invoke(_ p1: P1, _ p2: P2, _ p3: P3, _ p4: P4) -> R
}

public extension Function4 {
    func call(_ p1: P1, _ p2: P2, _ p3: P3, _ p4: P4) -> R {
        return invoke(p1, p2, p3, p4)
    }
}

// 必要に応じてFunction5-22も同様に実装...
// ここでは主要なFunction0-4までを実装

// MARK: - 関数型のユーティリティ

/// MARK: - 関数型を生成するヘルパー関数

public struct Function0Impl<R>: Function0 {
    let body: () -> R
    public func invoke() -> R { body() }
}

public struct Function1Impl<P1, R>: Function1 {
    let body: (P1) -> R
    public func invoke(_ p1: P1) -> R { body(p1) }
}

public struct Function2Impl<P1, P2, R>: Function2 {
    let body: (P1, P2) -> R
    public func invoke(_ p1: P1, _ p2: P2) -> R { body(p1, p2) }
}

public func function0<R>(_ body: @escaping () -> R) -> Function0Impl<R> {
    return Function0Impl(body: body)
}

public func function1<P1, R>(_ body: @escaping (P1) -> R) -> Function1Impl<P1, R> {
    return Function1Impl(body: body)
}

public func function2<P1, P2, R>(_ body: @escaping (P1, P2) -> R) -> Function2Impl<P1, P2, R> {
    return Function2Impl(body: body)
}

// MARK: - Suspend関数型のサポート

public protocol SuspendFunction0 {
    associatedtype R
    func invoke() async -> R
}

public protocol SuspendFunction1 {
    associatedtype P1
    associatedtype R
    func invoke(_ p1: P1) async -> R
}

public protocol SuspendFunction2 {
    associatedtype P1
    associatedtype P2
    associatedtype R
    func invoke(_ p1: P1, _ p2: P2) async -> R
}

// MARK: - ランタイム関数型操作

/// 関数型の合成を行うランタイム関数
@_silgen_name("kk_function_andThen")
public func kk_function_andThen<T, R, NewR>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (R) -> NewR
) -> (T) -> NewR {
    return { g(f($0)) }
}

@_silgen_name("kk_function_compose")
public func kk_function_compose<NewT, T, R>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (NewT) -> T
) -> (NewT) -> R {
    return { f(g($0)) }
}

@_silgen_name("kk_function_curried")
public func kk_function_curried<P1, P2, R>(
    _ f: @escaping (P1, P2) -> R
) -> (P1) -> (P2) -> R {
    return { p1 in
        return { p2 in
            f(p1, p2)
        }
    }
}

func runtimeFunctionValueBox(from rawValue: Int) -> RuntimeFunctionValueBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeFunctionValueBox.self)
}

private func runtimeFunctionInvokeInvalidArity(expected: Int, actual: Int) -> Int {
    runtimeAllocateThrowable(message: "Function invoke arity mismatch: expected \(expected), got \(actual)")
}

@_cdecl("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 1 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 1, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint1.self)
        return function(box.closureRaw, arg, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint1.self)
    return function(arg, outThrown)
}

@_cdecl("kk_function_invoke_0")
public func kk_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 0 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 0, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureThunkEntryPoint.self)
        return function(box.closureRaw, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKThunkEntryPoint.self)
    return function(outThrown)
}

@_cdecl("kk_function_invoke_2")
public func kk_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 2 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 2, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        return function(box.closureRaw, arg1, arg2, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint2.self)
    return function(arg1, arg2, outThrown)
}

@_cdecl("kk_function_invoke_3")
public func kk_function_invoke_3(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if let box = runtimeFunctionValueBox(from: functionRaw) {
        guard box.arity == 3 else {
            outThrown?.pointee = runtimeFunctionInvokeInvalidArity(expected: 3, actual: box.arity)
            return 0
        }
        let function = unsafeBitCast(box.fnPtr, to: KKClosureFunctionEntryPoint3.self)
        return function(box.closureRaw, arg1, arg2, arg3, outThrown)
    }
    let function = unsafeBitCast(functionRaw, to: KKFunctionEntryPoint3.self)
    return function(arg1, arg2, arg3, outThrown)
}

@_cdecl("kk_function_create_0")
public func kk_function_create_0(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 0))
}

@_cdecl("kk_function_create_1")
public func kk_function_create_1(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 1))
}

@_cdecl("kk_function_create_2")
public func kk_function_create_2(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard bodyRaw != 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid function body")
        return 0
    }
    return registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: bodyRaw, closureRaw: closureRaw, arity: 2))
}

// MARK: - 型消去ヘルパー

/// 型消去された関数型
public struct AnyFunction0<R> {
    private let body: () -> R
    
    public init(_ body: @escaping () -> R) {
        self.body = body
    }
    
    public func call() -> R {
        return body()
    }
}

public struct AnyFunction1<P1, R> {
    private let body: (P1) -> R
    
    public init(_ body: @escaping (P1) -> R) {
        self.body = body
    }
    
    public func call(_ p1: P1) -> R {
        return body(p1)
    }
    
    public func andThen<NewR>(_ g: @escaping (R) -> NewR) -> AnyFunction1<P1, NewR> {
        return AnyFunction1<P1, NewR> { [self] p1 in
            g(self.body(p1))
        }
    }
    
    public func compose<NewT>(_ g: @escaping (NewT) -> P1) -> AnyFunction1<NewT, R> {
        return AnyFunction1<NewT, R> { [self] newT in
            self.body(g(newT))
        }
    }
}

public struct AnyFunction2<P1, P2, R> {
    private let body: (P1, P2) -> R
    
    public init(_ body: @escaping (P1, P2) -> R) {
        self.body = body
    }
    
    public func call(_ p1: P1, _ p2: P2) -> R {
        return body(p1, p2)
    }
    
    public func curried() -> AnyFunction1<P1, AnyFunction1<P2, R>> {
        return AnyFunction1<P1, AnyFunction1<P2, R>> { [self] p1 in
            return AnyFunction1<P2, R> { p2 in
                self.body(p1, p2)
            }
        }
    }
}
