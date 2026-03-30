/// Runtime ABI externs for function types (STDLIB-HOF-029)

// MARK: - Function type composition operations

/// Function1.andThen implementation
@_silgen_name("kk_function_andThen")
public func kk_function_andThen<T, R, NewR>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (R) -> NewR
) -> (T) -> NewR

/// Function1.compose implementation  
@_silgen_name("kk_function_compose")
public func kk_function_compose<NewT, T, R>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (NewT) -> T
) -> (NewT) -> R

/// Function2.curried implementation
@_silgen_name("kk_function_curried")
public func kk_function_curried<P1, P2, R>(
    _ f: @escaping (P1, P2) -> R
) -> (P1) -> (P2) -> R

/// Function.invoke implementation for all arities
@_silgen_name("kk_function_invoke")
public func kk_function_invoke(
    _ functionRaw: Int,
    _ arg: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

@_silgen_name("kk_function_invoke_0")
public func kk_function_invoke_0(
    _ functionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

@_silgen_name("kk_function_invoke_2")
public func kk_function_invoke_2(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

@_silgen_name("kk_function_invoke_3")
public func kk_function_invoke_3(
    _ functionRaw: Int,
    _ arg1: Int,
    _ arg2: Int,
    _ arg3: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

// MARK: - Suspend function type operations

/// Suspend function invoke
@_silgen_name("kk_suspend_function_invoke")
public func kk_suspend_function_invoke<T, R>(
    _ f: @escaping (T) async -> R,
    _ arg: T
) async -> R

@_silgen_name("kk_suspend_function_invoke_0")
public func kk_suspend_function_invoke_0<R>(
    _ f: @escaping () async -> R
) async -> R

// MARK: - Function type utilities

/// Function type creation helpers
@_silgen_name("kk_function_create_0")
public func kk_function_create_0(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

@_silgen_name("kk_function_create_1")
public func kk_function_create_1(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

@_silgen_name("kk_function_create_2")
public func kk_function_create_2(
    _ bodyRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int

// MARK: - Function type reflection

/// Get function arity
@_silgen_name("kk_function_arity")
public func kk_function_arity(_ function: Any) -> Int

/// Get function parameter types
@_silgen_name("kk_function_parameter_types")
public func kk_function_parameter_types(_ function: Any) -> [Any.Type]

/// Get function return type
@_silgen_name("kk_function_return_type")
public func kk_function_return_type(_ function: Any) -> Any.Type

// MARK: - Function type adaptation

/// Adapt function to different signature
@_silgen_name("kk_function_adapt")
public func kk_function_adapt<FromT, ToT, FromR, ToR>(
    _ f: @escaping (FromT) -> FromR,
    _ adapter: @escaping (ToT) -> FromT,
    _ resultAdapter: @escaping (FromR) -> ToR
) -> (ToT) -> ToR

/// Partial function application
@_silgen_name("kk_function_partial_apply")
public func kk_function_partial_apply<P1, P2, R>(
    _ f: @escaping (P1, P2) -> R,
    _ p1: P1
) -> (P2) -> R

@_silgen_name("kk_function_partial_apply_3")
public func kk_function_partial_apply_3<P1, P2, P3, R>(
    _ f: @escaping (P1, P2, P3) -> R,
    _ p1: P1,
    _ p2: P2
) -> (P3) -> R

// MARK: - Function type memoization

/// Memoize function with single parameter
@_silgen_name("kk_function_memoize")
public func kk_function_memoize<T: Hashable, R>(
    _ f: @escaping (T) -> R
) -> (T) -> R

/// Memoize function with two parameters
@_silgen_name("kk_function_memoize_2")
public func kk_function_memoize_2<P1: Hashable, P2: Hashable, R>(
    _ f: @escaping (P1, P2) -> R
) -> (P1, P2) -> R

// MARK: - Function type composition utilities

/// Pipe operator: f |> g = g(f(x))
@_silgen_name("kk_function_pipe")
public func kk_function_pipe<T, R, NewR>(
    _ f: @escaping (T) -> R,
    _ g: @escaping (R) -> NewR
) -> (T) -> NewR

/// Compose multiple functions
@_silgen_name("kk_function_compose_many")
public func kk_function_compose_many<T>(
    _ functions: [(Any) -> Any]
) -> (T) -> Any

// MARK: - Function type debugging

/// Function description for debugging
@_silgen_name("kk_function_description")
public func kk_function_description(_ function: Any) -> String

/// Function type signature
@_silgen_name("kk_function_signature")
public func kk_function_signature(_ function: Any) -> String
