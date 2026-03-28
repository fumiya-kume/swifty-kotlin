# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-25

## 実装サマリー

### Phase 1 完了済みタスク (高優先度)
- **プリミティブ型**: Boolean拡張関数 ✓
- **配列操作**: 基本操作・高階関数・ソートと順序操作 ✓
- **オブジェクト指向**: インターフェース・シールドクラス・データクラス・オブジェクト宣言・無名オブジェクト ✓
- **関数型プログラミング**: コレクション高階関数・スコープ関数・関数参照・拡張関数・拡張プロパティ・シーケンス高階関数・文字列高階関数・ラムダとクロージャ ✓
- **プロパティデリゲート**: lazyデリゲート・lateinitプロパティ ✓
- **ジェネリクス**: ジェネリッククラス制約 ✓
- **演算子**: invoke演算子・範囲操作・プリミティブ型完全演算子・ビット操作関数 ✓
- **Char拡張関数**: 分類・変換・数値変換・Unicodeプロパティ ✓
- **プリミティブ型変換**: 全ての型間相互変換・unsigned型変換 ✓

### Phase 2 未完了タスク (中優先度)
- 抽象クラス制約
- データクラス継承制約
- コンパニオンオブジェクト
- 継承修飾子とオーバーライド
- 多重継承と衝突解決
- シーケンス高階関数
- 文字列高階関数
- ラムダとクロージャ
- 関数型
- 算術・比較・コンテナ演算子
- UInt/ULong範囲
- 範囲高階関数・進行
- Comparable・Comparator
- observable/vetoableデリゲート
- カスタムデリゲート
- lateinit拡張
- ジェネリック関数・インターフェース・変位指定

## 運用ルール

- `TODO.md` は未完了タスクを主に管理しつつ、直近で完了した大きめの項目は `[x]` で残してよい。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `[x]` または `既存実装済み` のどちらかで明示する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

---

## 未完了バックログ

監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

- [ ] REFL-004: 実行時 `KClass` から読めるバイナリメタデータ（`MetadataSerializer` 等の活用）
  - 現状: 基本的なリフレクションAPIは実装済み（`RuntimeReflection.swift`）

---

### Kotlin Stdlib 互換性（独立タスク）

#### Phase 1: 基本型と配列 (高優先度)


#### Phase 1: オブジェクト指向機能 (高優先度)

- [ ] STDLIB-CLASS-010: 抽象クラス完全実装
  - **仕様**: 抽象クラスの完全なサポートと制約
  - **実装内容**:
    - abstractメンバの定義と強制
    - 抽象クラスのインスタンス化禁止
    - 抽象プロパティと抽象関数
    - 抽象クラスの継承チェーン
  - **現状**: 基本的な抽象クラスは実装済み、制約チェックは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/abstract_class.kt`


- [ ] STDLIB-INHERIT-018: 継承修飾子完全実装
  - **仕様**: open/final/abstract修飾子の完全サポート
  - **実装内容**:
    - openクラスとopenメンバ
    - final修飾子の明示的指定
    - abstract overrideの組み合わせ
    - 継承階層の可視性制御
  - **現状**: 基本的な継承は実装済み、修飾子制約は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/abstract_open_override.kt`

- [ ] STDLIB-INHERIT-019: オーバーライド完全実装
  - **仕様**: メンバオーバーライドの完全サポート
  - **実装内容**:
    - override修飾子の強制
    - オーバーライド時の可視性拡張
    - オーバーライド時の戻り値型共変
    - オーバーライド時の例外型共変
  - **現状**: 基本的なoverrideは実装済み、共変性は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/override_variance.kt`

- [ ] STDLIB-INHERIT-020: 多重継承と衝突解決完全実装
  - **仕様**: インターフェース多重継承の衝突解決
  - **実装内容**:
    - デフォルト実装の衝突検出
    - super<>による明示的呼び出し
    - ダイヤモンド継承問題の解決
    - 最優先実装の選択ルール
  - **現状**: 基本的な多重継承は実装済み、衝突解決は未実装
  - **関連ファイル**: `DiamondOverride.swift`
  - **テストケース**: `Scripts/diff_cases/interface_conflict_resolution.kt`

#### Phase 2: 演算子と特殊構文 (中優先度)

- [ ] STDLIB-OP-030: 算術演算子オーバーロード完全実装
  - **仕様**: カスタムクラスでの算術演算子オーバーロード
  - **実装内容**:
    - 単項演算子: unaryPlus(), unaryMinus(), not()
    - 二項演算子: plus(), minus(), times(), div(), mod(), rem()
    - 代入演算子: plusAssign(), minusAssign(), timesAssign(), divAssign(), modAssign()
    - 演算子の優先順位と結合性
    - 演算子オーバーロードの型チェック
  - **現状**: 基本的な演算子は実装済み、カスタムオーバーロードは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/operator_overload.kt`

- [ ] STDLIB-OP-031: 比較演算子オーバーロード完全実装
  - **仕様**: カスタムクラスでの比較演算子オーバーロード
  - **実装内容**:
    - 等値演算子: equals(), hashCode()
    - 順序演算子: compareTo(), lessThan(), greaterThan(), lessThanOrEqual(), greaterThanOrEqual()
    - 構造的比較: contentEquals(), contentHashCode()
    - 比較演算子の連鎖
    - null安全な比較
  - **現状**: compareToは実装済み、詳細な比較ロジックは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticComparisonStubs.swift`
  - **テストケース**: `Scripts/diff_cases/compare_values.kt`

- [ ] STDLIB-OP-032: コンテナ演算子オーバーロード完全実装
  - **仕様**: コンテナクラスでの演算子オーバーロード
  - **実装内容**:
    - インデックス演算子: get(), set()
    - 含有演算子: contains(), iterator()
    - 範囲演算子: rangeTo()
    - in演算子: contains()の省略形
    - スプレッド演算子: spread()
  - **現状**: 基本的なコンテナ演算子は実装済み、カスタム実装は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/container_operators.kt`


- [ ] STDLIB-RANGE-034: IntRange完全実装
  - **仕様**: IntRangeの完全な機能サポート
  - **実装内容**:
    - コンストラクタ: IntRange(start, end), start..end
    - プロパティ: start, end, first, last, step
    - 包含判定: contains(), isEmpty()
    - 反復: iterator(), reversed()
    - 変換: toList(), toIntArray()
  - **現状**: 基本的なIntRangeは実装済み、高度な機能は未実装
  - **関連ファイル**: `RuntimeRangeAndDispatch.swift`
  - **テストケース**: `Scripts/diff_cases/range_basic.kt`

- [ ] STDLIB-RANGE-035: LongRange完全実装
  - **仕様**: LongRangeの完全な機能サポート
  - **実装内容**:
    - コンストラクタ: LongRange(start, end), startL..endL
    - プロパティ: start, end, first, last, step
    - 包含判定: contains(), isEmpty()
    - 反復: iterator(), reversed()
    - 変換: toList(), toLongArray()
  - **現状**: 基本的なLongRangeは実装済み、IntRangeとの相互運用は未実装
  - **関連ファイル**: `RuntimeRangeAndDispatch.swift`
  - **テストケース**: `Scripts/diff_cases/long_range.kt`

- [ ] STDLIB-RANGE-036: UIntRange完全実装
  - **仕様**: UIntRangeの完全な機能サポート
  - **実装内容**:
    - コンストラクタ: UIntRange(start, end), startU..endU
    - プロパティ: start, end, first, last, step
    - 包含判定: contains(), isEmpty()
    - 反復: iterator(), reversed()
    - 変換: toList(), toUIntArray()
  - **現状**: UIntRangeは未実装
  - **関連ファイル**: `RuntimeRangeAndDispatch.swift`
  - **テストケース**: `Scripts/diff_cases/uint_range.kt`


#### Phase 2: プロパティデリゲート (中優先度)


- [ ] STDLIB-DELEG-047: provideDelegate完全実装
  - **仕様**: provideDelegate演算子の完全サポート
  - **実装内容**:
    - provideDelegate()メソッド: デリゲートインスタンスの提供
    - デリゲートの最適化: 状態共有
    - provideDelegateの型推論
    - 複数プロパティでのデリゲート共有
    - provideDelegateと他のデリゲート演算子
  - **現状**: provideDelegateは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticDelegateStubs.swift`
  - **テストケース**: `Scripts/diff_cases/delegate_provide.kt`

- [ ] STDLIB-DELEG-048: デリゲート演算子完全実装
  - **仕様**: 全てのデリゲート演算子の完全サポート
  - **実装内容**:
    - getValue(): 値取得演算子
    - setValue(): 値設定演算子
    - provideDelegate(): デリゲート提供演算子
    - 演算子の優先順位
    - 演算子のオーバーロード解決
    - デリゲート演算子の型チェック
  - **現状**: 基本的なデリゲート演算子は実装済み、provideDelegateは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticDelegateStubs.swift`
  - **テストケース**: `Scripts/diff_cases/delegate_operators.kt`


#### Phase 2: ジェネリクスと型システム (中優先度)


- [ ] STDLIB-GEN-053: ジェネリックインターフェース完全実装
  - **仕様**: ジェネリックインターフェースの完全サポート
  - **実装内容**:
    - 型パラメータ: interface MyInterface<T>
    - 複数型パラメータ: interface MyInterface<T, U>
    - 型制約: interface MyInterface<T : Comparable<T>>
    - ジェネリックメソッド: interface MyInterface<T> { fun process(value: T) }
    - ジェネリックプロパティ: interface MyInterface<T> { val value: T }
  - **現状**: 基本的なジェネリックインターフェースは実装済み、制約は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/generic_interfaces.kt`

- [ ] STDLIB-GEN-054: 変位指定完全実装
  - **仕様**: 型パラメータの変位指定（共変性と反変性）
  - **実装内容**:
    - 共変性（out）: interface Producer<out T>
    - 反変性（in）: interface Consumer<in T>
    - 不変性: interface Container<T>
    - 変位指定の型チェック
    - 変位指定と継承の関係
  - **現状**: 基本的な変位指定は実装済み、詳細なチェックは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/variance_generics.kt`

- [ ] STDLIB-GEN-055: 型制約完全実装
  - **仕様**: 型パラメータの制約
  - **実装内容**:
    - 上限制約: <T : Comparable<T>>
    - 複数制約: <T : Comparable<T>, Serializable>
    - where句: fun <T> process(value: T) where T : Comparable<T>
    - 制約の解決とチェック
    - 制約違反のエラーメッセージ
  - **現状**: 基本的な制約は実装済み、where句は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/type_constraints.kt`

- [ ] STDLIB-GEN-056: スープロジェクション完全実装
  - **仕様**: スープロジェクション（*）の完全サポート
  - **実装内容**:
    - スープロジェクション: List<*>
    - 読み取り専用アクセス: get()のみ許可
    - 型安全なキャスト: as?演算子
    - スープロジェクションとジェネリック関数
    - スープロジェクションの型消去
  - **現状**: 基本的なスープロジェクションは実装済み、詳細は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/star_projection.kt`

- [ ] STDLIB-GEN-057: reified型パラメータ完全実装
  - **仕様**: reified型パラメータの完全サポート
  - **実装内容**:
    - reified修飾子: inline fun <reified T> myFunction()
    - 実行時型チェック: value is T
    - 実行時型キャスト: value as T
    - reifiedとジェネリック制約の組み合わせ
    - reifiedとinline関数の制約
  - **現状**: reifiedは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/reified_generics.kt`

- [ ] STDLIB-GEN-058: ジェネリック型消去完全実装
  - **仕様**: ジェネリック型の実行時型消去
  - **実装内容**:
    - 型消去のルール: List<String> -> List
    - 配列での型保持: Array<String>
    - 型消去とキャストの安全性
    - ジェネリック型のinstanceofチェック
    - 型消去とリフレクションの関係
  - **現状**: 基本的な型消去は実装済み、詳細なルールは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/type_erasure.kt`

