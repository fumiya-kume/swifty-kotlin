了解。ここからは **「実装レベルの API 仕様（Swift の型・関数・データフォーマットまで固定）」**を、Phase ごとに “Doc” として提示します。
このセットを参照すれば、外部ドキュメントを読まずとも（曖昧点は参照 `kotlinc` による差分テストで確定させる前提で）完成まで走れる粒度に落とします。

前提（この仕様書で固定する基準）：

* **Kotlin 2.3.10 の stable 範囲**を対象（公式 Grammar は “latest stable で experimental 無効ルール除外” を明示） ([Kotlin][1])
* セマンティクスは Kotlin/Core を基準（式・宣言・型・オーバーロード解決） ([Kotlin][2])
* Coroutines は Kotlin spec の CPS 変換モデルを実装（`Continuation<T>` 追加引数 + `Any?` 戻り、suspend/return 判定） ([Kotlin][3])
* 実行環境は **macOS のみ**。開発は Xcode 26（Swift 6.2）を基準 ([Apple Developer][4])

---

# Doc J0: 実装方針と “規約” 固定（全 Phase 共通）

## J0.1 リポジトリ規約（必須）

* すべて SwiftPM パッケージ。
* すべてのモジュールは `public` API を最小にし、内部は `internal` に閉じる。
* すべての “ID” は整数で表し、参照は **インターン（intern）**で統一（String/Type/Symbol を直接比較しない）。

## J0.2 コンパイラの決定性（必須）

同一入力・同一オプションで出力がビットレベルで一致する（DWARF を除く）こと。

* HashMap の iteration 順に依存しない（ソートして出す）。
* 乱数禁止。

## J0.3 エラー耐性（必須）

* どんな入力でもクラッシュしない。
* `fatalError` は “内部不整合（ICE）” のみに限定し、必ず `KSWIFTK-ICE-xxxx` を出す。

## J0.4 Kotlin 2.3 の安定機能差分（注意点）

Kotlin 2.3.0 で stable 化／既定有効化された要素は互換対象：

* **nested type aliases**
* **when の data-flow ベース exhaustiveness**
* **明示戻り型がある expression body で `return` 許可（既定有効）** ([Kotlin][5])

この仕様書ではこれらを “必須” とし、テストで保証する。

---

# Doc J1: Driver / コンパイルモデル（`KSwiftKCLI` + `CompilerCore`）

## J1.1 主要型（Swift）

```swift
public struct CompilerVersion: Equatable {
    public let major: Int, minor: Int, patch: Int
    public let gitHash: String?
}

public enum KotlinLanguageVersion: Equatable {
    case v2_3_10
}

public struct TargetTriple: Equatable {
    public let arch: String         // "arm64" or "x86_64"
    public let vendor: String       // "apple"
    public let os: String           // "macosx"
    public let osVersion: String?   // optional
}

public enum OptimizationLevel: Int { case O0, O1, O2, O3 }

public struct CompilerOptions: Equatable {
    public var moduleName: String
    public var inputs: [String]              // paths
    public var outputPath: String
    public var emit: EmitMode                // exe/obj/llvm/kir
    public var searchPaths: [String]         // -I
    public var libraryPaths: [String]        // -L
    public var linkLibraries: [String]       // -l
    public var target: TargetTriple
    public var optLevel: OptimizationLevel
    public var debugInfo: Bool               // -g
    public var frontendFlags: [String]
    public var irFlags: [String]
    public var runtimeFlags: [String]
}

public enum EmitMode { case executable, object, llvmIR, kirDump, library }
```

## J1.2 コンパイルの “単位”

* **CompilationSession**: 1回の `kswiftc` 実行
* **Module**: Kotlin の “名前空間 + 生成物” 単位（`moduleName`）
* **Library**: 別 Module を import 可能にする配布形態（Doc J12）

## J1.3 パイプライン API（固定）

```swift
public final class CompilerDriver {
    public init(version: CompilerVersion, kotlinVersion: KotlinLanguageVersion)

    public func run(options: CompilerOptions) -> Int  // exit code
}

public final class CompilationContext {
    public let options: CompilerOptions
    public let sourceManager: SourceManager
    public let diagnostics: DiagnosticEngine

    public var tokens: [Token] = []
    public var cst: SyntaxArena? = nil
    public var ast: ASTModule? = nil
    public var sema: SemaModule? = nil
    public var kir: KIRModule? = nil
}
```

