#!/usr/bin/env python3
"""app_flutter 各平台的 app icon 必須與 resources/branding/ 產出的品牌圖 byte 相等。

resources/branding/app-icon.svg 是唯一來源，scripts/gen-app-icon.sh 產出並同步；
Flutter 樣板自帶的預設圖示一旦沒被覆蓋，build 出來的 app 就沒有品牌圖示。
"""
import filecmp, sys

BRANDING = 'resources/branding'
MAC_SET = 'app_flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset'

pairs = [(f'{BRANDING}/app-icon-{s}.png', f'{MAC_SET}/app_icon_{s}.png')
         for s in (16, 32, 64, 128, 256, 512, 1024)]
# Runner.rc 與 installer/Package.wxs 都讀這一個 .ico
pairs.append((f'{BRANDING}/app-icon.ico', 'app_flutter/windows/runner/resources/app_icon.ico'))

problems = []
for src, dst in pairs:
    try:
        if not filecmp.cmp(src, dst, shallow=False):
            problems.append(f'{dst} differs from {src}')
    except FileNotFoundError as e:
        problems.append(f'missing: {e.filename}')

# Linux 沒有 bundle 圖示機制：CMake 把 PNG 裝進 bundle，runner 在啟動時設給視窗
linux_checks = [
    ('app_flutter/linux/CMakeLists.txt', 'app-icon-256.png'),
    ('app_flutter/linux/runner/my_application.cc', 'gtk_window_set_icon_from_file'),
]
for path, needle in linux_checks:
    if needle not in open(path, encoding='utf-8').read():
        problems.append(f'{path} does not mention {needle}')

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
