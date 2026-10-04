# 2026-09-28 · chore/accept-toolchain-bump — 接受工具鏈升級，並把 Flutter CI 開到三個 OS

使用者要求三件事，依序：「add test png to gitignore and accept package upgrades」、
「golden failure 有辦法修嗎，至少提2個建議我看看」、「開個windows 與macos ci」。

## 一、gitignore 與套件升級

工作區帶著五個未提交的檔案，全部是本機 Flutter 3.47.4 對上 CI 釘的 3.44.9 所產生的漂移
（[CI-newer-flutter-dirties-tracked-files] 記的正是這個形狀，但它記的處置是「還原」，
本輪依使用者裁定改為「接受」）。

| 檔案 | 內容 | commit |
|---|---|---|
| `.gitignore` | 新增 `app_flutter/test/goldens/failures/` | C1 |
| `pubspec.lock` | matcher/meta/test_api/vector_math 四筆 transitive | C2 |
| `analysis_options.yaml` | SDK 自己加的 `analyzer: exclude` | C2 |
| `devtools_options.yaml` | DevTools 產生的空 extensions 檔 | C2 |
| `project.pbxproj` | `MACOSX_DEPLOYMENT_TARGET` 10.15 → 12.0 | C3 |

- 四筆套件都不是本專案選的：本機 3.47.4 的 `flutter_test/pubspec.yaml` 把
  `test_api: 0.7.12`、`matcher: 0.12.20` 釘成**精確版**，3.44.9 釘的是舊的那組。
- CI 的 `flutter pub get` 沒有 `--enforce-lockfile`，所以 CI 會照自己 SDK 的 pin 重解一次；
  lock 在 CI 上等於建議值而非約束。**這是查證過的，不是推測**——三個 workflow 的
  `pub get` 呼叫全部看過。
- pbxproj 獨立一個 commit：它是**平台下限**變更（放掉 macOS 11），不是套件升級，
  要退回只 revert 那一筆。

## 二、golden 失敗：量了之後才知道是什麼

`test/goldens/failures/` 之所以存在，是因為 golden 真的是紅的。實跑 **12 紅 9 綠**。

```
gbm_tag_chip    ×2   0.21%   ~1000px
gbm_button      ×3   0.04-0.05%  179-257px
gbm_panel       ×3   0.02%   95-104px
gbm_icon_button ×2   0.00%   6px
```

看 `gbm_tag_chip_lightIde_isolatedDiff.png`：**差異只落在圓角外框那一圈線**，
文字、填色、位置、尺寸全部沒動。是 3.44 → 3.47 engine 對曲線描邊的光柵化改變。

**不是本輪造成的，也不是上一輪造成的。** INDEX 上 2026-09-20 那輪記了「9 個 goldens
既有無關的 0.04% 像素差異失敗」，2026-09-26 那輪記了「12 顆 golden 紅在本輪之前就存在」。
所以它至少從 9/20 起就是紅的，而且從 9 顆長到 12 顆。

### 上一輪我講錯的一句話，就地更正

我先說過「重產基準圖會讓 CI 變紅」。**錯的。** `ci.yml` 的 `flutter-ci` 當時 `runs-on:
ubuntu-22.04`，而七組 golden 每一組都帶 `skip: !Platform.isMacOS` —— CI 從來沒跑過它們一次。

於是真正的缺陷不是像素差，是**這批 golden 沒有任何一層在驗它**：
[CULT-orphan-wiring] 的形狀，孤兒在「執行者」那一側。它只在開發者剛好於 macOS 上跑全套時
才出聲，而出聲了兩輪也沒人處理。

三個選項向使用者提出（A 容差 comparator、B 重產基準圖、C 讓它進 CI），
使用者選了 C 的前提——先把 CI 開出來。A 的代價當時就寫明：這批 widget 的 diff 全集中在
外框那一圈，所以「border-radius 改 1px」和抗鋸齒漂移是同一個數量級，0.5% 門檻會一起吃掉。

## 三、Flutter CI 開到三個 OS（C4）

`flutter-ci` 從單一 `ubuntu-22.04` 改成 `fail-fast: false` 的三 OS matrix，
沿用 `capi-build` 既有的 `matrix.include` 慣用法。

```
                   Linux          macOS (arm64)    Windows
                   ubuntu-22.04   macos-26         windows-latest
  msvc-dev-cmd        –              –                ✔
  flutter analyze     ✔              ✔                ✔
  flutter test        ✔              ✔ ← goldens      ✔
  apt desktop deps    ✔              –                –
  build_capi          .sh            .sh              .ps1
  flutter build       linux          macos            windows   (--debug)
```