- [ ] STDLIB-GEN-059: ジェネリック型推論完全実装
  - **仕様**: ジェネリック型の自動推論
  - **実装内容**:
    - 関数呼び出しでの型推論: myFunction("hello")
    - 変数宣言での型推論: val list = listOf(1, 2, 3)
    - 複雑な型推論: mapOf("key" to "value")
    - 型推論の失敗時のエラー
    - 明示的型指定との組み合わせ
  - **現状**: 基本的な型推論は実装済み、複雑なケースは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/type_inference.kt`

#### Phase 2: リフレクション (中優先度)

- [ ] STDLIB-REFLECT-060: KClass基本機能完全実装
  - **仕様**: KClassの基本的なリフレクション機能
  - **実装内容**:
    - クラス名: simpleName, qualifiedName
    - クラス階層: supertypes, isInstance
    - 型パラメータ: typeParameters, generics
    - 可視性: visibility, isAbstract, isFinal
    - コンストラクタ: constructors
  - **現状**: 基本的なKClassは実装済み (REFL-004参照)、詳細は未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/kclass_basic.kt`

- [ ] STDLIB-REFLECT-061: KClassメンバアクセス完全実装
  - **仕様**: KClassからのメンバアクセス機能
  - **実装内容**:
    - プロパティ: properties, memberProperties
    - 関数: functions, memberFunctions
    - 拡張プロパティ: declaredMemberProperties
    - 拡張関数: declaredMemberFunctions
    - メンバのフィルタリングと検索
  - **現状**: 基本的なリフレクションは実装済み、メンバアクセスは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/kclass_members.kt`

- [ ] STDLIB-REFLECT-062: KProperty完全実装
  - **仕様**: KPropertyインターフェースの完全サポート
  - **実装内容**:
    - プロパティ名: name
    - プロパティ型: returnType
    - 可視性: visibility, isLateinit, isConst
    - ゲッター/セッター: getter, setter
    - プロパティ値の取得/設定: get(), set()
  - **現状**: 基本的なKPropertyは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/kproperty_basic.kt`

- [ ] STDLIB-REFLECT-063: KFunction完全実装
  - **仕様**: KFunctionインターフェースの完全サポート
  - **実装内容**:
    - 関数名: name
    - 関数型: type
    - パラメータ: parameters, valueParameters
    - 戻り値型: returnType
    - 関数の呼び出し: call()
    - suspend関数: isSuspend
  - **現状**: 基本的なKFunctionは実装済み、呼び出しは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/kfunction_basic.kt`

- [ ] STDLIB-REFLECT-064: KConstructor完全実装
  - **仕様**: KConstructorインターフェースの完全サポート
  - **実装内容**:
    - コンストラクタパラメータ: parameters, valueParameters
    - 可視性: visibility
    - インスタンス生成: call()
    - プライマリコンストラクタ: isPrimary
    - セカンダリコンストラクタ
  - **現状**: 基本的なKConstructorは実装済み、呼び出しは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/kconstructor_basic.kt`

- [ ] STDLIB-REFLECT-065: アノテーションリフレクション完全実装
  - **仕様**: アノテーションのリフレクションアクセス
  - **実装内容**:
    - アノテーション取得: annotations
    - 特定アノテーション検索: findAnnotation()
    - アノテーションプロパティ: annotationClass
    - アノテーション値の取得
    - 実行時アノテーション: @Retention(RUNTIME)
  - **現状**: 基本的なアノテーションは実装済み、リフレクションは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_reflection.kt`

- [ ] STDLIB-REFLECT-066: 型リフレクション完全実装
  - **仕様**: 型情報のリフレクションアクセス
  - **実装内容**:
    - KType: 型情報の表現
    - 型引数: arguments
    - 分類: classifier
    - null可能性: isMarkedNullable
    - ジェネリック型の分解
    - 配列型の要素型取得
  - **現状**: 基本的な型チェックは実装済み、リフレクションは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/type_reflection.kt`

- [ ] STDLIB-REFLECT-067: リフレクション動的呼び出し完全実装
  - **仕様**: リフレクションによる動的メンバ呼び出し
  - **実装内容**:
    - 関数呼び出し: KFunction.call()
    - プロパティアクセス: KProperty.get(), KProperty.set()
    - コンストラクタ呼び出し: KConstructor.call()
    - 可変長引数の処理
    - 例外処理とエラーハンドリング
  - **現状**: 基本的なリフレクションは実装済み、動的呼び出しは未実装
  - **関連ファイル**: `RuntimeReflection.swift`
  - **テストケース**: `Scripts/diff_cases/reflection_dynamic_call.kt`

#### Phase 3: コルーチンと並行処理 (低優先度)

- [ ] STDLIB-CORO-068: suspend関数基本実装
  - **仕様**: suspend関数の基本的なサポート
  - **実装内容**:
    - suspend修飾子: suspend fun myFunction()
    - コルーチンコンテキスト: CoroutineContext
    - 継続渡し: Continuation<T>
    - suspendラムダ: suspend { value -> }
    - suspendプロパティ: suspend val property
  - **現状**: async/awaitは一部実装済み、suspend関数は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/suspend_functions.kt`

- [ ] STDLIB-CORO-069: CoroutineScope完全実装
  - **仕様**: CoroutineScopeの完全サポート
  - **実装内容**:
    - スコープの階層: CoroutineScopeの親子関係
    - キャンセル伝播: 親スコープのキャンセル
    - ジョブ管理: scope.coroutineContext[Job]
    - 構造化並行性: structured concurrency
    - スコープのライフサイクル管理
  - **現状**: 基本的なスコープは実装済み、階層管理は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/coroutine_scope.kt`

- [ ] STDLIB-CORO-070: Job完全実装
  - **仕様**: Jobインターフェースの完全サポート
  - **実装内容**:
    - ジョブの状態: New, Active, Completing, Completed, Cancelling, Cancelled, Failed
    - キャンセル: cancel(), cancel(CauseException)
    - ジョブの階層: parent-child関係
    - ジョブの完了: complete(), completeExceptionally()
    - ジョブの待機: join(), awaitCompletion()
  - **現状**: 基本的なJobは実装済み、状態管理は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/job_basic.kt`

- [ ] STDLIB-CORO-071: async/await完全実装
  - **仕様**: async/awaitの完全サポート
  - **実装内容**:
    - asyncビルダー: async { return value }
    - await式: val result = asyncFunction()
    - asyncの例外処理: try-catch in async
    - awaitのキャンセル: awaitのキャンセル対応
    - asyncのディスパッチャ指定: async(Dispatchers.Default)
  - **現状**: async/awaitは一部実装済み、例外処理は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/async_await.kt`

- [ ] STDLIB-CORO-072: launch完全実装
  - **仕様**: launchビルダーの完全サポート
  - **実装内容**:
    - launchビルダー: launch { /* code */ }
    - fire-and-forget: 戻り値なしの実行
    - launchの例外処理: CoroutineExceptionHandler
    - launchのディスパッチャ指定: launch(Dispatchers.IO)
    - launchのキャンセル: Jobによるキャンセル
  - **現状**: 基本的なlaunchは実装済み、例外処理は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/launch_basic.kt`

- [ ] STDLIB-CORO-073: Flow基本実装
  - **仕様**: Flowの基本的な機能
  - **実装内容**:
    - flowビルダー: flow { emit(value) }
    - コレクター: collect { value -> }
    - 中間操作: map, filter, transform
    - 端末操作: collect, toList, first, single
    - Flowの遅延評価: コールドストリーム
  - **現状**: 基本的なflowは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_basic.kt`

- [ ] STDLIB-CORO-074: Flow操作完全実装
  - **仕様**: Flowの高度な操作
  - **実装内容**:
    - 変換操作: map, mapNotNull, transform
    - フィルタリング: filter, filterNot, take, drop
    - 集約操作: reduce, fold, scan
    - 結合操作: zip, combine, flatMapConcat
    - バッファリング: buffer, conflate, flowOn
  - **現状**: 基本的なFlowは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_operations.kt`

- [ ] STDLIB-CORO-075: Channel基本実装
  - **仕様**: Channelの基本的な機能
  - **実装内容**:
    - チャネル作成: Channel<T>(), produce {}
    - 送受信: send(), receive()
    - クローズ: close(), isClosedForSend, isClosedForReceive
    - イテレーション: for (value in channel)
    - バッファリング: バッファサイズ指定
  - **現状**: 基本的なchannelは実装済み、バッファリングは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/channel_basic.kt`

- [ ] STDLIB-CORO-076: Channel高度機能完全実装
  - **仕様**: Channelの高度な機能
  - **実装内容**:
    - バックプレッシャー: suspend on full/empty
    - ファンアウト: 複数受信者
    - ファンイン: 複数送信者
    - ブロードキャスト: BroadcastChannel
    - パイプライン: channelパイプライン処理
  - **現状**: 基本的なchannelは実装済み、バックプレッシャー制御は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/channel_backpressure.kt`

- [ ] STDLIB-CORO-077: withContext完全実装
  - **仕様**: withContextの完全サポート
  - **実装内容**:
    - コンテキスト切り替え: withContext(Dispatchers.IO)
    - スレッドプール: 各ディスパッチャのスレッド管理
    - コンテキスト要素: Job, CoroutineName, CoroutineExceptionHandler
    - コンテキストの合成: +演算子
    - コンテキストのキャンセル伝播
  - **現状**: withContextは一部実装済み、ディスパッチャは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/with_context.kt`

- [ ] STDLIB-CORO-079: Mutex完全実装
  - **仕様**: Mutexの完全サポート
  - **実装内容**:
    - ロック取得: withLock { /* critical section */ }
    - tryLock: 非ブロックロック取得
    - ロック解放: unlock(), withLockの自動解放
    - フェアネス: ロック取得の公平性
    - 再入可能: reentrant mutexのサポート
  - **現状**: synchronizedは一部実装済み (STDLIB-325)、Mutexは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/mutex_basic.kt`

- [ ] STDLIB-CORO-080: Atomic操作完全実装
  - **仕様**: アトミック操作の完全サポート
  - **実装内容**:
    - AtomicInt: 整数のアトミック操作
    - AtomicBoolean: 真偽値のアトミック操作
    - AtomicReference: 参照のアトミック操作
    - compareAndSet: CAS操作
    - getAndUpdate, updateAndGet: アトミック更新
  - **現状**: atomic操作は一部実装済み、完全な実装は未完了
  - **関連ファイル**: `RuntimeAtomic.swift`
  - **テストケース**: `Scripts/diff_cases/atomic_basic.kt`

#### Phase 3: 時間と期間 (低優先度)

- [ ] STDLIB-TIME-081: Duration基本実装
  - **仕様**: Durationの基本的な機能
  - **実装内容**:
    - Duration作成: 1.seconds, 1.minutes, 1.hours
    - Duration演算: +, -, *, / 演算子
    - Duration比較: ==, <, >, <=, >=
    - Durationプロパティ: inWholeSeconds, inWholeMinutes
    - Durationフォーマット: toString()
  - **現状**: 基本的なDurationは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimeDuration.swift`
  - **テストケース**: `Scripts/diff_cases/duration_basic.kt`