## J1.4 Phase 実行プロトコル

```swift
public protocol CompilerPhase {
    static var name: String { get }
    func run(_ ctx: CompilationContext) throws
}
```

* `CompilerDriver` は以下順で Phase を実行し、失敗時は診断を出して停止：

  1. LoadSources
  2. Lex
  3. Parse
  4. BuildAST
  5. SemaPasses（複数）
  6. BuildKIR
  7. Lowerings（複数）
  8. Codegen
  9. Link

---

# Doc J2: SourceManager / 位置情報 / 診断（`CompilerCore`）

## J2.1 位置情報（必須）

Kotlin の診断は 1-indexed line/column で表示。

```swift
public struct FileID: Hashable { public let rawValue: Int }

public struct SourceLocation: Equatable {
    public let file: FileID
    public let offset: Int   // UTF-8 byte offset
}

public struct SourceRange: Equatable {
    public let start: SourceLocation
    public let end: SourceLocation
}

public struct LineColumn: Equatable {
    public let line: Int     // 1-based
    public let column: Int   // 1-based (unicode scalar count)
}
```

## J2.2 SourceManager

```swift
public final class SourceManager {
    public func addFile(path: String, contents: Data) -> FileID
    public func addFile(path: String) throws -> FileID

    public func contents(of file: FileID) -> Data
    public func path(of file: FileID) -> String

    public func lineColumn(of loc: SourceLocation) -> LineColumn
    public func slice(_ range: SourceRange) -> Substring
}
```

必須要件：

* UTF-8 を内部表現として保持。
* `lineColumn` は改行インデックスを前計算（`[Int] lineStartOffsets`）して O(log N) で求める。

## J2.3 DiagnosticEngine

```swift
public enum DiagnosticSeverity { case error, warning, note, info }

public struct Diagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let code: String              // "KSWIFTK-PARSE-0001"
    public let message: String
    public let primaryRange: SourceRange?
    public let secondaryRanges: [SourceRange]
}

public final class DiagnosticEngine {
    public private(set) var diagnostics: [Diagnostic] = []

    public func emit(_ d: Diagnostic)
    public func error(_ code: String, _ message: String, range: SourceRange?)
    public func warning(_ code: String, _ message: String, range: SourceRange?)
    public var hasError: Bool { get }
}
```

表示フォーマットは Doc 0 の通り。

---

# Doc J3: 文字列インターン / ID 系（全モジュール共通）

## J3.1 Interner（必須）

* **Identifier / FQName / String literal / Operator** 等をインターン。
* `String` 比較を避け、`Int32` 比較に寄せる。

```swift
public struct InternedString: Hashable { public let rawValue: Int32 }

public final class StringInterner {
    public func intern(_ s: String) -> InternedString
    public func resolve(_ id: InternedString) -> String
}
```

## J3.2 ID の命名規約

* `TokenID`, `NodeID`, `SymbolID`, `TypeID`, `DeclID` などは `Int32`。
* “未設定” は `-1` を使用（Optional を乱用しない）。

---

# Doc J4: Lexer 詳細 API（`KotlinLexer`）

Kotlin の lexical/syntax ルールは spec と公式 grammar を基準にする。 ([Kotlin][6])
実装時の参照として Kotlin spec の ANTLR lexer 定義（KotlinLexer.g4）も利用可能（ただしコード生成はしない）。 ([GitHub][7])

## J4.1 Token モデル

```swift
public enum TriviaPiece: Equatable {
    case spaces(Int)
    case tabs(Int)
    case newline              // 1回分
    case lineComment(String)  // "//..."
    case blockComment(String) // "/*...*/"
    case shebang(String)      // "#!..."
}

public enum TokenKind: Equatable {
    case identifier(InternedString)
    case backtickedIdentifier(InternedString)

    case keyword(Keyword)
    case softKeyword(SoftKeyword) // parser が必要に応じて解釈する

    case intLiteral(String)    // raw text (後で数値化)
    case longLiteral(String)
    case floatLiteral(String)
    case doubleLiteral(String)
    case charLiteral(UInt32)   // unicode scalar
    case stringSegment(InternedString) // "abc" の literal 部分
    case stringQuote           // "
    case rawStringQuote        // """
    case templateExprStart     // ${
    case templateExprEnd       // }
    case templateSimpleNameStart // $name

    case symbol(Symbol)        // operators & punctuators
    case eof
}

public struct Token: Equatable {
    public let kind: TokenKind
    public let range: SourceRange
    public let leadingTrivia: [TriviaPiece]
    public let trailingTrivia: [TriviaPiece]
}
```

