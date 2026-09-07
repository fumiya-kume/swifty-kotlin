package kotlin.reflect

import kotlin.internal.KsSymbolName

// KSP-496
// KClass member introspection: visibility, typeParameters, annotations, and
// the KCallable/KFunction/KProperty-returning collection accessors.
// Runtime bridges live in Sources/Runtime/RuntimeReflection.swift and
// Sources/Runtime/RuntimeStringArray.swift.
//
// NOTE: the collection accessors below (`members`, `constructors`, etc.)
// return `List<Any?>` rather than their real stdlib signatures (e.g.
// `Collection<KCallable<*>>`) — the returned runtime handles carry stable
// reflection nominal IDs (KSP-689), so `is`/`as` and shared `KCallable` metadata
// dispatch are valid at the Kotlin boundary, but the containing collection
// itself is not yet precisely typed.
//
// NOTE: `findAnnotation<T>()` / `findAssociatedObject<T>()` are NOT covered
// here — they take a reified type argument, which this compiler only
// supports for a fixed, non-nested set of built-in intrinsics (see how
// `typeOf<T>()` is special-cased). Forwarding a reified type parameter as
// the type argument of a *nested* reified call is not yet general, so they
// remain compiler special cases (Sources/CompilerCore/KIR/CallLowerer+KClassReflectMemberCalls.swift).
//
// NOTE: `properties` is also NOT covered here, unlike its `memberProperties`/
// `declaredMemberProperties` siblings. It is not a real kotlin-stdlib name
// (only the `member`/`declaredMember`-prefixed variants exist upstream), and
// Scripts/diff_cases/kclass_interface_handles.kt relies on being able to
// freely shadow it with a real user-declared extension for kotlinc
// portability. It remains a compiler special case so user shadowing keeps
// working exactly as before.

// ─── ABI bridges ─────────────────────────────────────────────────────────────

@KsSymbolName("__kk_kclass_visibility")
private external fun __kk_kclass_visibility(kclass: KClass<*>): String?

@KsSymbolName("__kk_kclass_type_parameters")
private external fun __kk_kclass_type_parameters(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_get_annotations")
private external fun __kk_kclass_get_annotations(kclass: KClass<*>): List<Annotation>

@KsSymbolName("__kk_kclass_members")
private external fun __kk_kclass_members(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_constructors")
private external fun __kk_kclass_constructors(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_nested_classes")
private external fun __kk_kclass_nested_classes(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_primary_constructor")
private external fun __kk_kclass_primary_constructor(kclass: KClass<*>): Any?

@KsSymbolName("__kk_kclass_member_properties")
private external fun __kk_kclass_member_properties(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_declared_member_properties")
private external fun __kk_kclass_declared_member_properties(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_functions")
private external fun __kk_kclass_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_member_functions")
private external fun __kk_kclass_member_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_declared_member_functions")
private external fun __kk_kclass_declared_member_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_supertypes")
private external fun __kk_kclass_supertypes(kclass: KClass<*>): List<Any?>

// ─── visibility / typeParameters / annotations ───────────────────────────────

/** Returns the visibility of this class, or `null` if unknown. */
public val KClass<*>.visibility: String?
    get() = __kk_kclass_visibility(this)

/** Returns the type parameters of this class. */
public val KClass<*>.typeParameters: List<Any?>
    get() = __kk_kclass_type_parameters(this)

/** Returns all annotations present on this class. */
public val KClass<*>.annotations: List<Annotation>
    get() = __kk_kclass_get_annotations(this)

// ─── member / constructor / supertype collections ────────────────────────────

/** Returns all functions and properties declared in this class and its supertypes. */
public val KClass<*>.members: List<Any?>
    get() = __kk_kclass_members(this)

/** Returns the constructors declared in this class. */
public val KClass<*>.constructors: List<Any?>
    get() = __kk_kclass_constructors(this)

/** Returns the classes declared directly inside this class. */
public val KClass<*>.nestedClasses: List<Any?>
    get() = __kk_kclass_nested_classes(this)

/** Returns the primary constructor of this class, or `null` if it has none. */
public val KClass<*>.primaryConstructor: Any?
    get() = __kk_kclass_primary_constructor(this)

/** Returns all non-extension member properties declared in this class and its supertypes. */
public val KClass<*>.memberProperties: List<Any?>
    get() = __kk_kclass_member_properties(this)

/** Returns non-extension member properties declared directly in this class, excluding supertypes. */
public val KClass<*>.declaredMemberProperties: List<Any?>
    get() = __kk_kclass_declared_member_properties(this)

/** Returns all non-extension functions declared in this class and its supertypes. */
public val KClass<*>.functions: List<Any?>
    get() = __kk_kclass_functions(this)

/** Returns all non-extension member functions declared in this class and its supertypes. */
public val KClass<*>.memberFunctions: List<Any?>
    get() = __kk_kclass_member_functions(this)

/** Returns non-extension member functions declared directly in this class, excluding supertypes. */
public val KClass<*>.declaredMemberFunctions: List<Any?>
    get() = __kk_kclass_declared_member_functions(this)

/** Returns the immediate supertypes of this class. */
public val KClass<*>.supertypes: List<Any?>
    get() = __kk_kclass_supertypes(this)