- [ ] STDLIB-TIME-082: Duration高度操作完全実装
  - **仕様**: Durationの高度な操作
  - **実装内容**:
    - 時間単位変換: toInt(Duration), toLong(Duration)
    - 絶対値: absoluteValue, abs()
    - 符号: isNegative, isInfinite
    - 範囲チェック: inSeconds, inNanoseconds
    - Durationの数学演算: plus(), minus(), times(), dividedBy()
  - **現状**: 基本的なDurationは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimeDuration.swift`
  - **テストケース**: `Scripts/diff_cases/duration_operations.kt`

- [ ] STDLIB-TIME-083: Instant完全実装
  - **仕様**: Instantの完全サポート
  - **実装内容**:
    - Instant作成: Instant.now(), Instant.fromEpochMilliseconds()
    - Instant演算: +, - Durationとの演算
    - Instant比較: ==, <, >, <=, >=
    - Instantプロパティ: epochSeconds, nanoOfSecond
    - Instant間の期間: until(), elapsed()
  - **現状**: Instantは未実装
  - **関連ファイル**: `RuntimeDuration.swift`
  - **テストケース**: `Scripts/diff_cases/instant_basic.kt`

- [ ] STDLIB-TIME-084: 時間測定完全実装
  - **仕様**: 時間測定関数の完全サポート
  - **実装内容**:
    - measureTime: 実行時間測定
    - measureTimedValue: 値と実行時間の測定
    - TimeSource: 時間ソースの抽象化
    - Monotonic: 単調増加時間ソース
    - TimeMark: 時間マークと差分計算
  - **現状**: measureTime等は一部実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeDuration.swift`
  - **テストケース**: `Scripts/diff_cases/measure_time.kt`

- [ ] STDLIB-TIME-085: システム時刻完全実装
  - **仕様**: システム時刻アクセスの完全サポート
  - **実装内容**:
    - currentTimeMillis: ミリ秒単位の現在時刻
    - nanoTime: ナノ秒単位の相対時刻
    - processStartNanos: プロセス開始時刻
    - 時刻の精度と分解能
    - 時刻のモノトニック性保証
  - **現状**: currentTimeMillis等は一部実装済み (STDLIB-131/132)、完全な実装は未完了
  - **関連ファイル**: `RuntimeSystem.swift`
  - **テストケース**: `Scripts/diff_cases/system_current_time_millis.kt`

- [ ] STDLIB-TIME-086: Clock完全実装
  - **仕様**: Clockインターフェースの完全サポート
  - **実装内容**:
    - Clock.now(): 現在時刻の取得
    - Clockの実装: SystemClock, TestClock
    - Clockの抽象化: 時間ソースの統一インターフェース
    - Clockの調整: テスト用の時間操作
    - Clockのスレッドセーフティ
  - **現状**: Clockは未実装
  - **関連ファイル**: `RuntimeDuration.swift`
  - **テストケース**: `Scripts/diff_cases/clock_basic.kt`

#### Phase 3: I/Oとファイルシステム (低優先度)

- [ ] STDLIB-IO-087: File基本実装
  - **仕様**: Fileクラスの基本的なファイル操作
  - **実装内容**:
    - ファイル作成: File(path), File(parent, child)
    - ファイル操作: createNewFile(), delete(), exists()
    - ファイル情報: length(), lastModified(), isFile, isDirectory
    - ファイルパス: absolutePath, canonicalPath, parent
    - ファイル属性: canRead(), canWrite(), canExecute()
  - **現状**: 基本的なファイル操作は一部実装済み (STDLIB-320)、詳細は未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/file_basic.kt`

- [ ] STDLIB-IO-088: File読み書き完全実装
  - **仕様**: ファイルの読み書き操作
  - **実装内容**:
    - テキスト読み込み: readText(), readLines()
    - テキスト書き込み: writeText(), appendText()
    - バイナリ読み込み: readBytes()
    - バイナリ書き込み: writeBytes()
    - バッファリング: bufferedReader(), bufferedWriter()
  - **現状**: 基本的な読み書きは実装済み、バイナリ操作は未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/file_read_write.kt`

- [ ] STDLIB-IO-089: Path完全実装
  - **仕様**: Pathクラスの完全サポート
  - **実装内容**:
    - パス作成: Path.get(), Paths.get()
    - パス操作: resolve(), relativize(), normalize()
    - パス情報: fileName, parent, root, nameCount
    - パス比較: equals(), startsWith(), endsWith()
    - パス変換: toFile(), toUri(), toString()
  - **現状**: 基本的なPathは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimePath.swift`
  - **テストケース**: `Scripts/diff_cases/path_basic.kt`

- [ ] STDLIB-IO-090: Filesユーティリティ完全実装
  - **仕様**: Filesクラスのユーティリティメソッド
  - **実装内容**:
    - ファイル操作: createFile(), delete(), copy(), move()
    - ディレクトリ操作: createDirectory(), createDirectories()
    - ファイル属性: size(), lastModifiedTime(), isRegularFile()
    - ファイル検索: walk(), list(), newDirectoryStream()
    - 一時ファイル: createTempFile(), createTempDirectory()
  - **現状**: 基本的なFilesは実装済み、検索は未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/files_utility.kt`

- [ ] STDLIB-IO-091: BufferedReader/Writer完全実装
  - **仕様**: バッファ付きリーダー/ライターの完全サポート
  - **実装内容**:
    - BufferedReader: readLine(), read(), ready(), close()
    - BufferedWriter: write(), newLine(), flush(), close()
    - バッファサイズ指定: BufferedReader(reader, bufferSize)
    - 行末処理: CRLF, LF, CR対応
    - エンコーディング: Charset指定
  - **現状**: 基本的なReader/Writerは実装済み、バッファリングは未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/buffered_io.kt`

- [ ] STDLIB-IO-092: InputStream/OutputStream完全実装
  - **仕様**: ストリーム入出力の完全サポート
  - **実装内容**:
    - InputStream: read(), available(), close(), skip()
    - OutputStream: write(), flush(), close()
    - バイト配列操作: read(byteArray), write(byteArray)
    - マークとリセット: mark(), reset()
    - ストリームのチェーン: SequenceInputStream
  - **現状**: 基本的なストリームは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/stream_basic.kt`

- [ ] STDLIB-IO-093: リソースアクセス完全実装
  - **仕様**: リソースファイルへのアクセス
  - **実装内容**:
    - クラスパスリソース: ClassLoader.getResource()
    - リソースストリーム: getResourceAsStream()
    - リソースURL: getResource()
    - リソース読み込み: readResourceAsText()
    - リソース存在確認: resourceExists()
  - **現状**: リソースアクセスは未実装
  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/resource_access.kt`

#### Phase 3: 正規表現 (低優先度)

- [ ] STDLIB-REGEX-094: Regex基本実装
  - **仕様**: Regexクラスの基本的な機能
  - **実装内容**:
    - 正規表現作成: Regex(pattern), Regex.fromLiteral()
    - パターンマッチ: matches(), containsMatchIn()
    - マッチ検索: find(), findAll()
    - 文字列置換: replace(), replaceFirst()
    - 文字列分割: split()
  - **現状**: 基本的なRegexは実装済み (STDLIB-100/101/103)、高度な機能は未実装
  - **関連ファイル**: `RuntimeRegex.swift`
  - **テストケース**: `Scripts/diff_cases/regex_basic.kt`

- [ ] STDLIB-REGEX-095: MatchResult完全実装
  - **仕様**: MatchResultの完全サポート
  - **実装内容**:
    - マッチ情報: value, range, groups
    - グループアクセス: groupValues, groupValues[], get()
    - デストラクチャリング: component1(), component2()
    - マッチ反復: next(), hasPrevious()
    - マッチ変換: map(), transform()
  - **現状**: 基本的なMatchResultは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeRegex.swift`
  - **テストケース**: `Scripts/diff_cases/match_result.kt`

- [ ] STDLIB-REGEX-096: 正規表現オプション完全実装
  - **仕様**: 正規表現オプションの完全サポート
  - **実装内容**:
    - IGNORE_CASE: 大文字小文字無視
    - MULTILINE: 複数行モード
    - DOT_MATCHES_ALL: ドットが全文字にマッチ
    - UNIX_LINES: Unix行終端子
    - LITERAL: リテラルモード
    - COMMENTS: コメント許可
  - **現状**: 基本的なオプションは実装済み、全オプションは未実装
  - **関連ファイル**: `RuntimeRegex.swift`
  - **テストケース**: `Scripts/diff_cases/regex_options.kt`

- [ ] STDLIB-REGEX-097: 名前付きグループ完全実装
  - **仕様**: 名前付きキャプチャグループの完全サポート
  - **実装内容**:
    - 名前付きグループ: (?<name>pattern)
    - グループ名取得: groupNames
    - 名前付きアクセス: groups["name"]
    - 入れ子グループ: 入れ子名前付きグループ
    - グループのデストラクチャリング
  - **現状**: 基本的なグループは実装済み、名前付きは未実装
  - **関連ファイル**: `RuntimeRegex.swift`
  - **テストケース**: `Scripts/diff_cases/regex_named_groups.kt`

- [ ] STDLIB-REGEX-098: アンカーと境界完全実装
  - **仕様**: 正規表現アンカーと境界の完全サポート
  - **実装内容**:
    - 行アンカー: ^, $
    - 単語境界: \b, \B
    - 文字境界: \G
    - 入力境界: \A, \z, \Z
    - 前瞻/後瞻: (?=...), (?!...), (?<=...), (?<!...)
  - **現状**: 基本的なアンカーは実装済み、境界は未実装
  - **関連ファイル**: `RuntimeRegex.swift`
  - **テストケース**: `Scripts/diff_cases/regex_anchors.kt`

#### Phase 3: 乱数とUUID (低優先度)

- [ ] STDLIB-RANDOM-099: Random基本実装
  - **仕様**: Randomクラスの基本的な乱数生成
  - **実装内容**:
    - 整数乱数: nextInt(), nextInt(bound)
    - 長整数乱数: nextLong(), nextLong(bound)
    - 浮動小数点乱数: nextDouble(), nextFloat()
    - 真偽値乱数: nextBoolean()
    - バイト列乱数: nextBytes()
  - **現状**: 基本的なRandomは実装済み、境界付きは未実装
  - **関連ファイル**: `RuntimeRandom.swift`
  - **テストケース**: `Scripts/diff_cases/random_basic.kt`

- [ ] STDLIB-RANDOM-100: Random高度機能完全実装
  - **仕様**: Randomクラスの高度な機能
  - **実装内容**:
    - シード指定: Random(seed)
    - ガウス分布: nextGaussian()
    - 指数分布: nextExponential()
    - 一様分布: nextUniform()
    - 乱数列: ints(), longs(), doubles()
    - ストリームAPI: random().ints()
  - **現状**: 基本的なRandomは実装済み、高度な分布は未実装
  - **関連ファイル**: `RuntimeRandom.swift`
  - **テストケース**: `Scripts/diff_cases/random_extended.kt`

- [ ] STDLIB-RANDOM-101: SecureRandom完全実装
  - **仕様**: 暗号学的乱数生成器の完全サポート
  - **実装内容**:
    - SecureRandomインスタンス: SecureRandom.getInstance()
    - 強力な乱数: generateSeed(), nextBytes()
    - アルゴリズム指定: SecureRandom.getInstance("SHA1PRNG")
    - シード設定: setSeed()
    - スレッドセーフティ: マルチスレッド対応
  - **現状**: 暗号学的乱数は未実装
  - **関連ファイル**: `RuntimeRandom.swift`
  - **テストケース**: `Scripts/diff_cases/secure_random.kt`