## J4.2 Keyword / SoftKeyword / Symbol（固定）

* Keyword は Kotlin の “ハードキーワード” を全部列挙する（`class`, `fun`, `val`, `var`, `object`, …, `suspend`, `inline`, `reified`, `expect`, `actual` など）。
* SoftKeyword は Kotlin の “文脈依存語” を列挙（例：`by`, `get`, `set`, `field`, `property`, `receiver`, `param`, `setparam`, `delegate`, `file`, `where`, `constructor`, `init` 等）。
  ※ lexer は `identifier` として出してもよいが、この仕様では **softKeyword を kind として区別**し、parser での分岐を簡単にする（失敗時も identifier と互換扱いにできる）。

Symbol は `+ - * / % ++ -- && || ! == != <= >= < > = += -= *= /= %= .. ..< ?: ?. !! :: , . ; : -> => ( ) [ ] { } @ #` を全列挙。

## J4.3 Lexer API

```swift
public final class KotlinLexer {
    public init(file: FileID,
                source: Data,
                interner: StringInterner,
                diagnostics: DiagnosticEngine)

    public func lexAll() -> [Token]
}
```

必須要件：

* 文字列テンプレート用の **状態機械**を実装：

  * default
  * string（`"`）
  * rawString（`"""`）
  * template（`${ ... }` で入れ子可能）

* **改行は trivia として必ず保持**（ASI に必要）。
  parser 側は statement 境界の判断で `newline` trivia を参照可能にする。

## J4.4 lexer のエラー規約（必須）

* 不正なエスケープ、閉じていないコメント/文字列、数値フォーマット不正 → `KSWIFTK-LEX-xxxx` を emit。
* 可能なら復帰して lex 継続（EOF まで）。

---

# Doc J5: Parser / CST Arena / エラー回復（`KotlinParser` + `KotlinSyntaxTree`）

公式 grammar は “latest stable & experimental 除外” が基準。 ([Kotlin][1])
spec の syntax grammar には `kotlinFile` / `script` / `semi` があるので、これを最上位として実装する。 ([Kotlin][2])

## J5.1 CST は “Arena + ID” で固定

### SyntaxArena

```swift
public struct NodeID: Hashable { public let rawValue: Int32 }
public struct TokenID: Hashable { public let rawValue: Int32 }

public enum SyntaxChild {
    case node(NodeID)
    case token(TokenID)
}

public struct SyntaxNode {
    public let kind: SyntaxKind
    public let range: SourceRange
    public let firstChildIndex: Int32
    public let childCount: Int16
}

public final class SyntaxArena {
    public private(set) var nodes: [SyntaxNode] = []
    public private(set) var children: [SyntaxChild] = []
    public private(set) var tokens: [Token] = []

    public func appendToken(_ t: Token) -> TokenID
    public func makeNode(kind: SyntaxKind, range: SourceRange, _ kids: [SyntaxChild]) -> NodeID
    public func node(_ id: NodeID) -> SyntaxNode
    public func children(of id: NodeID) -> ArraySlice<SyntaxChild>
}
```

### SyntaxKind（最低限の粒度）

* `kotlinFile`, `script`, `packageHeader`, `importList`, `importHeader`
* 宣言：`classDecl`, `objectDecl`, `interfaceDecl`, `funDecl`, `propertyDecl`, `typeAliasDecl`, `enumEntry`, …
* 文：`statement`, `block`, `loopStmt`, `tryExpr`, …
* 式：`ifExpr`, `whenExpr`, `callExpr`, `binaryExpr`, `unaryExpr`, `lambdaLiteral`, `objectLiteral`, `stringTemplate`, `callableRef`, …
* 型：`typeRef`, `nullableType`, `functionType`, `suspendFunctionType`, `typeArgs`, `typeProjection`, …

粒度は “後段の AST Builder が楽になる” 範囲で良い。**CST は lossless で token を保持できる**のが最重要。

## J5.2 Parser API（固定）

```swift
public final class KotlinParser {
    public init(tokens: [Token],
                interner: StringInterner,
                diagnostics: DiagnosticEngine)

    public func parseFile() -> (arena: SyntaxArena, root: NodeID)
}
```

