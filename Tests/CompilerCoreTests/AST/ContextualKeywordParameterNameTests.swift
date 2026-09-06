#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for value parameters / primary-constructor properties
/// whose name is literally a Kotlin modifier keyword (`inner`, `sealed`,
/// `override`, ...). These keywords are valid plain identifiers outside
/// modifier position, but `appendValueParameter`
/// (BuildASTPhase+DeclBuilders.swift) used to drop the whole parameter
/// whenever its resolved name matched a fixed "leading declaration keyword"
/// list, instead of recognizing that the keyword was occupying the name slot
/// rather than a modifier slot.
@Suite
struct ContextualKeywordParameterNameTests {
    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(ctx)
        return (try #require(ctx.ast), ctx)
    }

    private func firstFunDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
        ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(funDecl) = decl else { return nil }
            return funDecl
        }.first { interner.resolve($0.name) == name }
    }

    private func firstClassDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> ClassDecl? {
        ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case let .classDecl(classDecl) = decl else { return nil }
            return classDecl
        }.first { interner.resolve($0.name) == name }
    }

    private func firstObjectDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> ObjectDecl? {
        ast.arena.declarations().compactMap { decl -> ObjectDecl? in
            guard case let .objectDecl(objectDecl) = decl else { return nil }
            return objectDecl
        }.first { interner.resolve($0.name) == name }
    }

    private func firstInterfaceDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> InterfaceDecl? {
        ast.arena.declarations().compactMap { decl -> InterfaceDecl? in
            guard case let .interfaceDecl(interfaceDecl) = decl else { return nil }
            return interfaceDecl
        }.first { interner.resolve($0.name) == name }
    }

    private func firstTypeAliasDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> TypeAliasDecl? {
        ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first { interner.resolve($0.name) == name }
    }

    @Test
    func testModifierKeywordsRemainDeclarationNames() throws {
        let source = """
        package demo
        open class Base
        class inner(val x: Int) : Base()
        object sealed
        interface operator
        typealias override = Int
        """
        let (ast, ctx) = try buildAST(from: source)

        let innerClass = try #require(firstClassDecl(named: "inner", in: ast, interner: ctx.interner))
        #expect(innerClass.superTypeEntries.count == 1)
        #expect(firstObjectDecl(named: "sealed", in: ast, interner: ctx.interner) != nil)
        #expect(firstInterfaceDecl(named: "operator", in: ast, interner: ctx.interner) != nil)
        #expect(firstTypeAliasDecl(named: "override", in: ast, interner: ctx.interner) != nil)
    }

    @Test
    func testMultilineParameterNameStartingWithModifierKeywordKeepsGroupBalanced() throws {
        let source = """
        package demo
        fun makeIt(
            inner: Int,
            tag: Int
        ): Int = inner + tag
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "makeIt", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["inner", "tag"])
    }

    @Test
    func testOutParameterNameIsNotReservedAsVariance() throws {
        let source = """
        package demo
        fun read(out: Int): Int = out
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "read", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["out"])
    }

    @Test
    func testFunctionParameterNamedInnerIsNotDropped() throws {
        let source = """
        package demo
        fun makeIt(inner: Int, tag: Int): Int = inner + tag
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "makeIt", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["inner", "tag"])
    }

    @Test
    func testDataClassConstructorParameterNamedInnerIsNotDropped() throws {
        let source = """
        package demo
        data class Holder(val inner: Int, val tag: Int)
        """
        let (ast, ctx) = try buildAST(from: source)
        let classDecl = try #require(firstClassDecl(named: "Holder", in: ast, interner: ctx.interner))

        #expect(classDecl.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["inner", "tag"])
        let allAreProperties = classDecl.primaryConstructorParams.allSatisfy { $0.isProperty }
        #expect(allAreProperties)
    }

    @Test(arguments: [
        "sealed", "operator", "infix", "tailrec", "suspend", "inline", "enum",
        "annotation", "companion", "const", "lateinit", "open", "override",
        "actual", "expect", "external", "vararg", "crossinline", "noinline",
    ])
    func testValueParameterNamedWithModifierKeywordIsNotDropped(_ keyword: String) throws {
        let source = """
        package demo
        fun makeIt(\(keyword): Int, tag: Int): Int = \(keyword) + tag
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "makeIt", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == [keyword, "tag"])
    }

    @Test
    func testRealVarargModifierStillMarksParameterVararg() throws {
        let source = """
        package demo
        fun sum(vararg nums: Int): Int = 0
        """
        let (ast, ctx) = try buildAST(from: source)
        let funDecl = try #require(firstFunDecl(named: "sum", in: ast, interner: ctx.interner))
        let param = try #require(funDecl.valueParams.first)

        #expect(ctx.interner.resolve(param.name) == "nums")
        #expect(param.isVararg)
    }

    @Test
    func testConstructorPropertyNamedOverrideIsNotMisflaggedAsOverride() throws {
        let source = """
        package demo
        class Box(val override: Int)
        """
        let (ast, ctx) = try buildAST(from: source)
        let classDecl = try #require(firstClassDecl(named: "Box", in: ast, interner: ctx.interner))
        let param = try #require(classDecl.primaryConstructorParams.first)

        #expect(ctx.interner.resolve(param.name) == "override")
        #expect(param.isProperty)
        #expect(!param.isOverrideProperty)
    }

    @Test
    func testRealOverrideModifierStillMarksConstructorPropertyOverride() throws {
        let source = """
        package demo
        interface Named { val name: String }
        class Person(override val name: String) : Named
        """
        let (ast, ctx) = try buildAST(from: source)
        let classDecl = try #require(firstClassDecl(named: "Person", in: ast, interner: ctx.interner))
        let param = try #require(classDecl.primaryConstructorParams.first)

        #expect(ctx.interner.resolve(param.name) == "name")
        #expect(param.isOverrideProperty)
    }
}
#endif