- [ ] STDLIB-UUID-102: UUID基本実装
  - **仕様**: UUIDクラスの基本的な機能
  - **実装内容**:
    - UUID生成: randomUUID(), nameUUIDFromBytes()
    - UUID解析: fromString()
    - UUID表現: toString(), mostSignificantBits, leastSignificantBits
    - UUID比較: equals(), compareTo()
    - UUIDバージョン: version(), variant()
  - **現状**: 基本的なUUIDは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeUuid.swift`
  - **テストケース**: `Scripts/diff_cases/uuid_basic.kt`

- [ ] STDLIB-UUID-103: UUID高度機能完全実装
  - **仕様**: UUIDクラスの高度な機能
  - **実装内容**:
    - UUIDバリアント: RFC 4122, DCE, Microsoft, NCS
    - UUIDバージョン: time-based, DCE, name-based, random
    - UUID文字列表現: 標準フォーマットと短縮フォーマット
    - UUID名前空間: DNS, URL, OID, X.500
    - UUID検証: 有効性チェックと形式検証
  - **現状**: 基本的なUUIDは実装済み、バリアントは未実装
  - **関連ファイル**: `RuntimeUuid.swift`
  - **テストケース**: `Scripts/diff_cases/uuid_advanced.kt`

#### Phase 3: エラー処理 (低優先度)

- [ ] STDLIB-EXCEPT-104: 例外基本実装
  - **仕様**: 例外処理の基本的な機能
  - **実装内容**:
    - try-catch: try { /* code */ } catch (e: Exception) { /* handle */ }
    - try-catch-finally: try-catch-finallyブロック
    - 例外階層: Throwable, Exception, RuntimeException
    - 例外メッセージ: message, cause
    - 例外スタックトレース: stackTrace
  - **現状**: 基本的なtry-catchは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeThrowableBox`
  - **テストケース**: `Scripts/diff_cases/exception_basic.kt`

- [ ] STDLIB-EXCEPT-105: 例外高度機能完全実装
  - **仕様**: 例外処理の高度な機能
  - **実装内容**:
    - 例外再スロー: throw, rethrow
    - 例外チェーン: initCause(), getCause()
    - 例外抑制: addSuppressed(), getSuppressed()
    - try-with-resources: use()関数
    - 例外フィルタリング: catchの条件付き
  - **現状**: 基本的な例外は実装済み、抑制は未実装
  - **関連ファイル**: `RuntimeThrowableBox`
  - **テストケース**: `Scripts/diff_cases/exception_advanced.kt`

- [ ] STDLIB-RESULT-106: Result基本実装
  - **仕様**: Result<T>クラスの基本的な機能
  - **実装内容**:
    - Result作成: Result.success(value), Result.failure(exception)
    - 状態チェック: isSuccess, isFailure
    - 値取得: getOrThrow(), getOrElse()
    - マッピング: map(), mapCatching()
    - フラットマッピング: flatMap(), flatMapCatching()
  - **現状**: 基本的なResultは実装済み (STDLIB-280/281/282/283)、詳細は未実装
  - **関連ファイル**: `RuntimeResult.swift`
  - **テストケース**: `Scripts/diff_cases/result_basic.kt`

- [ ] STDLIB-RESULT-107: Result高度機能完全実装
  - **仕様**: Result<T>クラスの高度な機能
  - **実装内容**:
    - 例外処理: getOrElse(), recover(), recoverCatching()
    - 副作用: onSuccess(), onFailure()
    - 結合: zip(), combine()
    - 反復: asSequence(), iterator()
    - デストラクチャリング: component1(), component2()
  - **現状**: 基本的なResultは実装済み、高度な機能は未実装
  - **関連ファイル**: `RuntimeResult.swift`
  - **テストケース**: `Scripts/diff_cases/result_advanced.kt`

- [ ] STDLIB-RUNCATCH-108: runCatching完全実装
  - **仕様**: runCatching関数の完全サポート
  - **実装内容**:
    - 基本runCatching: runCatching { /* code */ }
    - 例外マッピング: runCatching { /* code */ }.mapCatching()
    - 例外回復: runCatching { /* code */ }.recoverCatching()
    - 副作用: runCatching { /* code */ }.onFailure { /* handle */ }
    - 入れ子runCatching: 入れ子例外処理
  - **現状**: 基本的なrunCatchingは実装済み、高度な機能は未実装
  - **関連ファイル**: `RuntimeResult.swift`
  - **テストケース**: `Scripts/diff_cases/runcatching_advanced.kt`

#### Phase 3: 数学関数 (低優先度)

- [ ] STDLIB-MATH-109: 基本数学関数完全実装
  - **仕様**: 基本数学関数の完全サポート
  - **実装内容**:
    - 三角関数: sin(), cos(), tan(), asin(), acos(), atan()
    - 双曲線関数: sinh(), cosh(), tanh()
    - 指数対数: exp(), log(), log10(), log2()
    - 累乗根: pow(), sqrt(), cbrt()
    - 絶対値と符号: abs(), sign()
  - **現状**: 基本的な数学関数は実装済み、三角関数は未実装
  - **関連ファイル**: `RuntimeMath.swift`
  - **テストケース**: `Scripts/diff_cases/math_basic.kt`

- [ ] STDLIB-MATH-110: 高度数学関数完全実装
  - **仕様**: 高度な数学関数の完全サポート
  - **実装内容**:
    - 逆三角関数: atan2(), hypot()
    - 丸め関数: round(), ceil(), floor()
    - 最大・最小: max(), maxOf(), min(), minOf()
    - クランプ: clamp(), coerceIn()
    - 線形補間: lerp()
  - **現状**: 基本的な数学関数は実装済み、高度な関数は未実装
  - **関連ファイル**: `RuntimeMath.swift`
  - **テストケース**: `Scripts/diff_cases/math_advanced.kt`

- [ ] STDLIB-MATH-111: IEEE丸め完全実装
  - **仕様**: IEEE 754丸めモードの完全サポート
  - **実装内容**:
    - 丸めモード: ROUND_UP, ROUND_DOWN, ROUND_CEILING, ROUND_FLOOR
    - 丸めモード: ROUND_HALF_UP, ROUND_HALF_DOWN, ROUND_HALF_EVEN
    - 丸めモード: ROUND_UNNECESSARY
    - 精度制御: MathContextの指定
    - 丸めモードのスレッドセーフティ
  - **現状**: 基本的な丸めは実装済み、IEEE丸めは未実装
  - **関連ファイル**: `RuntimeMath.swift`
  - **テストケース**: `Scripts/diff_cases/math_rounding_ieee.kt`

- [ ] STDLIB-MATH-112: 数学定数完全実装
  - **仕様**: 数学定数の完全サポート
  - **実装内容**:
    - 円周率: PI, Math.PI
    - 自然対数の底: E, Math.E
    - その他定数: TAU, SQRT2, SQRT1_2
    - 浮動小数点定数: POSITIVE_INFINITY, NEGATIVE_INFINITY, NaN
    - 定数の精度と型安全性
  - **現状**: 基本的な定数は実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeMath.swift`
  - **テストケース**: `Scripts/diff_cases/math_constants.kt`

#### Phase 3: アノテーションとメタプログラミング (低優先度)

- [ ] STDLIB-ANNO-113: アノテーション基本実装
  - **仕様**: アノテーションの基本的な機能
  - **実装内容**:
    - アノテーション宣言: @interface MyAnnotation
    - アノテーション使用: @MyAnnotation class MyClass
    - アノテーションプロパティ: val value: String, val count: Int
    - デフォルト値: val value: String = "default"
    - アノテーションターゲット: @Target
  - **現状**: 基本的なアノテーションは実装済み、詳細は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_basic.kt`

- [ ] STDLIB-ANNO-114: アノテーション保持完全実装
  - **仕様**: アノテーション保持ポリシーの完全サポート
  - **実装内容**:
    - SOURCE: ソースレベルでのみ保持
    - CLASS: クラスファイルに保持、実行時は破棄
    - RUNTIME: 実行時まで保持
    - 保持ポリシーの継承
    - アノテーションの継承: @Inherited
  - **現状**: 基本的なアノテーションは実装済み、保持ポリシーは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_retention.kt`

- [ ] STDLIB-ANNO-115: アノテーションターゲット完全実装
  - **仕様**: アノテーションターゲットの完全サポート
  - **実装内容**:
    - ターゲット種類: CLASS, FUNCTION, PROPERTY, FIELD
    - ターゲット種類: CONSTRUCTOR, PARAMETER, TYPE, EXPRESSION
    - ターゲット種類: FILE, TYPEALIAS, TYPE_PARAMETER
    - 複合ターゲット: @Target([ElementType.CLASS, ElementType.FUNCTION])
    - ターゲットの継承と制約
  - **現状**: 基本的なアノテーションは実装済み、ターゲットは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_target.kt`