## J5.3 TokenStream 補助

```swift
public final class TokenStream {
    public let tokens: [Token]
    public private(set) var index: Int = 0

    public func peek(_ k: Int = 0) -> Token
    public func advance() -> Token
    public func atEOF() -> Bool
    public func consumeIf(_ predicate: (Token) -> Bool) -> Token?
}
```

## J5.4 エラー回復（必須）

* “同期点” を固定：

  * トップレベル：`class/fun/val/var/object/interface/typealias/import/package`, `}`, `EOF`
  * ブロック内：`;`/改行, `}`, `catch/finally`, `else`
* 回復戦略：

  1. 期待トークン欠如 → **missing token** を仮想挿入（Node に `isMissing` フラグを持たせてもよい）
  2. 不要トークン → 破棄して進む
  3. どうにもならない → 同期点までスキップ

## J5.5 `<T>` vs `<` の曖昧性（必須）

Kotlin パース最大の地雷なので、ここは仕様で固定する：

* Parser は “型引数を読みたい文脈” でのみ `<` を type-args 開始として解釈する。
* 文脈判定関数：

  * `canStartTypeArguments(after: NodeID/Token)` を設け、
  * 次トークン列を最大 N=32 まで先読みして `>` まで整合が取れたら type-args とみなす。
* 整合条件（最低限）：

  * `<` の内側は `typeProjection (',' typeProjection)*` としてパース可能
  * `>` の直後が “呼び出し/参照に続けられるもの（`(`, `.`, `::`, `?., !!., <` etc）” である

失敗したら通常の `<` 演算子として扱う（戻す）。

---

# Doc J6: AST（`KotlinAST`）と CST→AST 変換（`BuildAST` Phase）

## J6.1 AST の目的

* CST の trivia/token 詳細は落とし、**意味解析に必要な構造**だけ残す。
* ただし **位置情報（SourceRange）**は必ず保持する。

## J6.2 AST の基本表現

* AST も “Arena + ID” で揃える（メモリ効率と参照安定）。

```swift
public struct ASTNodeID: Hashable { public let rawValue: Int32 }
public struct DeclID: Hashable { public let rawValue: Int32 }
public struct ExprID: Hashable { public let rawValue: Int32 }
public struct TypeRefID: Hashable { public let rawValue: Int32 }

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
}

public struct ASTFile {
    public let fileID: FileID
    public let packageFQName: [InternedString]
    public let imports: [ImportDecl]
    public let topLevelDecls: [DeclID]
}
```

### 代表ノード（抜粋）

```swift
public enum Decl {
    case classDecl(ClassDecl)
    case funDecl(FunDecl)
    case propertyDecl(PropertyDecl)
    case typeAliasDecl(TypeAliasDecl)
    case objectDecl(ObjectDecl)
    case enumEntry(EnumEntryDecl)
    // ...
}

public struct FunDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let receiverType: TypeRefID?
    public let valueParams: [ValueParamDecl]
    public let returnType: TypeRefID?
    public let body: FunctionBody // block or exprBody
    public let isSuspend: Bool
    public let isInline: Bool
}
```

## J6.3 Modifiers（固定）

`Modifiers` は bitset で持つ：

* visibility: public/internal/protected/private
* modality: final/open/abstract/sealed
* classKind: data/enum/annotation/value
* fun: inline/tailrec/operator/infix/external/suspend
* param: noinline/crossinline/vararg
* expect/actual

## J6.4 AST Builder の責務

* CST を walking し、AST を生成
* この段階では **解決しない**（識別子は raw のまま）
* ただし “構文糖衣” は残してよい（desugar は KIR lowering）

---

# Doc J7: シンボル・スコープ・解決（`KotlinSemantics`）

Kotlin/Core の仕様範囲（式・宣言・型・オーバーロード解決）をここで実装する。 ([Kotlin][2])

## J7.1 SymbolID と Symbol

```swift
public struct SymbolID: Hashable { public let rawValue: Int32 }

public enum SymbolKind {
    case package, `class`, `interface`, object, enumClass, annotationClass
    case typeAlias
    case function
    case constructor
    case property
    case field
    case typeParameter
    case valueParameter
    case local
    case label
}

public struct Symbol {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]   // package + nested
    public let declSite: SourceRange?
    public let visibility: Visibility
    public let flags: SymbolFlags
}
```

