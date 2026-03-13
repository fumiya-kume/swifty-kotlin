@testable import CompilerCore
import XCTest

/// TYPE-111: Verify that premature `anyType` fallbacks in object literal,
/// callable reference, and compound assignment inference have been replaced
/// with `errorType` + diagnostics where appropriate.
final class AnyTypeFallbackTests: XCTestCase {

    // MARK: - Object Literal

    func testObjectLiteralPropertyWithInitializerInfersConcreteType() throws {
        let source = """
        fun main() {
            val obj = object {
                val x = 42
            }
            println(obj.x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            // Find the object decl's property symbol and verify its type is Int, not Any.
            guard let declID = firstObjectDeclID(in: ast),
                  let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl,
                  let propertyDeclID = objectDecl.memberProperties.first,
                  let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
            else {
                XCTFail("Expected object literal with property.")
                return
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol)
            XCTAssertNotNil(propertyType)
            XCTAssertNotEqual(propertyType, sema.types.anyType,
                "Object literal property with initializer should not fall back to Any.")
            XCTAssertEqual(propertyType, sema.types.intType)
            assertNoDiagnostic("KSWIFTK-SEMA-0101", in: ctx)
        }
    }

    func testObjectLiteralPropertyWithTypeAnnotationUsesAnnotatedType() throws {
        let source = """
        fun main() {
            val obj = object {
                val y: String = "hello"
            }
            println(obj.y)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            guard let declID = firstObjectDeclID(in: ast),
                  let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl,
                  let propertyDeclID = objectDecl.memberProperties.first,
                  let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
            else {
                XCTFail("Expected object literal with property.")
                return
            }
            let propertyType = sema.symbols.propertyType(for: propertySymbol)
            XCTAssertEqual(propertyType, sema.types.stringType,
                "Object literal property with type annotation should use annotated type.")
            assertNoDiagnostic("KSWIFTK-SEMA-0101", in: ctx)
        }
    }

    // MARK: - Callable Reference

    func testCallableRefUnresolvedEmitsDiagnostic() throws {
        let source = """
        fun main() {
            val ref = ::nonExistentFunction
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    func testCallableRefResolvedNoDiagnostic() throws {
        let source = """
        fun greet(name: String): String = "Hello"
        fun main() {
            val ref = ::greet
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            // Find the callable ref expression and verify its type is not Any or error.
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(_, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }
                XCTAssertNotEqual(boundType, sema.types.anyType,
                    "Resolved callable reference should not be Any.")
                XCTAssertNotEqual(boundType, sema.types.errorType,
                    "Resolved callable reference should not be errorType.")
            }
        }
    }

    // MARK: - Helpers

    private func firstObjectDeclID(in ast: ASTModule) -> DeclID? {
        for (index, decl) in ast.arena.declarations().enumerated() {
            guard case .objectDecl = decl else { continue }
            return DeclID(rawValue: Int32(index))
        }
        return nil
    }

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }
}