- [ ] STDLIB-METAPROG-116: メタプログラミング基本実装
  - **仕様**: メタプログラミングの基本的な機能
  - **実装内容**:
    - アノテーション処理: AnnotationProcessor
    - コード生成: コンパイル時コード生成
    - シンボル解決: シンボルテーブルアクセス
    - 型情報: コンパイル時型情報
    - エラー報告: コンパイル時エラー生成
  - **現状**: メタプログラミングは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticTODOAndIOStubs.swift`
  - **テストケース**: `Scripts/diff_cases/metaprogramming_basic.kt`

#### 既存STDLIBタスクの整理

以下の既存STDLIBタスクを上記カテゴリに再分類：

- [x] STDLIB-001: 基本的なコレクション操作 → STDLIB-HOF-021に統合
- [x] STDLIB-002: 文字列操作 → STDLIB-EXT-026に統合
- [x] STDLIB-003: 数値変換 → STDLIB-PRIM-002に統合
- [x] STDLIB-004: 比較操作 → STDLIB-COMP-041に統合
- [x] STDLIB-005: 型変換 → STDLIB-PRIM-002に統合
- [x] STDLIB-006: 数学関数 → STDLIB-MATH-109に統合
- [x] STDLIB-008: ループ操作 → STDLIB-HOF-021に統合
- [x] STDLIB-009: コレクションファクトリ → STDLIB-ARR-003に統合
- [x] STDLIB-050: コレクション変換 → STDLIB-HOF-021に統合
- [x] STDLIB-052: シーケンス操作 → STDLIB-HOF-022に統合
- [x] STDLIB-061: スコープ関数 → STDLIB-SCOPE-024に統合
- [x] STDLIB-062: I/O操作 → STDLIB-IO-087に統合
- [x] STDLIB-063: println/readLine → STDLIB-IO-088に統合
- [x] STDLIB-071: buildMap → STDLIB-DELEG-043に統合
- [x] STDLIB-080: Char操作 → STDLIB-PRIM-009に統合
- [x] STDLIB-083: StringBuilder → STDLIB-EXT-027に統合
- [x] STDLIB-085: 文字列フォーマット → STDLIB-EXT-026に統合
- [x] STDLIB-087: 文字列比較 → STDLIB-COMP-041に統合
- [x] STDLIB-088: 文字列変換 → STDLIB-PRIM-002に統合
- [x] STDLIB-089: 文字列検索 → STDLIB-EXT-026に統合

---

## 実装計画のまとめ

### 総タスク数: 116件

- **Phase 1 (高優先度)**: 39タスク
  - 基本型と配列: 9タスク (STDLIB-PRIM-001 ~ STDLIB-PRIM-009)
  - オブジェクト指向機能: 11タスク (STDLIB-CLASS-010 ~ STDLIB-INHERIT-020)
  - 関数型プログラミング: 9タスク (STDLIB-HOF-021 ~ STDLIB-HOF-029)
  - 演算子と特殊構文: 10タスク (STDLIB-OP-030 ~ STDLIB-COMP-042)

- **Phase 2 (中優先度)**: 38タスク
  - プロパティデリゲート: 8タスク (STDLIB-DELEG-043 ~ STDLIB-LATEINIT-050)
  - ジェネリクスと型システム: 9タスク (STDLIB-GEN-051 ~ STDLIB-GEN-059)
  - リフレクション: 8タスク (STDLIB-REFLECT-060 ~ STDLIB-REFLECT-067)
  - 範囲操作: 13タスク (STDLIB-RANGE-034 ~ STDLIB-RANGE-040)

- **Phase 3 (低優先度)**: 39タスク
  - コルーチンと並行処理: 13タスク (STDLIB-CORO-068 ~ STDLIB-CORO-080)
  - 時間と期間: 6タスク (STDLIB-TIME-081 ~ STDLIB-TIME-086)
  - I/Oとファイルシステム: 7タスク (STDLIB-IO-087 ~ STDLIB-IO-093)
  - 正規表現: 5タスク (STDLIB-REGEX-094 ~ STDLIB-REGEX-098)
  - 乱数とUUID: 5タスク (STDLIB-RANDOM-099 ~ STDLIB-UUID-103)
  - エラー処理: 5タスク (STDLIB-EXCEPT-104 ~ STDLIB-RUNCATCH-108)
  - 数学関数: 4タスク (STDLIB-MATH-109 ~ STDLIB-MATH-112)
  - アノテーションとメタプログラミング: 4タスク (STDLIB-ANNO-113 ~ STDLIB-METAPROG-116)

### 実装方針

1. **段階的実装**: Phase 1から順に実装し、各フェーズ完了後に評価
2. **網羅的テスト**: 各タスクに対応するテストケースを作成・維持
3. **一貫性維持**: 既存実装との互換性を確保しつつ機能拡張
4. **ドキュメント整備**: 実装仕様と使用例を詳細に記録

#### Phase 4: 高度コレクションとデータ構造 (低優先度)

- [ ] STDLIB-COL-117: Map完全実装
  - **仕様**: Mapインターフェースの完全サポート
  - **実装内容**:
    - 基本操作: get(), put(), remove(), containsKey(), containsValue()
    - ビュー: keys, values, entries
    - 変換: mapValues(), mapKeys(), filter(), filterKeys(), filterValues()
    - 集約: count(), isEmpty(), isNotEmpty()
    - 変更可能: MutableMapのputAll(), clear()
  - **現状**: 基本的なMapは実装済み、高度な操作は未実装
  - **関連ファイル**: `RuntimeMap.swift`
  - **テストケース**: `Scripts/diff_cases/map_basic.kt`

- [ ] STDLIB-COL-118: Set完全実装
  - **仕様**: Setインターフェースの完全サポート
  - **実装内容**:
    - 基本操作: add(), remove(), contains(), size()
    - 集合演算: union(), intersect(), subtract()
    - フィルタリング: filter(), filterNot()
    - 変換: map(), mapNotNull(), flatMap()
    - 変更可能: MutableSetのaddAll(), removeAll(), retainAll()
  - **現状**: 基本的なSetは実装済み、集合演算は未実装
  - **関連ファイル**: `RuntimeSet.swift`
  - **テストケース**: `Scripts/diff_cases/set_basic.kt`

- [ ] STDLIB-COL-119: List完全実装
  - **仕様**: Listインターフェースの完全サポート
  - **実装内容**:
    - 基本操作: get(), set(), add(), remove(), indexOf(), lastIndexOf()
    - サブリスト: subList(), slice(), take(), drop()
    - 変換: map(), mapNotNull(), flatMap(), filter()
    - 検索: find(), findLast(), first(), last()
    - 変更可能: MutableListのaddAll(), removeAll()
  - **現状**: 基本的なListは実装済み、サブリスト操作は未実装
  - **関連ファイル**: `RuntimeList.swift`
  - **テストケース**: `Scripts/diff_cases/list_basic.kt`

- [ ] STDLIB-COL-120: コレクションファクトリ完全実装
  - **仕様**: コレクションファクトリ関数の完全サポート
  - **実装内容**:
    - Listファクトリ: listOf(), listOfNotNull(), emptyList()
    - Setファクトリ: setOf(), emptySet(), mutableSetOf()
    - Mapファクトリ: mapOf(), emptyMap(), mutableMapOf()
    - 連続値: (1..10).toList(), ('a'..'z').toList()
    - 配列変換: arrayOf().toList(), list.toTypedArray()
  - **現状**: 基本的なファクトリは実装済み、高度なファクトリは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticCollectionStubs.swift`
  - **テストケース**: `Scripts/diff_cases/collection_factories.kt`