關掉了兩個**本來就被記成「開著」而非「不知道」**的缺口：

1. [CI-linux-only] / **#69**：`windows/runner/`、`macos/Runner/` 在 release tag 之前
   由任何東西編譯，所以那裡的修改是未編譯就進 main 的。
2. fix/windows-host-updater-tests 自己在「沒做／開著的」列的第一項：
   「**Flutter 單元層仍然沒有 Windows CI job**……加一個 job 是使用者的決定，本輪沒動。」
   那一輪在真實 Windows 主機上量到 58 紅，而沒有任何一層看得見。

順帶關掉一個生產者端孤兒：`build_capi.ps1` 的檔頭自己寫著「PowerShell for the CI Windows
runner」，而在這個 matrix 之前**沒有任何 CI job 呼叫它**。

### 幾個做法上的取捨

- **MSVC 步驟是必要的，不是裝飾**。GitHub 的 Windows image 同時有 MinGW `g++` 與 MSVC，
  沒有 toolchain 步驟時 CMake 的探測拿到哪個看順序（[CI-windows-toolchain-not-implied]）。
- **`flutter analyze` 三個 OS 都跑**，而不是只在 Linux。它 ~25s，而省下來要付的代價是一個
  `if:`，其前提（「analyzer 不隨 host 變」）這個 repo 沒有任何東西在驗。
- **`flutter test` 排在 capi build 之前**，沿用原本的理由：這一層是純 Dart，不需要 native lib。
- **macOS 走 `build_capi.sh`**，照 `release.yml` 已證實可行的順序。注意
  `release.yml` 的註解說 macOS「沒有 Phase B」，而 `build_capi.sh` 的檔頭說
  `macos/Runner.xcodeproj` 有一個 "Build gbm_capi" Run Script phase，grep 也確實在
  `project.pbxproj:343` 找到它——**兩段註解互相矛盾，本輪沒有裁決**，只是照著兩邊都成立的
  那個順序走（[CULT-scrutinise-the-comment] 的候選，記在這裡而不是留白）。

### 驗證做到哪裡

- `flutter analyze` → 0 issues（本機，3.47.4）。
- YAML 以 Ruby 的 `YAML.load_file` 解析過：四個 job、matrix 三筆、`flutter-ci` 11 個 step、
  `needs: capi-build` 保留。
- `cq.yml` 的「every flutter-action use must pin flutter-version」lint 在本機跑過，通過。
- `scripts/check-rule-pins.py` → 209 條規則、176 個交叉引用、懸空 0。
- **三個新 job 本身沒有任何本機驗證可言**——唯一的驗證是推上去看。G3 的「開 PR 後盯 CI 到綠」
  是這一輪唯一能證明它的東西，還沒做。

### 已知風險，寫出來而不是暗示

**macOS job 很可能第一次就紅在 goldens。** CI 釘 3.44.9，而基準圖是 3.44.x 在某台開發機上
烤的，所以它有可能綠；但 runner 是 `macos-26`，字型與 engine 環境和那台開發機不是同一個。
兩種結果都是資訊：綠代表基準圖可攜，紅代表應該拿 CI 的輸出當新基準（那才是可重現的環境）。
**沒有先斬後奏去重產基準圖**，因為那會讓這個 job 第一次跑就失去它唯一的診斷價值。

## 三之二、CI 第一次跑的結果 —— 兩個都和預測相反

| job | 預測 | 實際 |
|---|---|---|
| Flutter UI - macOS | 「很可能第一次就紅在 goldens」 | **全綠** |
| Flutter UI - Windows | 沒有特別擔心 | **1 紅** |

### macOS 綠：基準圖是可攜的，紅的只有那台開發機

12 顆 golden 在 `macos-26` + Flutter 3.44.9 下全過。所以基準圖沒有綁到烤它的那台機器，
**本機的 12 紅純粹是 3.47.4 這個 SDK 造成的**，~~和硬體、字型、機器無關。~~
**就地更正（2026-10-04，#151）**：12 紅當中 9 張確實只跟 SDK 有關；但 `GbmIconButton` 的 3 張
在同為 3.47.4 時，本機 macOS 27 與 `macos-26` 仍差 6px（2/255），差異在 tofu 字形的反鋸齒邊——
字形光柵化與機器/OS 有關。見 [ledger: flutter-upgrade](2026-10-04-flutter-upgrade.md)。