## J7.2 Scope（固定）

```swift
public protocol Scope {
    var parent: Scope? { get }
    func lookup(_ name: InternedString) -> [SymbolID]
    func insert(_ sym: SymbolID)
}
```

実装：

* `FileScope`, `PackageScope`, `ImportScope`, `ClassMemberScope`, `FunctionScope`, `BlockScope`

lookup 優先順位（固定）：

1. ローカル（block → function → class）
2. 明示 import
3. ワイルドカード import
4. デフォルト import（stdlib）

## J7.3 2パス（必須）

* Pass A: “ヘッダ収集”

  * クラス名、型パラメータ、関数シグネチャ、プロパティ型（明示があれば）
  * 相互再帰を許すため、body はまだ見ない
* Pass B: “本体解析”

  * 初期化子、関数 body、getter/setter、init ブロック

## J7.4 Sema の出力（SemaModule）

```swift
public final class SemaModule {
    public let symbols: SymbolTable
    public let types: TypeSystem
    public let bindings: BindingTable // AST node -> Symbol/Type
    public let diagnostics: DiagnosticEngine
}
```

`BindingTable` は最低限：

* `ExprID -> TypeID`
* `IdentifierExpr -> SymbolID`
* `CallExpr -> CalleeSymbolID + chosen overload`
* `DeclID -> SymbolID`

---

# Doc J8: 型システムと TypeID（`TypeSystem`）

## J8.1 TypeID と型表現

```swift
public struct TypeID: Hashable { public let rawValue: Int32 }

public enum Nullability { case nonNull, nullable }

public enum TypeKind {
    case error
    case unit
    case nothing
    case any(Nullability)

    case primitive(PrimitiveType, Nullability) // nullable primitive は原則 box へ lowering
    case classType(ClassType)
    case typeParam(TypeParamType)
    case functionType(FunctionType)
    case intersection([TypeID])
}

public struct ClassType {
    public let classSymbol: SymbolID
    public let args: [TypeArg]
    public let nullability: Nullability
}

public enum TypeArg {
    case invariant(TypeID)
    case out(TypeID)
    case `in`(TypeID)
    case star
}

public struct FunctionType {
    public let receiver: TypeID?
    public let params: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let nullability: Nullability
}
```

## J8.2 TypeSystem API

```swift
public final class TypeSystem {
    public func make(_ kind: TypeKind) -> TypeID
    public func kind(of id: TypeID) -> TypeKind

    public func isSubtype(_ a: TypeID, _ b: TypeID) -> Bool
    public func lub(_ types: [TypeID]) -> TypeID
    public func glb(_ types: [TypeID]) -> TypeID
}
```

必須：

* `Nothing` はすべての型の subtype
* nullable/non-null の規則
* 関数型の variance（パラメータ反変、戻り共変）
* 型引数 variance（declaration-site + use-site を合成）

---

# Doc J9: 型推論（制約）・オーバーロード解決（`ConstraintSolver` + `OverloadResolver`）

## J9.1 制約変数（TypeVar）

```swift
public struct TypeVarID: Hashable { public let rawValue: Int32 }

public enum ConstraintKind { case subtype, equal, supertype }

public struct Constraint {
    public let kind: ConstraintKind
    public let left: TypeID
    public let right: TypeID
    public let blameRange: SourceRange?
}
```

## J9.2 推論プロトコル

* 式ごとに “期待型 expectedType” を受け取り推論する（Kotlin のローカル推論に寄せる）。
* `CallExpr` は：

  1. 候補関数群を収集
  2. それぞれに type vars を割り当て
  3. 引数から制約生成
  4. solve
  5. 最良候補選択（tie は曖昧エラー）

## J9.3 API（固定）

```swift
public final class ConstraintSolver {
    public func solve(vars: [TypeVarID],
                      constraints: [Constraint],
                      typeSystem: TypeSystem) -> Solution
}

public struct Solution {
    public let substitution: [TypeVarID: TypeID]
    public let isSuccess: Bool
    public let failure: Diagnostic?
}
```

## J9.4 オーバーロード解決（固定）

```swift
public final class OverloadResolver {
    public func resolveCall(candidates: [SymbolID],
                            call: CallExpr,
                            expectedType: TypeID?,
                            ctx: SemaContext) -> ResolvedCall
}
```

`ResolvedCall` は以下を含む：