- [ ] STDLIB-COL-121: コレクションビルダー完全実装
  - **仕様**: コレクションビルダーの完全サポート
  - **実装内容**:
    - buildList(): Listビルダー
    - buildSet(): Setビルダー
    - buildMap(): Mapビルダー
    - ビルダー操作: add(), addAll(), put(), putAll()
    - ビルダースコープ: this参照とreturn値
  - **現状**: buildMapは一部実装済み、他は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticCollectionStubs.swift`
  - **テストケース**: `Scripts/diff_cases/collection_builders.kt`

- [ ] STDLIB-COL-122: コレクション変換完全実装
  - **仕様**: コレクション間の完全な相互変換
  - **実装内容**:
    - 型変換: List<Number>をList<Int>に変換
    - 構造変換: ListをMapに変換（groupBy）
    - フラット化: List<List<T>>をList<T>に変換
    - 圧縮: zip()とunzip()操作
    - 分割: partition()とchunked()操作
  - **現状**: 基本的な変換は実装済み、高度な変換は未実装
  - **関連ファイル**: `RuntimeCollectionHOF.swift`
  - **テストケース**: `Scripts/diff_cases/collection_transformations.kt`

#### Phase 4: 高度文字列処理 (低優先度)

- [ ] STDLIB-STR-123: StringBuilder完全実装
  - **仕様**: StringBuilderの完全サポート
  - **実装内容**:
    - 基本操作: append(), insert(), delete(), replace()
    - 文字操作: setCharAt(), charAt()
    - 逆転: reverse()
    - 容量管理: capacity(), ensureCapacity(), trimToSize()
    - 変換: toString(), length()
  - **現状**: 基本的なStringBuilderは実装済み (STDLIB-083)、高度な操作は未実装
  - **関連ファイル**: `RuntimeStringStdlib.swift`
  - **テストケース**: `Scripts/diff_cases/string_builder.kt`

- [ ] STDLIB-STR-124: 文字列フォーマット完全実装
  - **仕様**: 文字列フォーマットの完全サポート
  - **実装内容**:
    - テンプレート文字列: "$variable", "${expression}"
    - format(): String.format()スタイル
    - 文字列補間: 複雑な式の補間
    - ロケール対応: ロケール依存のフォーマット
    - 数値フォーマット: 小数点、桁区切り、指数表記
  - **現状**: 基本的なフォーマットは実装済み (STDLIB-085)、高度なフォーマットは未実装
  - **関連ファイル**: `RuntimeStringStdlib.swift`
  - **テストケース**: `Scripts/diff_cases/string_format.kt`

- [ ] STDLIB-STR-125: 文字列エンコーディング完全実装
  - **仕様**: 文字列エンコーディングの完全サポート
  - **実装内容**:
    - エンコーディング指定: UTF-8, UTF-16, ISO-8859-1
    - バイト変換: toByteArray(), fromByteArray()
    - 文字セット: Charsetクラスのサポート
    - エンコーディング検出: バイト配列からのエンコーディング推測
    - エンコーディング変換: 異なるエンコーディング間の変換
  - **現状**: 基本的なエンコーディングは実装済み、詳細は未実装
  - **関連ファイル**: `RuntimeStringStdlib.swift`
  - **テストケース**: `Scripts/diff_cases/string_encoding.kt`

- [ ] STDLIB-STR-126: 文字列正規化完全実装
  - **仕様**: Unicode正規化の完全サポート
  - **実装内容**:
    - 正規化形式: NFC, NFD, NFKC, NFKD
    - 正規化関数: normalize(), isNormalized()
    - 文字等価性: 正規化による文字比較
    - 合成文字: 分解と結合の処理
    - 互換文字: 互換性のある文字の処理
  - **現状**: 文字列正規化は未実装
  - **関連ファイル**: `RuntimeStringStdlib.swift`
  - **テストケース**: `Scripts/diff_cases/string_normalization.kt`

- [ ] STDLIB-STR-127: 文字列ロケール完全実装
  - **仕様**: ロケール依存の文字列操作
  - **実装内容**:
    - 大文字小文字変換: toUpperCase(Locale), toLowerCase(Locale)
    - 文字列比較: compare(Locale)
    - 照合順序: Collatorのサポート
    - ロケール情報: Localeクラスのサポート
    - ロケール依存のフォーマット: 数値、日時、通貨
  - **現状**: ロケール依存操作は未実装
  - **関連ファイル**: `RuntimeStringStdlib.swift`
  - **テストケース**: `Scripts/diff_cases/string_locale.kt`

#### Phase 4: 数値処理と精度 (低優先度)

- [ ] STDLIB-NUM-128: BigDecimal完全実装
  - **仕様**: BigDecimalの完全サポート
  - **実装内容**:
    - 精度計算: 任意精度の小数点演算
    - 丸めモード: 全てのIEEE 754丸めモード
    - スケール操作: scale(), setScale(), precision()
    - 数学演算: add(), subtract(), multiply(), divide()
    - 比較: compareTo(), equals(), hashCode()
  - **現状**: BigDecimalは未実装
  - **関連ファイル**: `RuntimeBigDecimal.swift`
  - **テストケース**: `Scripts/diff_cases/big_decimal.kt`

- [ ] STDLIB-NUM-129: BigInteger完全実装
  - **仕様**: BigIntegerの完全サポート
  - **実装内容**:
    - 任意精度整数: 無制限の整数サイズ
    - 基本演算: add(), subtract(), multiply(), divide()
    - ビット演算: and(), or(), xor(), not(), shiftLeft(), shiftRight()
    - 数学関数: gcd(), abs(), modInverse(), modPow()
    - 変換: toInt(), toLong(), toByteArray()
  - **現状**: BigIntegerは未実装
  - **関連ファイル**: `RuntimeBigInteger.swift`
  - **テストケース**: `Scripts/diff_cases/big_integer.kt`

- [ ] STDLIB-NUM-130: 浮動小数点精度完全実装
  - **仕様**: 浮動小数点数の精度制御
  - **実装内容**:
    - 精度情報: ulp(), nextUp(), nextDown()
    - 特殊値: POSITIVE_INFINITY, NEGATIVE_INFINITY, NaN
    - 比較: isNaN(), isInfinite()
    - ビット表現: toBits(), fromBits()
    - 丸め: IEEE 754丸めの完全サポート
  - **現状**: 基本的な浮動小数点は実装済み、精度制御は未実装
  - **関連ファイル**: `RuntimeNumericCompat.swift`
  - **テストケース**: `Scripts/diff_cases/float_precision.kt`

- [ ] STDLIB-NUM-131: 数値フォーマット完全実装
  - **仕様**: 数値のフォーマットと解析
  - **実装内容**:
    - 10進数フォーマット: 整数、小数点、桁区切り
    - 科学技術表記: 指数形式のフォーマット
    - 16進数、8進数、2進数フォーマット
    - パーセントとパーミル: %, ‰記号
    - 通貨フォーマット: 通貨記号と小数点
  - **現状**: 基本的な数値フォーマットは実装済み、高度なフォーマットは未実装
  - **関連ファイル**: `RuntimeNumberFormat.swift`
  - **テストケース**: `Scripts/diff_cases/number_format.kt`

#### Phase 4: シリアライゼーション (低優先度)

- [ ] STDLIB-SER-132: JSONシリアライゼーション完全実装
  - **仕様**: JSONシリアライゼーションの完全サポート
  - **実装内容**:
    - JSONエンコード: オブジェクトをJSON文字列に変換
    - JSONデコード: JSON文字列をオブジェクトに変換
    - 型安全: ジェネリック型のシリアライゼーション
    - アノテーション: @SerializedName, @Expose等
    - フォーマット制御: インデント、日付フォーマット
  - **現状**: JSONシリアライゼーションは未実装
  - **関連ファイル**: `RuntimeSerialization.swift`
  - **テストケース**: `Scripts/diff_cases/json_serialization.kt`

- [ ] STDLIB-SER-133: データクラスシリアライゼーション完全実装
  - **仕様**: データクラスの自動シリアライゼーション
  - **実装内容**:
    - 自動シリアライズ: @Serializableアノテーション
    - プロパティマッピング: JSONフィールドとのマッピング
    - デフォルト値: シリアライズ時のデフォルト値処理
    - オプションプロパティ: null値の扱い
    - 入れ込みオブジェクト: 階層構造のシリアライゼーション
  - **現状**: データクラスシリアライゼーションは未実装
  - **関連ファイル**: `RuntimeSerialization.swift`
  - **テストケース**: `Scripts/diff_cases/dataclass_serialization.kt`

- [ ] STDLIB-SER-134: コレクションシリアライゼーション完全実装
  - **仕様**: コレクションのシリアライゼーション
  - **実装内容**:
    - Listシリアライゼーション: JSON配列への変換
    - Mapシリアライゼーション: JSONオブジェクトへの変換
    - Setシリアライゼーション: JSON配列への変換
    - 入れ込みコレクション: 階層コレクションのシリアライゼーション
    - ジェネリックコレクション: 型パラメータの保持
  - **現状**: コレクションシリアライゼーションは未実装
  - **関連ファイル**: `RuntimeSerialization.swift`
  - **テストケース**: `Scripts/diff_cases/collection_serialization.kt`

- [ ] STDLIB-SER-135: カスタムシリアライザ完全実装
  - **仕様**: カスタムシリアライザの完全サポート
  - **実装内容**:
    - KSerializerインターフェース: カスタムシリアライザの実装
    - シリアライザ登録: 型とシリアライザの紐付け
    - コンテキストアクセス: シリアライゼーションコンテキスト
    - エンコーダ/デコーダ: 低レベルのシリアライゼーションAPI
    - バリデーション: シリアライズ前のデータ検証
  - **現状**: カスタムシリアライザは未実装
  - **関連ファイル**: `RuntimeSerialization.swift`
  - **テストケース**: `Scripts/diff_cases/custom_serializer.kt`

#### Phase 4: ネットワークとHTTP (低優先度)

- [ ] STDLIB-NET-136: URL完全実装
  - **仕様**: URLクラスの完全サポート
  - **実装内容**:
    - URL作成: URL(String), URL(base, relative)
    - URL分解: protocol, host, port, path, query, fragment
    - URL操作: toURI(), toExternalForm()
    - URL比較: equals(), hashCode(), sameFile()
    - URLエンコーディング: エンコード/デコード
  - **現状**: URLは未実装
  - **関連ファイル**: `RuntimeNetwork.swift`
  - **テストケース**: `Scripts/diff_cases/url_basic.kt`

- [ ] STDLIB-NET-137: URI完全実装
  - **仕様**: URIクラスの完全サポート
  - **実装内容**:
    - URI作成: URI(String), URI(scheme, host, path, fragment)
    - URI分解: scheme, schemeSpecificPart, authority, path, query, fragment
    - URI操作: normalize(), resolve(), relativize()
    - URI比較: equals(), hashCode()
    - URIエスケープ: エスケープ/アンエスケープ
  - **現状**: URIは未実装
  - **関連ファイル**: `RuntimeNetwork.swift`
  - **テストケース**: `Scripts/diff_cases/uri_basic.kt`

- [ ] STDLIB-NET-138: HTTPクライアント基本実装
  - **仕様**: HTTPクライアントの基本的な機能
  - **実装内容**:
    - GETリクエスト: HTTP GETメソッド
    - POSTリクエスト: HTTP POSTメソッド
    - ヘッダー設定: リクエストヘッダーの指定
    - ボディ送信: リクエストボディの送信
    - レスポンス処理: ステータスコード、ヘッダー、ボディ
  - **現状**: HTTPクライアントは未実装
  - **関連ファイル**: `RuntimeNetwork.swift`
  - **テストケース**: `Scripts/diff_cases/http_client_basic.kt`

- [ ] STDLIB-NET-139: HTTPクライアント高度機能完全実装
  - **仕様**: HTTPクライアントの高度な機能
  - **実装内容**:
    - 非同期リクエスト: suspend関数でのHTTP通信
    - タイムアウト: 接続、読み取りタイムアウト
    - リダイレクト: 自動リダイレクト処理
    - 認証: Basic認証、Bearerトークン
    - HTTPS: SSL/TLSサポート
  - **現状**: HTTPクライアントは未実装
  - **関連ファイル**: `RuntimeNetwork.swift`
  - **テストケース**: `Scripts/diff_cases/http_client_advanced.kt`

#### Phase 4: データベースアクセス (低優先度)

- [ ] STDLIB-DB-140: JDBC基本実装
  - **仕様**: JDBCドライバの基本的な機能
  - **実装内容**:
    - コネクション: DriverManager.getConnection()
    - ステートメント: Statement, PreparedStatement
    - クエリ実行: executeQuery(), executeUpdate()
    - 結果セット: ResultSetの処理
    - リソース管理: close(), try-with-resources
  - **現状**: JDBCは未実装
  - **関連ファイル**: `RuntimeDatabase.swift`
  - **テストケース**: `Scripts/diff_cases/jdbc_basic.kt`

- [ ] STDLIB-DB-141: トランザクション管理完全実装
  - **仕様**: データベーストランザクションの完全サポート
  - **実装内容**:
    - トランザクション開始: connection.autoCommit = false
    - コミット: connection.commit()
    - ロールバック: connection.rollback()
    - セーブポイント: SavePointの作成と復元
    - トランザクション分離レベル: 4つの分離レベル
  - **現状**: トランザクション管理は未実装
  - **関連ファイル**: `RuntimeDatabase.swift`
  - **テストケース**: `Scripts/diff_cases/transaction_management.kt`

- [ ] STDLIB-DB-142: コネクションプール完全実装
  - **仕様**: データベースコネクションプール
  - **実装内容**:
    - プール作成: コネクションプールの初期化
    - コネクション取得: プールからのコネクション取得
    - コネクション返却: プールへのコネクション返却
    - プール設定: 最大コネクション数、タイムアウト
    - プール監視: コネクション状態の監視
  - **現状**: コネクションプールは未実装
  - **関連ファイル**: `RuntimeDatabase.swift`
  - **テストケース**: `Scripts/diff_cases/connection_pool.kt`

#### Phase 4: セキュリティと暗号化 (低優先度)

- [ ] STDLIB-SEC-143: メッセージダイジェスト完全実装
  - **仕様**: メッセージダイジェスト（ハッシュ）の完全サポート
  - **実装内容**:
    - MD5: MD5ハッシュアルゴリズム
    - SHA-1: SHA-1ハッシュアルゴリズム
    - SHA-256: SHA-256ハッシュアルゴリズム
    - SHA-512: SHA-512ハッシュアルゴリズム
    - HMAC: HMAC-based Message Authentication Code
  - **現状**: メッセージダイジェストは未実装
  - **関連ファイル**: `RuntimeSecurity.swift`
  - **テストケース**: `Scripts/diff_cases/message_digest.kt`

- [ ] STDLIB-SEC-144: 対称暗号完全実装
  - **仕様**: 対称暗号アルゴリズムの完全サポート
  - **実装内容**:
    - AES: AES暗号化/復号
    - DES: DES暗号化/復号
    - 3DES: Triple DES暗号化/復号
    - ブロックモード: ECB, CBC, CFB, OFB, CTR
    - パディング: PKCS5Padding, NoPadding
  - **現状**: 対称暗号は未実装
  - **関連ファイル**: `RuntimeSecurity.swift`
  - **テストケース**: `Scripts/diff_cases/symmetric_crypto.kt`

- [ ] STDLIB-SEC-145: 非対称暗号完全実装
  - **仕様**: 非対称暗号アルゴリズムの完全サポート
  - **実装内容**:
    - RSA: RSA暗号化/復号
    - DSA: Digital Signature Algorithm
    - ECDSA: Elliptic Curve DSA
    - 鍵生成: 公開鍵と秘密鍵の生成
    - 鍵管理: 鍵の保存と読み込み
  - **現状**: 非対称暗号は未実装
  - **関連ファイル**: `RuntimeSecurity.swift`
  - **テストケース**: `Scripts/diff_cases/asymmetric_crypto.kt`

- [ ] STDLIB-SEC-146: デジタル署名完全実装
  - **仕様**: デジタル署名の完全サポート
  - **実装内容**:
    - 署名生成: データへのデジタル署名
    - 署名検証: デジタル署名の検証
    - 署名アルゴリズム: SHA1withRSA, SHA256withRSA
    - 証明書: X.509証明書の処理
    - 証明書チェーン: 証明書パスの検証
  - **現状**: デジタル署名は未実装
  - **関連ファイル**: `RuntimeSecurity.swift`
  - **テストケース**: `Scripts/diff_cases/digital_signature.kt`

#### Phase 4: ロギングとデバッグ (低優先度)

- [ ] STDLIB-LOG-147: ロギング基本実装
  - **仕様**: ロギングフレームワークの基本的な機能
  - **実装内容**:
    - ロガー取得: Logger.getLogger()
    - ログレベル: SEVERE, WARNING, INFO, CONFIG, FINE, FINER, FINEST
    - ログメッセージ: ログメッセージの出力
    - 例外ログ: 例外情報のログ出力
    - ログフォーマット: ログメッセージのフォーマット
  - **現状**: ロギングは未実装
  - **関連ファイル**: `RuntimeLogging.swift`
  - **テストケース**: `Scripts/diff_cases/logging_basic.kt`

- [ ] STDLIB-LOG-148: ロギング高度機能完全実装
  - **仕様**: ロギングフレームワークの高度な機能
  - **実装内容**:
    - ハンドラ: ConsoleHandler, FileHandler
    - フォーマッタ: SimpleFormatter, XMLFormatter
    - フィルタ: ログメッセージのフィルタリング
    - ログ設定: プロパティファイルでの設定
    - パフォーマンス: 非同期ログ出力
  - **現状**: ロギングは未実装
  - **関連ファイル**: `RuntimeLogging.swift`
  - **テストケース**: `Scripts/diff_cases/logging_advanced.kt`

- [ ] STDLIB-LOG-149: アサーション完全実装
  - **仕様**: アサーション機能の完全サポート
  - **実装内容**:
    - assert()関数: 条件の検証
    - アサーション有効/無効: 実行時の制御
    - エラーメッセージ: アサーション失敗時のメッセージ
    - アサーション例外: AssertionErrorのスロー
    - デバッグ支援: 開発時のデバッグ支援
  - **現状**: アサーションは未実装
  - **関連ファイル**: `RuntimeDebug.swift`
  - **テストケース**: `Scripts/diff_cases/assertions.kt`

#### Phase 4: 国際化とローカライゼーション (低優先度)

- [ ] STDLIB-I18N-150: Locale完全実装
  - **仕様**: Localeクラスの完全サポート
  - **実装内容**:
    - Locale作成: Locale(String), Locale(language, country)
    - Locale情報: language, country, variant, displayLanguage
    - デフォルトLocale: Locale.getDefault(), setDefault()
    - Locale比較: equals(), hashCode()
    - 利用可能Locale: getAvailableLocales()
  - **現状**: Localeは未実装
  - **関連ファイル**: `RuntimeI18N.swift`
  - **テストケース**: `Scripts/diff_cases/locale_basic.kt`

- [ ] STDLIB-I18N-151: ResourceBundle完全実装
  - **仕様**: ResourceBundleの完全サポート
  - **実装内容**:
    - バンドル読み込み: ResourceBundle.getBundle()
    - プロパティアクセス: getString(), getObject()
    - 親バンドル: 階層的なリソースバンドル
    - Locale対応: ロケール依存のリソース選択
    - キー列挙: getKeys()メソッド
  - **現状**: ResourceBundleは未実装
  - **関連ファイル**: `RuntimeI18N.swift`
  - **テストケース**: `Scripts/diff_cases/resource_bundle.kt`

- [ ] STDLIB-I18N-152: 数値フォーマット完全実装
  - **仕様**: 数値のロケール依存フォーマット
  - **実装内容**:
    - NumberFormat: 数値フォーマッタ
    - 整数フォーマット: ロケール依存の整数フォーマット
    - 小数フォーマット: ロケール依存の小数フォーマット
    - 通貨フォーマット: 通貨記号と書式
    - パーセントフォーマット: パーセント表示
  - **現状**: 数値フォーマットは未実装
  - **関連ファイル**: `RuntimeI18N.swift`
  - **テストケース**: `Scripts/diff_cases/number_format_locale.kt`

- [ ] STDLIB-I18N-153: 日付フォーマット完全実装
  - **仕様**: 日付時刻のロケール依存フォーマット
  - **実装内容**:
    - DateFormat: 日付フォーマッタ
    - 日付パターン: カスタム日付パターン
    - 時間フォーマット: 時間のみのフォーマット
    - 日時フォーマット: 日付と時間の組み合わせ
    - タイムゾーン: タイムゾーン考慮のフォーマット
  - **現状**: 日付フォーマットは未実装
  - **関連ファイル**: `RuntimeI18N.swift`
  - **テストケース**: `Scripts/diff_cases/date_format_locale.kt`

#### Phase 4: パフォーマンスと最適化 (低優先度)

- [ ] STDLIB-PERF-154: メモリ管理完全実装
  - **仕様**: メモリ管理の高度な機能
  - **実装内容**:
    - メモリ使用量: Runtime.getRuntime().totalMemory()
    - 空きメモリ: freeMemory(), maxMemory()
    - ガベージコレクション: System.gc()
    - メモリリーク検出: メモリリークの検出ツール
    - パフォーマンス監視: メモリ使用量の監視
  - **現状**: メモリ管理は未実装
  - **関連ファイル**: `RuntimeMemory.swift`
  - **テストケース**: `Scripts/diff_cases/memory_management.kt`

- [ ] STDLIB-PERF-155: 並列処理完全実装
  - **仕様**: 並列処理の最適化
  - **実装内容**:
    - 並列ストリーム: parallelStream()のサポート
    - フォークジョインプール: ForkJoinPoolの管理
    - ワースティーリング: ワークスティーリングアルゴリズム
    - タスク分割: 再帰的なタスク分割
    - 負荷分散: 動的な負荷分散
  - **現状**: 並列処理は未実装
  - **関連ファイル**: `RuntimeParallel.swift`
  - **テストケース**: `Scripts/diff_cases/parallel_processing.kt`

- [ ] STDLIB-PERF-156: キャッシュ機構完全実装
  - **仕様**: キャッシュ機構の完全サポート
  - **実装内容**:
    - LRUキャッシュ: Least Recently Usedキャッシュ
    - キャッシュサイズ: 最大サイズとエビクション
    - キャッシュポリシー: TTL、サイズベースのポリシー
    - キャッシュ統計: ヒット率、ミス率の統計
    - スレッドセーフ: マルチスレッド対応のキャッシュ
  - **現状**: キャッシュ機構は未実装
  - **関連ファイル**: `RuntimeCache.swift`
  - **テストケース**: `Scripts/diff_cases/cache_mechanism.kt`

#### Phase 4: テストと検証 (低優先度)

- [ ] STDLIB-TEST-157: テストフレームワーク基本実装
  - **仕様**: テストフレームワークの基本的な機能
  - **実装内容**:
    - テストアノテーション: @Test, @Before, @After
    - アサーション: assertEquals(), assertTrue(), assertNull()
    - テストスイート: テストケースのグループ化
    - テスト実行: テストの自動実行
    - テスト結果: 成功/失敗のレポート
  - **現状**: テストフレームワークは未実装
  - **関連ファイル**: `RuntimeTest.swift`
  - **テストケース**: `Scripts/diff_cases/test_framework_basic.kt`

- [ ] STDLIB-TEST-158: モックオブジェクト完全実装
  - **仕様**: モックオブジェクトの完全サポート
  - **実装内容**:
    - モック作成: インターフェースのモック生成
    - 振る舞い定義: when().thenReturn()のスタブ
    - 検証: verify()によるメソッド呼び出し検証
    - 引数マッチャー: any(), eq()などのマッチャー
    - スパイ: 部分的なモック（スパイ）
  - **現状**: モックオブジェクトは未実装
  - **関連ファイル**: `RuntimeTest.swift`
  - **テストケース**: `Scripts/diff_cases/mock_objects.kt`

- [ ] STDLIB-TEST-159: プロパティベーステスト完全実装
  - **仕様**: プロパティベーステストの完全サポート
  - **実装内容**:
    - 乱数生成: テストデータの自動生成
    - プロパティ検証: 不変性の検証
    - シュリンク: 失敗ケースの最小化
    - 生成戦略: カスタムデータ生成戦略
    - 統計レポート: テスト実行の統計情報
  - **現状**: プロパティベーステストは未実装
  - **関連ファイル**: `RuntimeTest.swift`
  - **テストケース**: `Scripts/diff_cases/property_based_test.kt`

---

### Phase 4 実装計画のまとめ

**Phase 4タスク数: 43件**

- **高度コレクションとデータ構造**: 6タスク (STDLIB-COL-117 ~ STDLIB-COL-122)
- **高度文字列処理**: 5タスク (STDLIB-STR-123 ~ STDLIB-STR-127)
- **数値処理と精度**: 4タスク (STDLIB-NUM-128 ~ STDLIB-NUM-131)
- **シリアライゼーション**: 4タスク (STDLIB-SER-132 ~ STDLIB-SER-135)
- **ネットワークとHTTP**: 4タスク (STDLIB-NET-136 ~ STDLIB-NET-139)
- **データベースアクセス**: 3タスク (STDLIB-DB-140 ~ STDLIB-DB-142)
- **セキュリティと暗号化**: 4タスク (STDLIB-SEC-143 ~ STDLIB-SEC-146)
- **ロギングとデバッグ**: 3タスク (STDLIB-LOG-147 ~ STDLIB-LOG-149)
- **国際化とローカライゼーション**: 4タスク (STDLIB-I18N-150 ~ STDLIB-I18N-153)
- **パフォーマンスと最適化**: 3タスク (STDLIB-PERF-154 ~ STDLIB-PERF-156)
- **テストと検証**: 3タスク (STDLIB-TEST-157 ~ STDLIB-TEST-159)

### 全体実装計画の更新

**総タスク数: 159件**
- Phase 1: 39タスク
- Phase 2: 38タスク  
- Phase 3: 39タスク
- Phase 4: 43タスク

Phase 4は専門的な高度機能を含み、Phase 1-3の基盤が完成した後に実装を開始します。

#### Phase 5: 実験的機能と高度API (低優先度)

- [ ] STDLIB-EXP-160: コンテキストレシーバ完全実装
  - **仕様**: コンテキストレシーバの完全サポート
  - **実装内容**:
    - コンテキストレシーバ宣言: context(Context) fun function()
    - コンテキストパラメータ: -Xcontext-parametersコンパイラ引数
    - 明示的コンテキスト引数: -Xexplicit-context-arguments
    - コンテキストの解決とバインディング
    - 入れ込みコンテキストとコンテキスト継承
  - **現状**: コンテキストレシーバは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticContextReceivers.swift`
  - **テストケース**: `Scripts/diff_cases/context_receivers.kt`