這件事直接決定了上一節三個選項的去留：

- **B（重產基準圖）現在是錯的**。重產會把基準綁到 3.47.4，反而讓剛變綠的 CI 變紅。
- **A（容差 comparator）現在沒有必要**。它要換掉的那個代價（0.5% 門檻會一起吃掉
  「border-radius 改 1px」）現在換不到任何東西——CI 上根本沒有漂移要吸收。
- **C（讓它進 CI）已經做完，而且它自己就是答案**。golden 現在有主人了，
  基準圖對應的是 CI 釘的 3.44.9；開發機跑出 12 紅是本機 SDK 超前的已知結果，不是回歸。

**沒有動 goldens 一根寒毛**，這是先量後決定的直接結果——如果先斬後奏重產，會親手弄壞一個
本來就是綠的東西，而且沒有任何一層會告訴我。

### Windows 1 紅：一個只有 Windows CI 看得見的真缺陷

`2966 tests passed, 1 failed, 22 skipped`，唯一的紅是
`update_script_golden_test.dart`「the generated Windows updater matches the checked-in golden」：

```
Which: at location [77] is <10> instead of <13>
```

byte 77 是第一個換行。**根因在推測之前就先本機重現了**：

```
git show HEAD:app_flutter/test/fixtures/gbm-update.ps1.golden | python3 -c "..."
  LF blob byte77          = 10   ← generated 那一側
  CRLF-converted byte77   = 13   ← golden 在 Windows 工作區那一側
```

兩個數字和斷言完全一樣。Git for Windows 的**系統層** config 帶 `core.autocrlf=true`，
checkout 時把這個 LF 的 golden 在工作區改寫成 CRLF；而 `UpdateInstaller` 永遠輸出 `\n`。
blob 沒有被動到，所以 repo 裡看不出任何不對，其他平台也看不到。

**這個洞和 golden 一樣老。** `cq.yml` 的 `powershell-parse` job 確實在真的
`windows-latest` 上讀這個檔，但 PowerShell 不在乎 CRLF，所以它一路都是綠的。
要三 OS matrix 的**第一次跑**才會浮出來——這個 PR 開出來就是為了這個。

修法是 `.gitattributes` 加 `*.golden -text`（C5）。不用 `binary`，因為那是 `-text -diff`，
而這個 golden 是一份值得 review 的 PowerShell 腳本。不需要 `--renormalize`，
因為 blob 本來就是 LF（實測 `tr -dc '\r' | wc -c` → 0）。
新增規則 [CI-byte-compared-fixture-needs-notext]。

## 四、記錄更正

- [CI-linux-only] 標題與 Rule 劃掉重寫（三 OS matrix），保留
  `window_title_test.dart` 為何仍然存在的理由，並寫明**還沒涵蓋**的是 `integration_test/`
  與 PowerShell updater 的行為。
- [TEST-posix-fixture-on-windows-host] 的標題與第一條 Rule 就地更正——
  「`ci.yml`'s Flutter job is ubuntu-only」不再成立。
- **#69 沒有關閉**：關閉 issue 是使用者的決定（[CULT-standing-rules] 第 3 條），
  而且它的 `integration_test/` 那半仍然開著。

## 沒做／開著的

- **CI 還沒跑過。** 三個 job 全部未驗證。
- **golden 的處置未定**：本輪只是讓它有主人，A（容差 comparator）與 B（重產基準圖）
  都還在桌上，等第一次 macOS CI 的結果再決定。
- **`timeout-minutes: 25` 沿用**，沒有為 macOS 調高。ci.yml 自己的註解說這個數字對所有 job
  刻意相同、是防黑洞而非防慢跑；macOS 加上 `flutter build macos` 是否會超過 25 分鐘沒有量過。
- **macOS 的 Phase B 有無**，兩段註解互相矛盾，未裁決（見上）。
- `release.yml` 的 Linux 有一句 `mkdir -p build/native_assets/linux` 的既有 workaround，
  `ci.yml` 沒有而且一直是綠的，本輪沒有去對齊兩邊。

## 五、TSan 的紅：一個只有 sanitizer 看得見的測試缺陷

`.gitattributes` 那一推之後 Flutter 三個 job 全綠，但 Thread sanitizer 紅了 —— 而那一推
**一行 C++ 都沒動**（`git diff --name-only a2e2e6b fc9ba78` 對 `src/`、`tests/`、CMake 的
交集是空的）。同一棵樹，上一輪綠、這一輪紅。使用者裁定「這輪就診斷並修掉」。

