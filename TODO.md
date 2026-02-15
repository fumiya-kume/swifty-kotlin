# Kotlin Compiler Remaining Tasks

最終更新: 2026-02-15

## P0 (Core Correctness)

- [x] P0-1: Overload 可能なシンボルテーブルへ変更（同一 FQName の関数共存）
  - [x] `SymbolTable` を `fqName -> [SymbolID]` 対応に変更
  - [x] duplicate 判定を宣言種別ごとに見直し（function/constructor は許可）
  - [x] 型解決側で `lookup` 結果の kind フィルタを適用

- [x] P0-2: expected type 伝播を最小実装
  - [x] `inferExpr` に `expectedType` を通す
  - [x] `resolveCall` 呼び出しへ `expectedType` を渡す
  - [x] 既存型チェックとの整合を確認

- [x] P0-3: OverloadResolver の parameter mapping 拡張
  - [x] named args 対応
  - [x] default args 対応
  - [x] vararg 展開対応（trailing vararg）

## P1 (Language Semantics)

- [x] P1-1: Scope 解決順位の本実装（local/import/default import）
- [x] P1-2: 拡張関数の receiver 解決（現在は unqualified call で除外）
- [x] P1-3: Data-flow / smart cast / sealed・enum・nullable exhaustiveness 拡張
  - [x] enum / nullable when exhaustiveness の拡張
  - [x] sealed exhaustiveness
  - [x] smart cast (stable variable) の本体
    - [x] when の null 分岐ベース最小 smart cast
    - [x] when branch 条件（sealed subtype / Boolean）での smart cast
- [x] P1-4: Sema Pass B 拡張（getter/setter/init/initializer）
  - [x] property initializer の型チェック/推論
  - [x] property getter/setter の本体型チェック
  - [x] class/object init block の本体解析
- [x] P1-5: 呼び出し引数仕様の拡張（named+positional 混在, spread, non-trailing vararg）
  - [x] OverloadResolver の mixed named+positional 対応
  - [x] OverloadResolver の spread 制約対応（non-vararg への spread 拒否）
  - [x] OverloadResolver の non-trailing vararg 対応
  - [x] Frontend/AST で named/spread call args を保持して Resolver に渡す
- [x] P1-6: Kotlin 2.3 stable 機能差分の穴埋め（spec.md J0/J5/J6）
  - [x] nested typealias（class/object 内）を Parser/AST/Sema で扱う
  - [x] `return`/`if`/`try` を expression-body で正しく扱う式パーサを実装
  - [x] `script` ルート（`SyntaxKind.script`）の parse パスを実装

## P2 (Backend / Runtime)

- [x] P2-1: Lowering 各パスの本処理化（現在の marker/rename ベースを置換）
  - [x] generic rename pass を廃止し、専用 pass（For/When/Property/Lambda/Inline/Coroutine）へ置換
  - [x] ForLowering: `__for_expr__` を `iterator` + `kk_for_lowered` 呼び出しへ展開
  - [x] PropertyLowering: `get/set` を accessor kind 引数つき `kk_property_access` に lowering
  - [x] InlineLowering: inline 関数呼び出しを body 展開し、結果参照を alias で再配線
  - [x] DataEnumSealedSynthesis: enum/sealed/data 向け synthetic helper（count/copy）を生成
  - [x] CoroutineLowering: suspend 関数の lowered clone 生成 + hidden continuation 引数付与 + call-site 書き換え
  - [x] ABILowering: 既知 non-throwing runtime call を除外した `outThrown` 設定
  - [x] Coroutine state machine / strict ABI channel（CPS 本体変換・throw 経路）を段階実装
    - [x] external call（symbol 未解決）でも `outThrown` チャネルを使う C backend 生成に拡張
    - [x] lowered suspend 本体で suspend call の `outThrown` 伝播をテスト固定
    - [x] suspend overload（同名）でも `name+arity` で lowered target へ call-site rewrite
- [x] P2-2: ABI 実装（例外チャネル・vtable/itable・レイアウト）
  - [x] synthetic C backend で `outThrown` 引数を内部 call に伝播し、throw 値を呼び出し元へ転送
  - [x] nominal layout（header/field/vtable/itable count, superClass）を Sema で合成し metadata へ出力
  - [x] vtable slot を override 同一 slot で割当（name+arity ベース dispatch key）
  - [x] class layout を継承込みで合成（super fields を instance size へ反映）
  - [x] metadata `superFq` / `fields` / `vtable` / `itable` を import 側で反映