- [ ] STDLIB-EXP-161: バリュークラス完全実装
  - **仕様**: バリュークラスの完全サポート
  - **実装内容**:
    - @JvmInlineアノテーション: inline classの宣言
    - 単一フィールド: 1つのプライマリコンストラクタプロパティ
    - ボクシング暴露: -Xjvm-expose-boxedでのJava公開
    - ジェネリックインラインクラス: -Xinline-classes
    - マルチフィールドバリュークラス: -Xvalue-classes
  - **現状**: インラインクラスは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticInlineClasses.swift`
  - **テストケース**: `Scripts/diff_cases/value_classes.kt`

- [ ] STDLIB-EXP-162: 高度型推論完全実装
  - **仕様**: 高度な型推論アルゴリズムの完全サポート
  - **実装内容**:
    - 新型推論: -Xnew-inferenceコンパイラ引数
    - ビルダー推論: -Xunrestricted-builder-inference
    - 型制約処理: ProperTypeInferenceConstraintsProcessing
    - 実験的型推論: @ExperimentalTypeInference
    - 型推論エラーの改善
  - **現状**: 基本的な型推論は実装済み、高度な推論は未実装
  - **関連ファイル**: `TypeChecker.swift`
  - **テストケース**: `Scripts/diff_cases/advanced_type_inference.kt`

- [ ] STDLIB-EXP-163: 実験的アトミック操作完全実装
  - **仕様**: 実験的アトミック操作の完全サポート
  - **実装内容**:
    - ExperimentalAtomicApi: 実験的アトミックAPIマーカー
    - AtomicIntArray, AtomicLongArray: アトミック配列
    - AtomicReference: アトミック参照
    - compareAndSet: CAS操作
    - メモリバリア: メモリ一貫性保証
  - **現状**: 基本的なアトミック操作は一部実装済み、実験的APIは未実装
  - **関連ファイル**: `RuntimeAtomic.swift`
  - **テストケース**: `Scripts/diff_cases/experimental_atomic.kt`

- [ ] STDLIB-EXP-164: KMP（マルチプラットフォーム）API完全実装
  - **仕様**: Kotlin Multiplatform APIの完全サポート
  - **実装内容**:
    - expect/actual宣言: プラットフォーム固有実装
    - 共通コード: 共通モジュールの実装
    - プラットフォーム依存: iOS, Android, JS, Native対応
    - リソース管理: マルチプラットフォームリソース
    - ビルド設定: Gradleマルチプラットフォーム設定
  - **現状**: KMPサポートは未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticKMPSupport.swift`
  - **テストケース**: `Scripts/diff_cases/kmp_common.kt`