* chosen callee symbol
* substituted type arguments（推論結果）
* parameter mapping（名前引数・デフォルト引数・vararg 展開結果）

---

# Doc J10: Data-flow / Smart cast / when exhaustiveness（Kotlin 2.3 の要点）

Kotlin 2.3 で when の exhaustiveness が data-flow ベースで強化されているので、ここを必ず実装対象に含める。 ([Kotlin][5])

## J10.1 DFA 状態モデル（固定）

* 各ローカル変数/プロパティ参照に対し：

  * `possibleTypes: Set<TypeID>`
  * `nullability: Nullability`
  * `isStable: Bool`（stable smart cast できるか）
* 条件式を解析して “true 分岐/false 分岐” の状態を分岐生成。

## J10.2 when exhaustiveness（必須）

* sealed class / enum / Boolean / nullable の exhaustiveness を判定し、
* expression として使われる when が non-exhaustive なら診断（error or warning は Kotlin に合わせる：差分テストで確定）。

---

# Doc J11: KIR（型付き IR）と Pass API（`KotlinIR`）

## J11.1 KIR の基本

* AST + Sema を受けて “型が付いた IR” を生成。
* KIR は lowering の対象なので、構文糖衣を残してよいが、**名前解決と型**は確定していること。

## J11.2 KIR Arena

AST と同様に ID/arena で固定。

```swift
public struct KIRDeclID: Hashable { public let rawValue: Int32 }
public struct KIRExprID: Hashable { public let rawValue: Int32 }
public struct KIRTypeID: Hashable { public let rawValue: Int32 } // 実体は TypeID 参照でも可

public final class KIRModule {
    public let files: [KIRFile]
    public let arena: KIRArena
}

public protocol KIRPass {
    static var name: String { get }
    func run(module: KIRModule, ctx: KIRContext) throws
}
```

## J11.3 例外モデル（固定：明示チャネル）

* unwind は使わない。
* すべての “throw 可能” 呼び出しは `outThrown`（runtime の `KThrowable*`）を持つ ABI へ lowering（後述 Doc J13/J15）。

---

# Doc J12: Lowering 仕様（Kotlin → 実行可能形への機械変換）

## J12.1 パス順（固定）

1. NormalizeBlocks
2. OperatorLowering
3. ForLowering（iterator/hasNext/next）
4. WhenLowering
5. PropertyLowering（backing field / delegated）
6. DataEnumSealedSynthesis
7. LambdaClosureConversion
8. InlineLowering
9. CoroutineLowering
10. ABILowering（boxing/exception channel/vtable slots）

## J12.2 各 lowering の “入力/出力条件”

例：OperatorLowering

* 入力：`binaryExpr(op:"+")`
* 出力：`call(receiver.plus(arg))` または `call(plus(receiver,arg))`（拡張候補含む）
* 条件：候補解決は sema 済みなので、ここでは chosen symbol に対して call へ落とすだけ

ForLowering

* `for (x in y) body`
* `val it = y.iterator(); while(it.hasNext()) { val x = it.next(); body }`

InlineLowering

* inline 関数の body を call site に複製
* `reified` は runtime type token を hidden arg として渡す（Doc J16）

---

# Doc J13: Name Mangling / ABI（Swift runtime との結合仕様）

この仕様書は “独自 backend” なので、JetBrains の mangling 互換は要求しない。**ただし安定で衝突しない** mangling を規定する。

## J13.1 シンボル名 mangling（固定）

### 基本形式

```
_KK_<module>__<fqname>__<declkind>__<signature>__<hash>
```

* `<module>`: moduleName
* `<fqname>`: package + nested class 名を `_` で連結（各要素は length-prefix でエスケープ）
* `<declkind>`: F(unction)/C(lass)/P(roperty)/K(onstructor)/G(et)/S(et)…
* `<signature>`: erased signature（型引数は `T`、nullable は `Q` など符号化）
* `<hash>`: 8桁 hex（FNV-1a 32bit）

### 型符号化（例）

* `Int` -> `I`
* `Long` -> `J`
* `Boolean` -> `Z`
* `String` -> `Lkotlin_String;`
* `T?` -> `Q<T>`
* `Function2<A,B,R>` -> `F2<A,B,R>`
* `suspend` 関数型 -> `SF…`

## J13.2 クラスレイアウト（固定）

* heap object header:

  * `typeInfo*`
  * `flags`
  * `size`
