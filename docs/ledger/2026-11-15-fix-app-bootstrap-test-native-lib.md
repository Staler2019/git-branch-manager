# fix/app-bootstrap-test-native-lib — app_bootstrap_test 不再依賴 build/native/ 沒有 library

## Situation

feat/add-color 一輪為了實機截圖跑了 `app_flutter/scripts/build_capi.sh`，它把 `libgbm_capi.dylib` 放進 `app_flutter/build/native/`。之後全套 `flutter test` 出現 1 個紅：`app_bootstrap_test.dart` 的「a library that cannot be opened installs nothing and leaves the provider lazy」，`Expected: throws anything / Actual: returned <Instance of 'GbmBindings'>`。

- library 移開即綠；在 `origin/main`（`f1e9b5a7` 之前的 main）放入同一個 dylib 同樣紅，不是 feat/add-color 造成。
- `build_capi.sh` 開頭註解說它是「把 gbm_capi 放進 build/native/ 給 `flutter test`」最快的方法，所以照文件做就會紅。
- `ci.yml` 的 Flutter job 不跑 `build_capi`（同檔註解），CI 永遠沒有這個 library，看不到。

## Task

使用者裁定（2026-11-15）：「直接修，開新分支」。範圍只有這個測試；不改 `app_bootstrap.dart`。

## Action

斷言原本是「讀 `gbmBindingsProvider` 會丟例外」，把「bootstrap 沒有覆寫 provider」這件事寄託在環境裡打不開 library 上（[TEST-fixture-cannot-disagree] 第 13 種：受環境約束）。

改成在 `bootstrapApp` 回傳的 scope 外面再包一層 `ProviderScope`，覆寫成哨兵 `_Bindings()`，斷言讀到的是 `same(outer)`：只有 bootstrap 自己的 scope 沒覆寫時，外層的值才會透出來。

## Result

- 新測試有無 library 都 +2 綠；舊測試有 library 時紅。
- Mutation 3 次（只改 `app_bootstrap.dart` 的覆寫那一行）：
  - 舊測試 vs「以會丟例外的 provider 覆寫」：仍綠，舊斷言本身就抓不到這種錯。
  - 新測試 vs 同一個 mutation：紅。
  - 新測試 vs「以真的 bindings 覆寫」：紅。
  - 兩次紅都只紅這一個測試。
- 全套 +4681 ~19 綠，analyzer 0。
- 沒有蒸餾新 rule：[TEST-fixture-cannot-disagree] 已涵蓋這種形狀。
