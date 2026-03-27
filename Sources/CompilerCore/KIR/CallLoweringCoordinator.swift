import Foundation

/// コールローワーリングの調整を行うコアクラス
/// 各専門ローワーへのディスパッチを担当し、既存CallLowererとの互換性を維持する
final class CallLoweringCoordinator {
    unowned let driver: KIRLoweringDriver
    
    // 専門ローワー群（Phase 2で実装）
    private var memberCallLowerer: MemberCallLowerer?
    private var safeMemberCallLowerer: SafeMemberCallLowerer?
    private var operatorLowerer: OperatorLowerer?
    private var indexedAccessLowerer: IndexedAccessLowerer?
    private var stdlibFunctionLowerer: StdlibFunctionLowerer?
    private var primitiveOperationLowerer: PrimitiveOperationLowerer?
    private var anyTypeLowerer: AnyTypeLowerer?
    private var coroutineLowerer: CoroutineLowerer?
    
    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }
    
    // MARK: - 主要なエントリーポイント
    
    /// 一般的なコール式のローワーリング
    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        var context = CallLoweringContext(
            driver: driver,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        
        // 既存CallLowererに委譲（移行期間中の互換性維持）
        return driver.callLowerer.lowerCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }
    
    /// メンバーコール式のローワーリング
    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // 既存CallLowererに委譲（移行期間中の互換性維持）
        return driver.callLowerer.lowerMemberCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }
    
    /// セーフメンバーコール式のローワーリング
    func lowerSafeMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        // 既存CallLowererに委譲（移行期間中の互換性維持）
        return driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            shared: shared,
            emit: &instructions
        )
    }
    
    // MARK: - 専門ローワーの初期化とアクセス
    
    /// MemberCallLowererを取得（遅延初期化）
    private var _memberCallLowerer: MemberCallLowerer?
    var memberCallLowerer: MemberCallLowerer {
        if _memberCallLowerer == nil {
            _memberCallLowerer = MemberCallLowerer(coordinator: self)
        }
        return _memberCallLowerer!
    }
    
    /// SafeMemberCallLowererを取得（遅延初期化）
    private var _safeMemberCallLowerer: SafeMemberCallLowerer?
    var safeMemberCallLowerer: SafeMemberCallLowerer {
        if _safeMemberCallLowerer == nil {
            _safeMemberCallLowerer = SafeMemberCallLowerer(coordinator: self)
        }
        return _safeMemberCallLowerer!
    }
    
    /// OperatorLowererを取得（遅延初期化）
    private var _operatorLowerer: OperatorLowerer?
    var operatorLowerer: OperatorLowerer {
        if _operatorLowerer == nil {
            _operatorLowerer = OperatorLowerer(coordinator: self)
        }
        return _operatorLowerer!
    }
    
    /// IndexedAccessLowererを取得（遅延初期化）
    private var _indexedAccessLowerer: IndexedAccessLowerer?
    var indexedAccessLowerer: IndexedAccessLowerer {
        if _indexedAccessLowerer == nil {
            _indexedAccessLowerer = IndexedAccessLowerer(coordinator: self)
        }
        return _indexedAccessLowerer!
    }
    
    /// StdlibFunctionLowererを取得（遅延初期化）
    private var _stdlibFunctionLowerer: StdlibFunctionLowerer?
    var stdlibFunctionLowerer: StdlibFunctionLowerer {
        if _stdlibFunctionLowerer == nil {
            _stdlibFunctionLowerer = StdlibFunctionLowerer(coordinator: self)
        }
        return _stdlibFunctionLowerer!
    }
    
    /// PrimitiveOperationLowererを取得（遅延初期化）
    private var _primitiveOperationLowerer: PrimitiveOperationLowerer?
    var primitiveOperationLowerer: PrimitiveOperationLowerer {
        if _primitiveOperationLowerer == nil {
            _primitiveOperationLowerer = PrimitiveOperationLowerer(coordinator: self)
        }
        return _primitiveOperationLowerer!
    }
    
    /// AnyTypeLowererを取得（遅延初期化）
    private var _anyTypeLowerer: AnyTypeLowerer?
    var anyTypeLowerer: AnyTypeLowerer {
        if _anyTypeLowerer == nil {
            _anyTypeLowerer = AnyTypeLowerer(coordinator: self)
        }
        return _anyTypeLowerer!
    }
    
    /// CoroutineLowererを取得（遅延初期化）
    private var _coroutineLowerer: CoroutineLowerer?
    var coroutineLowerer: CoroutineLowerer {
        if _coroutineLowerer == nil {
            _coroutineLowerer = CoroutineLowerer(coordinator: self)
        }
        return _coroutineLowerer!
    }
}

/// コールローワーリングのコンテキストを管理する構造体
struct CallLoweringContext {
    unowned let driver: KIRLoweringDriver
    let ast: ASTModule
    let sema: SemaModule
    let arena: KIRArena
    let interner: StringInterner
    let propertyConstantInitializers: [SymbolID: KIRExprKind]
    
    // インストラクションの可変参照
    private(set) var instructions: [KIRInstruction]
    
    init(
        driver: KIRLoweringDriver,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        self.driver = driver
        self.ast = ast
        self.sema = sema
        self.arena = arena
        self.interner = interner
        self.propertyConstantInitializers = propertyConstantInitializers
        self.instructions = instructions
    }
    
    /// インストラクションを追加
    mutating func append(_ instruction: KIRInstruction) {
        instructions.append(instruction)
    }
    
    /// 複数のインストラクションを追加
    mutating func append(contentsOf newInstructions: [KIRInstruction]) {
        instructions.append(contentsOf: newInstructions)
    }
    
    /// 共有コンテキストを取得
    var sharedContext: KIRLoweringSharedContext {
        return KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
    }
    
    /// エミットコンテキストを取得
    func emitContext() -> KIRLoweringEmitContext {
        return KIRLoweringEmitContext(instructions)
    }
}

/// 共有ヘルパー関数を提供する構造体
struct CallLoweringHelpers {
    
    /// 数値型の強制ランタイムプレフィックスを取得
    static func numericCoercionRuntimePrefix(
        receiverType: TypeID,
        sema: SemaModule
    ) -> String? {
        let nonNull = sema.types.makeNonNullable(receiverType)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        
        if nonNull == intType { return "kk_int" }
        if nonNull == longType { return "kk_long" }
        if nonNull == doubleType { return "kk_double" }
        if nonNull == floatType { return "kk_float" }
        return nil
    }
    
    /// coerceIn(range) のローワーリングを生成
    static func emitCoerceInRange(
        prefix: String,
        receiverType: TypeID,
        loweredReceiverID: KIRExprID,
        loweredRangeArgID: KIRExprID,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let boundType = sema.types.makeNonNullable(receiverType)
        let firstExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        let lastExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_first"),
            arguments: [loweredRangeArgID],
            result: firstExpr,
            canThrow: false,
            thrownResult: nil
        ))
        
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_last"),
            arguments: [loweredRangeArgID],
            result: lastExpr,
            canThrow: false,
            thrownResult: nil
        ))
        
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(prefix + "_coerceIn"),
            arguments: [loweredReceiverID, firstExpr, lastExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }
    
    /// Any型のフォールバックタグを取得
    static func anyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.boolean, _):
            return 2
        case .primitive(.string, _):
            return 3
        case .primitive(.char, _):
            return 4
        case .primitive(.float, _):
            return 5
        case .primitive(.double, _):
            return 6
        default:
            return 1
        }
    }
}