* フィールドは 8 byte alignment。
* vtable slot は “継承順 + override で同 slot” の規則で割り当てる。
* interface dispatch は itable（interface ごとに method table）で実装。

## J13.3 例外チャネル ABI（固定）

最終的に lowering された関数 ABI：

* 戻りあり：`(args..., outThrown: *KThrowable?) -> Ret`
* 戻りなし：`(args..., outThrown: *KThrowable?) -> Void`

call site は：

* outThrown != nil なら “例外経路” へ分岐。
* try/catch は “例外値をローカルに束縛して分岐” で実装（unwind 不要）。

---

# Doc J14: Library 形式（`.kklib`）と separate compilation（macOS 専用）

“フル Kotlin” を現実的に使うには別モジュール import が必要なので、配布形式を固定する。

## J14.1 `.kklib` は “ディレクトリ” で固定（最初は zip 不要）

```
Foo.kklib/
  manifest.json
  metadata.bin
  objects/
    Foo_0.o
    Foo_1.o
  inline-kir/
    <mangled>.kirbin
  resources/ (optional)
```

## J14.2 `manifest.json`（固定スキーマ）

```json
{
  "formatVersion": 1,
  "moduleName": "Foo",
  "kotlinLanguageVersion": "2.3.10",
  "compilerVersion": "0.1.0",
  "target": "arm64-apple-macosx",
  "objects": ["objects/Foo_0.o"],
  "metadata": "metadata.bin",
  "inlineKIRDir": "inline-kir"
}
```

## J14.3 `metadata.bin`（最小要件）

* public API の “ヘッダ情報” を入れる（型・シグネチャ・vtable slot・field offsets）
* inline 関数は body を `inline-kir/` に保存し、import 側がインライン展開できるようにする。

**注意**：この方式は Kotlin の inline を跨モジュールで成立させるために必須。

---

# Doc J15: LLVM Backend API（`LLVMBackend`）

## J15.1 依存と目標

* Swift から LLVM C API を呼ぶ（modulemap + SwiftPM）。
* 出力：Mach-O object（.o）→ clang で link。

## J15.2 Backend の主要型

```swift
public final class LLVMBackend {
    public init(target: TargetTriple,
                optLevel: OptimizationLevel,
                debugInfo: Bool,
                diagnostics: DiagnosticEngine)

    public func emitObject(module: KIRModule,
                           runtime: RuntimeLinkInfo,
                           outputObjectPath: String) throws

    public func emitLLVMIR(module: KIRModule,
                           runtime: RuntimeLinkInfo,
                           outputIRPath: String) throws
}

public struct RuntimeLinkInfo {
    public let libraryPaths: [String]
    public let libraries: [String]     // -lKotlinRuntime 等
    public let extraObjects: [String]
}
```

## J15.3 文字列・配列・例外・コルーチンの呼び出し境界

backend は “言語コア操作” を runtime 関数呼び出しに落とす：

* string concat
* array bounds check
* throwing propagation
* coroutine resume/suspend

つまり backend は “KIR の lowering 結果 + runtime ABI” だけを信じてコード生成する。

---

# Doc J16: Runtime（Swift 実装）C ABI 仕様（`Runtime` + `StdlibCore`）

Kotlin/Native も tracing GC を備えた自動メモリ管理を採用している（参考）。 ([Kotlin][8])
この仕様書でも **non-moving tracing GC（mark-sweep）**を固定採用する。

## J16.1 ランタイムの公開シンボル（`@_cdecl`）

### メモリ

```swift
@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafePointer<KTypeInfo>) -> UnsafeMutableRawPointer

@_cdecl("kk_gc_collect")
public func kk_gc_collect()

@_cdecl("kk_write_barrier")
public func kk_write_barrier(_ owner: UnsafeMutableRawPointer, _ fieldAddr: UnsafeMutablePointer<UnsafeMutableRawPointer?>)
```

### 型情報

```swift
public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?
}
```

### 例外

```swift
@_cdecl("kk_throwable_new")
public func kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer

@_cdecl("kk_panic")
public func kk_panic(_ cstr: UnsafePointer<CChar>) -> Never
```

### 文字列

```swift
@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer
```

### println

```swift
@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?)
```

## J16.2 GC（必須仕様）

* stop-the-world mark-sweep（non-moving）
* root set:

  * globals（singleton/object/companion）
  * thread stacks：**Kotlin フレームマップ**により列挙
  * coroutines：Continuation オブジェクトから辿れる参照も root 扱い