- [x] P2-3: `.kklib` 消費側（-I から manifest/metadata 読込）
- [x] P2-4: LLVM C API backend への移行
  - [x] Codegen backend を抽象化し `-Xir backend=...` で選択可能に変更
  - [x] `backend=llvm-c-api` 選択時の `LLVMCAPIBackend` スキャフォールド（警告つきフォールバック）を追加
  - [x] `backend-strict=true` で未実装時に即 error へ切替（CI 用ガード）
  - [x] LLVM C API dynamic bindings loader（`dlopen` / `dlsym`）を追加
  - [x] LLVM C API bindings（modulemap / SwiftPM link 設定）を追加
  - [x] LLVM C API で最小 IR 生成（const / return / call / branch）
  - [x] LLVM C API で Object 出力パス（target machine 初期化 + emit）
  - [x] 既存 synthetic C backend と emit 出力互換テストを追加
- [x] P2-5: Runtime GC 実装（mark-sweep + root map）
  - [x] stop-the-world mark-sweep collector を実装
  - [x] root set（globals / stack frame map / coroutine）走査を実装
  - [x] `kk_register_frame_map` 系 API と compiler 側 map 出力を実装（現状は 0-root map 生成）
- [x] P2-6: coroutine CPS/state machine lowering 実装
  - [x] lowered suspend 関数へ state enter/exit helper 挿入（state machine 骨格）
  - [x] suspension point ごとの label 設定 + `COROUTINE_SUSPENDED` 早期 return ガード挿入
  - [x] suspension point ベースの state block 分割を追加
  - [x] linear state label dispatch（resume label による再開地点ジャンプ）を追加
  - [x] CFG ベースの suspension point 分割と label dispatch 生成
- [x] P2-7: kotlinc 差分テストハーネスの整備
  - [x] `Scripts/diff_kotlinc.sh` を追加（kotlinc 実行結果との stdout/exit 比較）
- [ ] P2-8: LLVM C API backend の runtime/ABI 追従（spec.md J15）
  - [x] `kk_string_concat` / 例外チャネル / coroutine helper 呼び出しの native lowering を実装
  - [x] `backend=llvm-c-api` で executable までの E2E テストを追加
  - [ ] fallback 依存を段階的に縮小（strict 以外でも native 優先を固定）

## P3 (Spec Compliance Backlog)

- [ ] P3-1: 決定性・エラー規約の固定（spec.md J0）
  - [ ] 出力決定性テスト（同一入力/同一オプションで byte 同一）を追加
  - [ ] compiler/runtime の panic 経路を診断コード方針に沿って整理
- [ ] P3-2: 型システムの仕様追従（spec.md J8/J9）
  - [ ] class/interface 継承関係を `TypeSystem.isSubtype` に反映
  - [ ] declaration-site variance と use-site variance 合成規則を強化
  - [ ] generic constraints の失敗診断精度を改善
- [ ] P3-3: KIR の型付き IR 化強化（spec.md J11/J12）
  - [ ] `if/for/try` など制御構造の KIR 表現を marker 依存から段階的に脱却
  - [ ] KIR value/type 情報の保持を強化し lowering の前提を明確化
- [ ] P3-4: Name mangling/ABI 厳密化（spec.md J13）
  - [ ] signature の型符号化ルール（nullable / function / suspend）を反映
  - [ ] decl kind（getter/setter/constructor）の区別を mangling に反映
- [ ] P3-5: Coroutine フル CPS 仕様追従（spec.md J17）
  - [ ] continuation object（spill slots + label）生成を実装
  - [ ] suspension 跨ぎ live 解析に基づく spill/reload を実装
  - [ ] suspend 例外伝播を含む golden/E2E テストを追加
- [ ] P3-6: テストハーネス拡張（spec.md J18/J19）
  - [ ] Lexer/Parser/Sema の golden test セットを追加
  - [ ] `Scripts/check_coverage.sh` を CI gate に組み込み
  - [ ] `diff_kotlinc.sh` の回帰ケースを継続追加

## In Progress

- [ ] P2-8: LLVM C API backend の runtime/ABI 追従