#### Phase 5: プラットフォーム固有機能 (低優先度)

- [ ] STDLIB-JVM-165: JVM固有API完全実装
  - **仕様**: JVMプラットフォーム固有の完全サポート
  - **実装内容**:
    - @JvmNameアノテーション: Java名前のマッピング
    - @JvmStatic: スタティックメソッド生成
    - @JvmField: フィールド公開
    - @JvmOverloads: オーバーロード生成
    - Java相互運用性: Javaクラスとの完全な相互運用
  - **現状**: 基本的なJVMアノテーションは実装済み、高度な機能は未実装
  - **関連ファイル**: `HeaderHelpers+SyntheticJvmStubs.swift`
  - **テストケース**: `Scripts/diff_cases/jvm_annotations.kt`

- [ ] STDLIB-JVM-166: Javaプレビュー機能完全実装
  - **仕様**: Javaプレビュー機能の完全サポート
  - **実装内容**:
    - -Xjvm-enable-preview: Javaプレビュー機能有効化
    - 新Java API: 最新Java APIのサポート
    - レコードクラス: Javaレコードとの相互運用
    - シールドクラス: Javaシールドクラスとの相互運用
    - パターンマッチング: Javaパターンマッチング対応
  - **現状**: Javaプレビュー機能は未実装
  - **関連ファイル**: `RuntimeJvmInterop.swift`
  - **テストケース**: `Scripts/diff_cases/java_preview.kt`

- [ ] STDLIB-JS-167: JavaScript固有API完全実装
  - **仕様**: Kotlin/JSプラットフォーム固有の完全サポート
  - **実装内容**:
    - @ExperimentalJsExport: JSへのエクスポート
    - @ExperimentalJsFileName: JSファイル名制御
    - @ExperimentalJsStatic: スタティックメンバー
    - @ExperimentalJsReflectionCreateInstance: リフレクション
    - @ExperimentalJsCollectionsApi: JSコレクションAPI
  - **現状**: JS固有機能は未実装
  - **関連ファイル**: `RuntimeJsInterop.swift`
  - **テストケース**: `Scripts/diff_cases/js_annotations.kt`

- [ ] STDLIB-NATIVE-168: Native固有API完全実装
  - **仕様**: Kotlin/Nativeプラットフォーム固有の完全サポート
  - **実装内容**:
    - @ExperimentalObjCName: Objective-C名前のマッピング
    - @ExperimentalObjCRefinement: Objective-C改良
    - @ExperimentalObjCEnum: Objective-C列挙型
    - @ExperimentalNativeApi: ネイティブAPIマーカー
    - C相互運用: Cライブラリとの相互運用
  - **現状**: Native固有機能は未実装
  - **関連ファイル**: `RuntimeNativeInterop.swift`
  - **テストケース**: `Scripts/diff_cases/native_annotations.kt`

- [ ] STDLIB-NATIVE-169: プラットフォーム情報完全実装
  - **仕様**: プラットフォーム情報の完全サポート
  - **実装内容**:
    - Platform.canAccessUnaligned: アライメントなしアクセス
    - Platform.isLittleEndian: エンディアン情報
    - Platform.osFamily: OSファミリー情報
    - Platform.cpuArchitecture: CPUアーキテクチャ
    - Platform.getAvailableProcessors(): プロセッサ数
  - **現状**: プラットフォーム情報は未実装
  - **関連ファイル**: `RuntimePlatform.swift`
  - **テストケース**: `Scripts/diff_cases/platform_info.kt`

#### Phase 5: 非推奨APIと移行 (低優先度)

- [ ] STDLIB-DEP-170: 非推奨API完全実装
  - **仕様**: 非推奨APIの完全サポートと移行支援
  - **実装内容**:
    - Number.toChar(): 非推奨変換関数
    - kotlin.io.createTempDir: 非推奨一時ディレクトリ作成
    - createTempFile: 非推奨一時ファイル作成
    - String.subSequence(start, end): 非推奨部分列取得
    - 非推奨警告: コンパイル時警告の生成
  - **現状**: 非推奨APIは未実装
  - **関連ファイル**: `RuntimeDeprecated.swift`
  - **テストケース**: `Scripts/diff_cases/deprecated_apis.kt`

- [ ] STDLIB-DEP-171: レガシーメモリ管理完全実装
  - **仕様**: レガシーメモリ管理APIの完全サポート
  - **実装内容**:
    - Platform.memoryModel: 非推奨メモリモデル
    - Platform.isFreezingEnabled: 非推奨フリーズ機能
    - Platform.isMemoryLeakCheckerActive: 非推奨メモリリーク検出
    - Platform.isCleanersLeakCheckerActive: 非推奨クリーナーリーク検出
    - 移行ガイド: 新メモリ管理への移行支援
  - **現状**: レガシーメモリ管理は未実装
  - **関連ファイル**: `RuntimeMemory.swift`
  - **テストケース**: `Scripts/diff_cases/legacy_memory.kt`

#### Phase 5: 高度リフレクションとメタプログラミング (低優先度)

- [ ] STDLIB-REFL-172: メタデータAPI完全実装
  - **仕様**: kotlinx-metadata互換のメタデータAPI
  - **実装内容**:
    - KmFunction: 関数メタデータ
    - KmConstructor: コンストラクタメタデータ
    - KmAnnotation: アノテーションメタデータ
    - compilerPluginMetadata: コンパイラプラグインメタデータ
    - メタデータシリアライズ: メタデータのシリアライズ/デシリアライズ
  - **現状**: メタデータAPIは未実装
  - **関連ファイル**: `RuntimeMetadata.swift`
  - **テストケース**: `Scripts/diff_cases/metadata_api.kt`

- [ ] STDLIB-REFL-173: コンパイラプラグインAPI完全実装
  - **仕様**: コンパイラプラグインAPIの完全サポート
  - **実装内容**:
    - CommandProcessor: コンパイラコマンド処理
    - ExtensionRegistrar: 拡張登録
    - IrGenerationExtension: IR生成拡張
    - ClassBuilderInterceptor: クラスビルダーインターセプト
    - プラグインメタデータ: プラグイン情報の保存
  - **現状**: コンパイラプラグインAPIは未実装
  - **関連ファイル**: `CompilerPlugin.swift`
  - **テストケース**: `Scripts/diff_cases/compiler_plugin_api.kt`

- [ ] STDLIB-REFL-174: KSP（シンボル処理）基本実装
  - **仕様**: Kotlin Symbol Processingの基本的なサポート
  - **実装内容**:
    - SymbolProcessor: シンボルプロセッサインターフェース
    - KSPLogger: ロギング機能
    - Resolver: シンボル解決
    - CodeGenerator: コード生成
    - プロセッサ登録: プロセッサの登録と実行
  - **現状**: KSPは未実装
  - **関連ファイル**: `RuntimeKSP.swift`
  - **テストケース**: `Scripts/diff_cases/ksp_basic.kt`

- [ ] STDLIB-REFL-175: アノテーション処理高度機能完全実装
  - **仕様**: アノテーション処理の高度な機能
  - **実装内容**:
    - KAPT統合: Kotlin Annotation Processing Tool
    - ラウンド処理: 複数ラウンドの処理
    - 増分処理: 増分コンパイル対応
    - オプション管理: プロセッサオプション
    - エラー報告: コンパイルエラーの生成
  - **現状**: アノテーション処理は未実装
  - **関連ファイル**: `RuntimeKAPT.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_processing.kt`

#### Phase 5: 高度Flowとコルーチン (低優先度)

- [ ] STDLIB-FLOW-176: Flow高度演算子完全実装
  - **仕様**: kotlinx.coroutinesの高度Flow演算子
  - **実装内容**:
    - 変換演算子: map, filter, transform, takeWhile, dropWhile
    - フラット化: flatMapConcat, flatMapMerge, flatMapLatest
    - 組合せ演算子: combine, zip, merge
    - バッファリング: buffer, conflate, flowOn
    - タイミング: debounce, sample, delayEach
  - **現状**: 基本的なFlowは実装済み、高度な演算子は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_advanced_operators.kt`

- [ ] STDLIB-FLOW-177: SharedFlowとStateFlow完全実装
  - **仕様**: ホットストリームの完全サポート
  - **実装内容**:
    - SharedFlow: マルチキャストホットフロー
    - StateFlow: 状態保持ホットフロー
    - shareIn(): コールドフローからSharedFlowへの変換
    - stateIn(): コールドフローからStateFlowへの変換
    - リプレイキャッシュ: 過去値のキャッシュ機能
  - **現状**: SharedFlowとStateFlowは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/shared_state_flow.kt`

- [ ] STDLIB-FLOW-178: Flowビルダー完全実装
  - **仕様**: 全てのFlowビルダーの完全サポート
  - **実装内容**:
    - flowOf(): 固定値からのフロー生成
    - emptyFlow(): 空フロー生成
    - channelFlow(): チャネルベースのフロー
    - callbackFlow(): コールバックベースのフロー
    - asFlow(): コレクションからのフロー変換
  - **現状**: 基本的なflowビルダーは実装済み、高度なビルダーは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_builders.kt`

- [ ] STDLIB-FLOW-179: Flowエラーハンドリング完全実装
  - **仕様**: Flowの完全なエラーハンドリング
  - **実装内容**:
    - catch(): 上流例外の処理
    - retry(): 失敗時のリトライ
    - retryWhen(): 条件付きリトライ
    - onErrorReturn(): エラー時のデフォルト値
    - onErrorResume(): エラー時の代替フロー
  - **現状**: Flowエラーハンドリングは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_error_handling.kt`

#### Phase 5: 高度時間測定 (低優先度)

- [ ] STDLIB-TIME-180: 実験的時間API完全実装
  - **仕様**: 実験的時間APIの完全サポート
  - **実装内容**:
    - @ExperimentalTime: 実験的時間APIマーカー
    - Clockインターフェース: 時計の抽象化
    - Clock.System: システム時計実装
    - TimeSource: 時間ソースの抽象化
    - TimeMark: 時間マークと差分計算
  - **現状**: 基本的な時間APIは実装済み、実験的APIは未実装
  - **関連ファイル**: `RuntimeTime.swift`
  - **テストケース**: `Scripts/diff_cases/experimental_time.kt`

- [ ] STDLIB-TIME-181: プラットフォーム時間変換完全実装
  - **仕様**: プラットフォーム固有の時間API変換
  - **実装内容**:
    - JVM: Instant.toJavaInstant(), java.time.Instant.toKotlinInstant()
    - JVM: Duration.toJavaDuration(), java.time.Duration.toKotlinDuration()
    - JS: Instant.toJSDate(), Date.toKotlinInstant()
    - Native: プラットフォーム固有時間API
    - 変換の安全性: 型安全な時間変換
  - **現状**: プラットフォーム時間変換は未実装
  - **関連ファイル**: `RuntimeTime.swift`
  - **テストケース**: `Scripts/diff_cases/platform_time_conversion.kt`

---

### 全体実装計画の最終更新

**総タスク数: 181件**
- Phase 1: 39タスク（高優先度）
- Phase 2: 38タスク（中優先度）
- Phase 3: 39タスク（低優先度）
- Phase 4: 43タスク（専門的機能）
- Phase 5: 22タスク（実験的・プラットフォーム固有機能）

Phase 5は実験的機能、プラットフォーム固有API、非推奨APIの移行支援、高度メタプログラミング機能を含み、他のフェーズが完了した後に段階的に実装します。

*他のSTDLIBタスクも適切なカテゴリに再分類していく*