* 各関数は compile 時に “GC root map” を生成し、runtime に登録する（例：`kk_register_frame_map(functionId, mapPtr)`）

## J16.3 オブジェクト header（固定）

```c
struct KKObjHeader {
  KTypeInfo* typeInfo;
  uint32_t flags;
  uint32_t size;
};
```

---

# Doc J17: Coroutines（コンパイラ変換 + Runtime）最終仕様

coroutines の spec 要点：suspend 関数は CPS 変換され、`Continuation<T>` が追加引数、戻りが `Any?` になり “suspend したら特殊値” を返す。 ([Kotlin][3])

## J17.1 Runtime の coroutine コア

### Continuation

```swift
public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get } // CoroutineContext object
    func resumeWith(_ result: UnsafeMutableRawPointer?) // Result<T> object
}
```

### COROUTINE_SUSPENDED

```swift
@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer
```

* これは singleton のアドレスを返す。
* codegen は `ret == kk_coroutine_suspended()` で比較する。

## J17.2 `suspend fun` の lowering（固定アルゴリズム）

### 入力

KIR で `isSuspend = true` の関数。

### 出力（2つ生成）

1. continuation クラス `F$Cont`（spill slots + label + completion）
2. 実体関数 `F$arity(args..., cont, outThrown)`（CPS + state machine）

### 状態機械の生成手順（固定）

1. 関数 body を CFG 化（基本ブロック列）
2. suspension point を列挙
   suspension point = “suspend 関数呼び出し” または “suspend lambda invoke”
3. 各 suspension point に `label` を割り当て（0..N）
4. spill が必要なローカルを解析：

   * そのローカルが “suspension を跨いで live” なら spill
5. `F$Cont` に spill fields を生成
6. 本体を以下のテンプレで出力：

   * `switch (cont.label)`:

     * `case 0:` 初期
     * `case k:` 各再開地点
   * 各 suspension 前：

     * spill 保存
     * `cont.label = next`
     * call suspend callee
     * if returned suspended -> return suspended
     * else result をローカルに入れて継続

## J17.3 non-suspend からの起動（KxMini）

* `runBlocking`, `launch`, `async`, `delay` を Swift runtime 側で提供（GCD）。
* `delay` は `DispatchSourceTimer` で resume。

---

# Doc J18: テストハーネス（“仕様の穴” を埋める最重要装置）

## J18.1 基本方針

* 曖昧な挙動（診断の文言/順序など）は、この仕様書で決め打ちしない。
  代わりに **参照 `kotlinc 2.3.10` と差分テスト**して一致させ、仕様を固める。

## J18.2 テスト種類（最低ライン）

* Lexer golden（token kind + range）
* Parser golden（CST dump の正規化）
* Sema golden（型注釈付き AST dump）
* 実行テスト（stdout/exit code）
* Coroutine テスト（delay/launch/async/例外伝播）

## J18.3 “差分テスト” の固定手順

1. 入力 `.kt` を kotlinc（JVM）で実行し stdout を保存
2. 同じ入力を `kswiftc` で実行し stdout を保存
3. 正規化（改行差、スタックトレース差など）して比較
4. 不一致が出たら：

   * bug としてチケット化
   * どの Phase のどの規約に違反したかを特定

---

# Doc J19: Coverage Gate（SwiftPM）

## J19.1 目的

* `CompilerCore` の優先8ファイルに対して、行カバレッジ 95% 以上を継続的に保証する。

## J19.2 実行コマンド

```bash
bash Scripts/check_coverage.sh
```

## J19.3 判定ルール

* 対象:
  * `Sources/CompilerCore/Lexer/TokenStream.swift`
  * `Sources/CompilerCore/Driver/SourceManager.swift`
  * `Sources/CompilerCore/Sema/ConstraintSolver.swift`
  * `Sources/CompilerCore/Sema/OverloadResolver.swift`
  * `Sources/CompilerCore/Parser/SyntaxArena.swift`
  * `Sources/CompilerCore/Sema/CompilerTypes.swift`
  * `Sources/CompilerCore/Lexer/TokenModel.swift`
  * `Sources/CompilerCore/AST/ASTModels.swift`
* しきい値: 95%（`COVERAGE_THRESHOLD` で上書き可）
* いずれか1ファイルでも未達なら `exit 1`
aa