### 走過的死路，兩條，都就地更正

1. **「`this` 是 null」** —— 錯。`~Session()` 跑到 228 行代表它走過了 `operations_->drain()`，
   那一行解參考成員；`this` 若是 null 早就炸在那裡。
2. **「是 GCC libtsan 的問題」** —— 錯，而且我為它找了兩個看似合理的理由（macOS 0/40、
   repo 自己記過 GCC 11 在 `mutex`+`condition_variable` 上的確認誤報）。推翻它的是**第二個
   sanitizer**：clang 的 ASan 也重現。

### 量出來的四個手臂

真正的錯誤訊息不是 TSan 報的，是 glibc 自己的：
`Fatal glibc error: assertion failed: mutex->__data.__owner == 0`。

| 手臂（Linux/aarch64，同源碼同容器，各 100 次） | 修法前 | 修法後 |
|---|---|---|
| 無 sanitizer | 0/100 | — |
| gcc-13 TSan | **20/100** | **0/100** |
| gcc-13 ASan | **17/100** | **0/100** |
| clang-18 ASan | **13/100** | **0/100** |
| clang-18 TSan | 0/100 | — |

四個 sanitizer 手臂三個紅、跨兩個廠商 —— 工具鏈假說就是死在這一格。

### 根因：ASan 指到了確切的一行

```
ERROR: AddressSanitizer: stack-use-after-return
  #1 operator()  CancelOperationApiTest.cpp:206    finishes.fetch_add(1)
  #6 logCallback CancelOperationApiTest.cpp:99
  #7 CallbackRegistry::emit
  #8 Session.cpp:747      submitOperation 的完成 callback
  #13 OperationRunner::workerLoop
```

`finishes` / `trippedOnFirstFinish` 是 `TestBody()` 的 stack local，hook 用 `[&]` 抓它們並存進
`log_` —— 而 `log_` 是 fixture 成員，活到 `TearDown()` 之後。`TearDown()` 的
`gbm_session_close()` 會取消所有還在佇列的 operation，每個都發 `OPERATION_FINISHED` 回到
`logCallback`，於是 hook 在死掉的 stack frame 上寫。

**寫還是輕的。** hook 會**讀**那個死掉的 `finishes` 來決定要不要呼叫
`gbm_cancel_operation(session_, 0)` —— 垃圾值讓那個分支成立，就在 `~Session()` 執行中重入一個
正在解構的 Session。glibc 的 mutex 斷言和 `~Session()` 裡的 SEGV 都是從這裡來的。症狀離原因
隔了兩層 frame 和一個 mutex 位址。

修法一行：`TearDown()` 開頭 `log_.setHook(nullptr)`，在 `gbm_session_close()` 之前。
**產品碼零改動。** 新增 [TEST-callback-hook-outlives-test-body]。

### 自己犯的三個程序錯誤，寫出來

1. **備份沒做成就往下走。** [TEST-mutation-check-every-test] 明寫「先複製到 scratchpad，絕不
   用 `git checkout --` 還原」。那個 `cp` 落在 classifier 失效的呼叫裡沒執行，我沒檢查。
   後來是從 `git show HEAD:` 取原檔（唯讀）補回來的。
2. **驗證時同時動了兩個變因** —— 新增 `detect_stack_use_after_return=1`，又把 filter 從一個
   測試換成四個，於是 `17/100 → 100/100` 這個比較毫無意義。差點讀成「修法讓情況變糟」。
   重做成同條件對照才有上表。
3. **100/100 裡一個 sanitizer 報告都沒有**，全是斷言失敗 —— 我一開始用退出碼數，把崩潰和
   斷言混在一起。後來把兩者分欄才看清楚。

### 沒做／開著的

- **`SessionCloseCancelsQueuedOperationsInsteadOfDraining` 在快機器上時序脆弱**：斷言
  `succeeded <= 1`，而這個容器跑出 `14 vs 1`（20 個 operation 有 14 個在 close 前跑完）。
  它不裝 hook，所以本輪的修法不可能造成它；CI 上也沒見過。**記錄待裁定，沒有自行調整斷言。**
- **capi 沒有擋「對正在解構的 session 再呼叫進來」**。本輪的測試是以非法方式呼叫的，但
  `gbm_capi.h` 並沒有說那不合法。要不要補一道防線是獨立決定，未裁定。
- 重現全在 **aarch64 Docker**；CI 是 x86_64。根因是 stack-use-after-return，與架構無關，
  但次數不可跨架構引用。
