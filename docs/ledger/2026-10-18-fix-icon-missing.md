# Flutter app 補回品牌 app icon

## Situation

使用者回報：從 Qt 換到 Flutter 後，產生出來的 app 沒有圖示。

查到：

- Qt 時代 `34e02289`（feat(app): add an app icon）建了 `resources/branding/app-icon.svg` 為唯一來源，`scripts/gen-app-icon.sh` 產出 PNG/.icns/.ico 並提交。
- Flutter 遷移（#32）時三個平台的接線都由樣板帶入且是正確的：macOS 的 `AppIcon.appiconset`、Windows 的 `Runner.rc`（`IDI_APP_ICON`）與 `installer/Package.wxs`（`ARPPRODUCTICON`、開始選單捷徑）。但檔案本身是 **Flutter 樣板的預設圖**——7 張 PNG 與 `app_icon.ico` 的 shasum 全部與 `resources/branding/` 不同。
- Linux runner（`my_application.cc`）從未設定視窗圖示，bundle 裡也沒有圖檔。

## Task

讓 macOS / Windows / Linux 的 Flutter build 都帶品牌圖示，並防止再次漂移。

## Action

```
resources/branding/app-icon.svg
   │ scripts/gen-app-icon.sh
   ├─▶ resources/branding/*      (Qt 時代既有)
   └─▶ 新增同步：
        macos  AppIcon.appiconset/app_icon_{16..1024}.png
        windows runner/resources/app_icon.ico  (Runner.rc + MSI 共用)
        linux  CMake install app-icon-256.png → bundle/data/app_icon.png
               my_application.cc：/proc/self/exe 目錄 + data/app_icon.png → gtk_window_set_icon_from_file
```

1. `test:` `scripts/check-app-icon-sync.py`——byte 比對 8 個檔案，並 grep Linux CMake／runner 的接線。先跑：10 項紅。
2. `fix:` 複製品牌 PNG/.ico 到 Flutter runner；`gen-app-icon.sh` 尾端加同步段。只執行了同步段的 `cp`（本輪沒有重跑整支腳本，避免本機 rsvg-convert 版本不同而改寫 `resources/branding/` 的既有產物）。剩 Linux 2 項紅。
3. `fix(linux):` CMake install + runner 設圖示。全綠。
4. `ci:` `cq.yml` lint job 執行檢查腳本。

Mutation（備份到 scratchpad 後還原）：跑 2 個、紅 2 項——把 `app_icon_64.png` 換回樣板圖只紅那一行；把 runner 的 `gtk_window_set_icon_from_file` 改名只紅那一行。

## Result

- 檢查腳本綠。`flutter build macos --debug`（本機 Flutter 3.47.7）成功；`.app/Contents/Resources/AppIcon.icns` 以 `iconutil -c iconset` 拆開，`icon_128x128@2x.png` 目視為藍底白色 git-branch 品牌圖。
- Linux 的 C++ 變更本機（macOS）無法編譯，由 CI 的 Linux Flutter build 驗證。Windows 只換了 .ico 檔，接線未動。
- Linux 檢查是字串 grep，只證明接線存在，不證明執行時載入成功；載入失敗時 runner 只記 `g_warning`。
