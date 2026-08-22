
const PAGES = [
  { id: 'p1', num: '01', label: '平台與視窗架構' , title: '平台與視窗架構', intent: '三平台統一樣式，只有 menu bar 位置與標題列跟隨系統' },
  { id: 'p2', num: '02', label: '主視窗 — History', title: '主視窗 — History', intent: 'commit description 的主要閱讀位置' },
  { id: 'p3', num: '03', label: '主視窗 — Working Copy', title: '主視窗 — Working Copy', intent: '暫存、逐行 stage、撰寫 commit description' },
  { id: 'p4', num: '04', label: 'Menu bar 與快捷鍵', title: 'Menu bar 與快捷鍵全表', intent: '每個動作的選單路徑與 shortcut' },
  { id: 'p5', num: '05', label: 'Context menu 各層級', title: 'Context menu — 9 種目標、兩層', intent: '右鍵選單的層級與內容' },
  { id: 'p6', num: '06', label: 'Dialogs', title: 'Dialogs', intent: 'Repository settings 由中央面板改為 dialog' },
  { id: 'p7', num: '07', label: 'Clean 與 Conflict', title: 'Clean 與 Conflict 狀態', intent: '兩種狀態下 UI 與可用操作的差異' },
  { id: 'p8', num: '08', label: 'Conflict 解決視窗', title: 'Conflict 解決視窗（獨立 window）', intent: '檔案清單 + 左 / 結果 / 右 三欄，拖曳與點行套用' },
  { id: 'p9', num: '09', label: '分割線與縮放', title: '分割線與面板縮放', intent: '每條 splitter 的預設、下限與記憶行為' },
  { id: 'p10', num: '10', label: 'Log 與背景狀態', title: 'Log 與背景狀態', intent: '長時間作業的進度、取消、錯誤與可稽核的指令紀錄' },
  { id: 'p11', num: '11', label: 'Preferences', title: 'Preferences', intent: 'repository 來源資料夾、自動掃描與手動開啟紀錄' },
  { id: 'p12', num: '12', label: '看變更與比較', title: '看變更與比較', intent: 'commit / stash 的變更檢視，以及四種 ref 的 compare' },
  { id: 'p13', num: '13', label: 'Rename 與多選', title: 'Branch rename dialog 與多選', intent: '260820 新增 — 分支更名，以及 branch / commit 多選的選取與動作規則', tag: 'NEW' },
  { id: 'p14', num: '14', label: '進階功能入口 IA', title: '進階功能的入口與載體', intent: '260820 新增 — 24 個已出貨畫面該當分頁、dialog 還是抽屜，以及怎麼到得了', tag: 'NEW' },
  { id: 'p15', num: '15', label: '空狀態與錯誤視窗', title: '空狀態與錯誤視窗', intent: '260820 新增 — 沒開 repo 時的畫面，以及 P10 錯誤規則的實際版面', tag: 'NEW' },
  { id: 'p16', num: '16', label: '260820 規格修訂', title: '260820 規格修訂與待決項', intent: '這一轪改了哪些行、為何這樣決，以及還欠誰拍桁的事', tag: 'NEW' },
  { id: 'p17', num: '17', label: 'Dialog 版面 — 流程類', title: 'Dialog 版面 — 流程類（12）', intent: '共用外殼套到每一個：Checkout / Merge / Rebase 及其餘日常流程', tag: 'NEW' },
  { id: 'p18', num: '18', label: 'Dialog 版面 — 修復類', title: 'Dialog 版面 — 修復與確認類（8）', intent: 'reset / cherry-pick / clean / 憑証 / 兩種 recovery', tag: 'NEW' },
  { id: 'p19', num: '19', label: '管理面板樣版', title: '管理面板樣版（12 個共用一張）', intent: 'manage-worktrees 為實例，其餘 11 個只換欄位不換造型', tag: 'NEW' },
  { id: 'p20', num: '20', label: '未實作功能', title: '未實作功能的預先版面（3）', intent: 'New repository、Open file at this revision、Save this revision as…', tag: 'NEW' },
  { id: 'p21', num: '21', label: 'Pull 流程與錯誤', title: 'Pull 流程與錯誤', intent: '一鍵 pull 的四段式過程、三種套用方式，以及六種失敗各自接到哪裡', tag: 'NEW' },
];

const PULLSTEPS = [
  { n: '1', t: 'Fetch', d: '先取得 remote 的新 ref。這一段不改工作區，可以安全取消，取消不留半完成狀態。', s: '可取消' },
  { n: '2', t: '判定', d: '比對 local 與 upstream：已是最新就結束；只落後則 fast-forward；分岔則按設定的套用方式走。', s: '瞬間' },
  { n: '3', t: '套用', d: 'merge / rebase / ff-only 三種之一。這一段會改工作區，衝突時進入 sequencer 狀態（P7）。', s: '可 abort' },
  { n: '4', t: '回報', d: '狀態列寫出實際結果：「Fast-forward 4 commits · 12 個檔案 · 412 ms」。已是最新也要寫。', s: '不彈窗' },
];

const PULLERR = [
  { e: '沒有 upstream', when: '第 2 段', ui: 'Dialog — Set upstream', act: '預選同名的遠端分支，設完自動繼續原本的 pull' },
  { e: '工作區有會被覆蓋的未提交變更', when: '第 3 段前', ui: 'Dialog — Pull blocked', act: 'Stash and pull（主）、Discard and pull（danger）、Cancel' },
  { e: '套用時衝突', when: '第 3 段', ui: '不彈窗 — 進入 sequencer 狀態', act: '頂部 banner：「Merge in progress — 3 個檔案衝突」+ Resolve / Abort' },
  { e: 'ff-only 但分支已分岔', when: '第 2 段', ui: '錯誤視窗', act: '主按鈕 Pull with rebase，次按鈕 Pull with merge — 不只說失敗' },
  { e: '需要認証 / 憑証過期', when: '第 1 段', ui: 'Dialog — Sign in to origin', act: '登入成功後自動重試同一次 pull，不要使用者重按' },
  { e: 'Remote 不可達 / 逾時', when: '第 1 段', ui: '錯誤視窗', act: '主按鈕 Retry；附 git 原始輸出與耗時；同錯誤累加 ×N' },
];

const DLGS = [
  { grp: 'C', name: 'Checkout', key: 'Ctrl/Cmd+Shift+O', primary: 'Checkout', f: [
    { k: 'focus', label: '目標', v: 'release/0.5', mono: true, hint: '可搜尋的混合清單：branch / tag / commit，以圖示區分' },
    { k: 'ro', label: '目前', v: 'main · 有25 項未提交變更', mono: true },
    { k: 'radio-on', v: '帶著變更切過去' },
    { k: 'radio', v: '先 stash，切完不自動還原' },
    { k: 'warn', v: '兩邊都改到的檔案會阻止 checkout；屆時列出檔名並提供「stash 後重試」。' } ] },
  { grp: 'C', name: 'Merge into current', key: 'Ctrl/Cmd+Shift+M', primary: 'Merge', f: [
    { k: 'focus', label: '來源分支', v: 'feature/lane-allocator', mono: true },
    { k: 'ro', label: '合入', v: 'main · 落後 4 個 commit', mono: true },
    { k: 'radio-on', v: 'Merge commit（保留分支形狀）' },
    { k: 'radio', v: 'Fast-forward 可行時不建 commit' },
    { k: 'radio', v: 'Squash 成一筆' },
    { k: 'text', label: 'Commit 訊息', v: "Merge branch 'feature/lane-allocator'", mono: true, hint: 'squash 時改為多行欄位並帶入來源 commit 摘要' },
    { k: 'note', v: '預告：可能衝突的 3 個檔案（點展開看檔名）。' } ] },
  { grp: 'C', name: 'Rebase onto', key: 'Ctrl/Cmd+Shift+R', primary: 'Rebase', f: [
    { k: 'ro', label: '重新安置', v: 'feature/lane-allocator · 6 commits', mono: true },
    { k: 'focus', label: '基於', v: 'origin/main', mono: true },
    { k: 'chk-on', v: '保留 merge commit（--rebase-merges）' },
    { k: 'chk', v: '自動 squash 標記過的 fixup commit' },
    { k: 'note', v: '衝突時停在第幾步、已套用幾筆，由 P7 的 sequencer 標記列接手。' },
    { k: 'warn', v: '此分支已 push。rebase 後需 force push，共作者需重新對齊。' } ] },
  { grp: 'C', name: 'New branch', key: 'Ctrl/Cmd+Shift+B', primary: 'Create branch', f: [
    { k: 'focus', label: '名稱', v: 'feature/', mono: true, hint: '驗證與 P13 rename 完全一致' },
    { k: 'text', label: '從哪裡分出', v: 'main', mono: true },
    { k: 'chk-on', v: '建立後直接 checkout' },
    { k: 'chk', v: '同時 push 並設為 upstream' } ] },
  { grp: 'C', name: 'Clone repository', key: 'Ctrl/Cmd+Shift+N', primary: 'Clone', f: [
    { k: 'focus', label: 'URL', v: 'git@github.com:Staler2019/git-branch-manager.git', mono: true },
    { k: 'text', label: '目標路徑', v: '~/src/git-branch-manager', mono: true, hint: 'URL 貼上後自動帶出資料夾名，可手改' },
    { k: 'chk-on', v: '一併 clone submodule' },
    { k: 'chk', v: '浅層 clone（--depth 1）' },
    { k: 'note', v: '進行中不卡 dialog：進度走 P10 背景作業列，完成後自動開啟。' } ] },
  { grp: 'C', name: 'Stash changes', key: 'Ctrl/Cmd+Shift+S', primary: 'Stash 9 files', f: [
    { k: 'focus', label: '訊息', v: 'WIP lane allocator', hint: '空白時使用預設的 WIP on <branch>' },
    { k: 'radio-on', v: '所有未提交的變更（9 個檔案）' },
    { k: 'radio', v: '只收起選取的 3 個檔案' },
    { k: 'list', label: '選取的檔案（逐項可取消）', v: 'lib/graph/lane_allocator.dart  −42\nlib/ui/tab_row.dart  +8 −3\ntest/graph_test.dart  +15', mono: true, hint: '選「所有」時此清單調暗但不消失，選項差別看得見' },
    { k: 'chk', v: '包含 untracked 檔案（3）' },
    { k: 'chk', v: '保留已 stage 的內容在工作區' },
    { k: 'note', v: '預設隨入口決定：從 Branch 選單 / 快捷鍵進來是「所有」；從檔案右鍵 Stash 進來是「選取的 N 個」。untracked 預設不勾 — 它們不在 git 的視野裡，要一併收起得明確表示；選取清單中的 untracked 檔案會標 U，勾了這欄才算進來。主按鈕寫出實際數量，切換選項時跟著改。' } ] },
  { grp: 'C', name: 'Force push', key: '', danger: true, primary: 'Force push', f: [
    { k: 'ro', label: '推送', v: 'feature/lane-allocator → origin', mono: true },
    { k: 'warn', v: '遠端有 4 個本地沒有的 commit，這些紀錄會消失。下方列出它們的 hash 與作者。' },
    { k: 'chk', v: '使用 --force-with-lease（遠端有新變動就中止）' },
    { k: 'note', v: '主按鈕為 danger 且必須複述分支名。所有勾選欄預設均不勾選 — force push 這種動作不幫使用者預設任何選項，要什麼行為自己勾。' } ] },
  { grp: 'C', name: 'Delete remote branch', key: '', danger: true, primary: 'Delete on origin', f: [
    { k: 'ro', label: '刪除', v: 'origin/wip/askpass', mono: true },
    { k: 'chk-on', v: '同時刪除本地分支 wip/askpass' },
    { k: 'warn', v: '其他人的 tracking branch 會變成 gone。此分支有 2 個未合入任何分支的 commit。' } ] },
  { grp: 'C', name: 'Prune remote branches', key: '', primary: 'Prune 5 refs', f: [
    { k: 'ro', label: 'Remote', v: 'origin', mono: true },
    { k: 'list', label: '將清除的 tracking ref', v: 'origin/feature/old-graph\norigin/wip/qt-theme\norigin/release/0.3', mono: true, hint: '逐項可取消勾選；不會動到任何本地分支' },
    { k: 'note', v: '只清遠端已不存在的 tracking ref，不是刪遠端分支 — 標題列下方一行寫明這件事。' } ] },
  { grp: 'C', name: 'Restore file to this state', key: '', danger: true, primary: 'Restore file', f: [
    { k: 'ro', label: '檔案', v: 'lib/graph/lane_allocator.dart', mono: true },
    { k: 'ro', label: '還原成', v: 'a1b2c3d · 2026-08-14 11:20 · Fix lane allocator overflow', mono: true },
    { k: 'warn', v: '此檔目前有未提交的 42 行變更，會被覆蓋且無法復原。' },
    { k: 'chk', v: '還原前先 stash 目前的變更' },
    { k: 'note', v: '與下一張成對：本張取 commit 本身的內容（a1b2c3d 之後）。' } ] },
  { grp: 'C', name: 'Restore file to before this state', key: '', danger: true, primary: 'Restore file', f: [
    { k: 'ro', label: '檔案', v: 'lib/graph/lane_allocator.dart', mono: true },
    { k: 'ro', label: '還原成', v: '4b8f01c（a1b2c3d 的前一筆）· 2026-08-14 09:02', mono: true, hint: '等於抵消 a1b2c3d 對這一檔做的改動，不碰其他檔案' },
    { k: 'ro', label: '將抵消的改動', v: '+18 −7（可展開看 diff）', mono: true },
    { k: 'warn', v: '此檔目前有未提交的 42 行變更，會被覆蓋且無法復原。' },
    { k: 'chk', v: '還原前先 stash 目前的變更' },
    { k: 'note', v: '入口在 commit 明細的檔案右鍵，與上一張相鄰並列，標題是兩張唯一的區別 — 所以「還原成」那一行必須寫出實際 hash 與日期，不能只寫「前一版」。merge commit 或首筆 commit 沒有單一父節點時此項 disabled。不建 revert commit，只改工作區。' } ] },
  { grp: 'C', name: 'Discard changes', key: '', danger: true, primary: 'Discard 3 files', f: [
    { k: 'list', label: '丟掉這些變更', v: 'lib/graph/lane_allocator.dart  −42\nlib/ui/tab_row.dart  +8 −3\ntest/graph_test.dart  +15', mono: true },
    { k: 'warn', v: '這些變更不進 stash、也不在 reflog，丟掉就沒了。' },
    { k: 'note', v: '主按鈕寫出實際數量；兩個檔案以下改成寫檔名。' } ] },

  { grp: 'B2', name: 'Reset branch', key: '', danger: true, primary: 'Reset to a1b2c3d', f: [
    { k: 'ro', label: '分支', v: 'feature/lane-allocator → a1b2c3d', mono: true },
    { k: 'radio-on', v: 'Mixed — 保留檔案，取消 stage' },
    { k: 'radio', v: 'Soft — 保留檔案與 stage' },
    { k: 'radio', v: 'Hard — 丟掉檔案變更' },
    { k: 'warn', v: '選 Hard 時這行才出現：將丟掉 9 個檔案的未提交變更；主按鈕同步轉為 danger。' } ] },
  { grp: 'B2', name: 'Cherry-pick', key: '', primary: 'Cherry-pick 4 commits', f: [
    { k: 'list', label: '套用這些 commit（依序）', v: 'a1b2c3d  Fix lane allocator overflow\n9d02f4e  Cache graph rows per repo\n2e6a7bd  Side-by-side conflict view', mono: true },
    { k: 'ro', label: '套到', v: 'main（目前分支）', mono: true },
    { k: 'chk', v: '不自動 commit（-n，套完停在工作區）' },
    { k: 'chk-on', v: '在訊息附上來源 hash' },
    { k: 'note', v: '只接連續選取（P13）。衝突時進 sequencer 狀態，可逐筆 skip。' } ] },
  { grp: 'B2', name: 'Create tag', key: '', primary: 'Create tag', f: [
    { k: 'focus', label: '名稱', v: 'v0.6.0', mono: true },
    { k: 'ro', label: '指向', v: 'a1b2c3d · Fix lane allocator overflow', mono: true },
    { k: 'radio-on', v: 'Annotated（有作者與訊息）' },
    { k: 'radio', v: 'Lightweight' },
    { k: 'text', label: '訊息', v: 'Release 0.6.0', hint: 'lightweight 時此欄停用並調暗，不消失' },
    { k: 'chk', v: '建立後 push 到 origin' } ] },
  { grp: 'B2', name: 'Clean untracked files', key: '', danger: true, primary: 'Delete 12 files', f: [
    { k: 'list', label: '將刪除（逐項可取消）', v: 'build/  · 8 個檔案 · 142 MB\n.dart_tool/  · 3 個檔案\nnotes.txt  · 2 KB', mono: true },
    { k: 'chk', v: '包含被 gitignore 忽略的檔案（-x）' },
    { k: 'chk', v: '包含目錄（-d）' },
    { k: 'warn', v: '這是 git clean，直接從磁碟刪檔，不進回收筒。合計 142 MB。' } ] },
  { grp: 'B2', name: 'Undo last operation', key: 'Ctrl/Cmd+Z', primary: 'Undo commit', f: [
    { k: 'ro', label: '上一個動作', v: 'Commit · a1b2c3d · 2 分鐘前', mono: true },
    { k: 'note', v: '將把 HEAD 退回 4b8f01c，檔案變更回到已 stage 的狀態。' },
    { k: 'ro', label: '實際執行', v: 'git reset --soft HEAD~1', mono: true },
    { k: 'note', v: '只能退一步，且只退得回 reflog 記得的動作；不可退的動作在選單就 disabled 並寫出原因。' } ] },
  { grp: 'B2', name: 'Sign in to origin', key: '', primary: 'Sign in', f: [
    { k: 'ro', label: 'Remote', v: 'origin · github.com', mono: true },
    { k: 'note', v: 'Fetch 被拒：憑証已過期或不存在。' },
    { k: 'focus', label: '帳號', v: 'staler2019' },
    { k: 'text', label: 'Token / 密碼', v: '••••••••••••', hint: '欄位內容不進 log，寫入前以 •••• 取代' },
    { k: 'chk-on', v: '存進系統金鑰圈' },
    { k: 'note', v: '不在主畫面做 inline 登入；這是阿鐵層 dialog，因為可能從任何 remote 動作彈出。' } ] },
  { grp: 'B2', name: 'Checkout blocked', key: '', primary: 'Stash and checkout', f: [
    { k: 'ro', label: '想切到', v: 'release/0.5', mono: true },
    { k: 'list', label: '阻止的檔案（兩邊都改了）', v: 'lib/graph/lane_allocator.dart\nlib/ui/tab_row.dart', mono: true },
    { k: 'note', v: '三個選項都給：Stash and checkout（主）、Discard and checkout（danger）、Cancel。不只跟使用者說「失敗」。' } ] },
  { grp: 'B2', name: 'Deleted branch recovery', key: '', primary: 'Restore branch', f: [
    { k: 'ro', label: '剛刪除', v: 'wip/askpass · 指向 c71ba90', mono: true },
    { k: 'note', v: 'commit 仍在 reflog，可以原名建回。這張 dialog 在刪除後以 undo 形式提供，不是事前再問一次。' },
    { k: 'text', label: '建回的名稱', v: 'wip/askpass', mono: true },
    { k: 'note', v: '這一張只在 30 秒内可從 status bar 點回來；之後要從 Tools → Reflog 面板找。' } ] },

  { grp: 'F', name: 'New repository', key: 'Ctrl/Cmd+N', primary: 'Create repository', f: [
    { k: 'focus', label: '名稱', v: 'graph-bench' },
    { k: 'text', label: '位置', v: '~/src', mono: true, hint: '預設為 Preferences 的第一個來源資料夾' },
    { k: 'text', label: '預設分支名', v: 'main', mono: true },
    { k: 'chk-on', v: '建立 .gitignore（從全域範本）' },
    { k: 'chk', v: '建立第一筆空 commit' } ] },
  { grp: 'F', name: 'Open file at this revision', key: '', primary: 'Open', f: [
    { k: 'ro', label: '檔案', v: 'lib/graph/lane_allocator.dart', mono: true },
    { k: 'ro', label: '版本', v: 'a1b2c3d · 2026-08-14 11:20', mono: true },
    { k: 'radio-on', v: '在新分頁以唯讀開啟' },
    { k: 'radio', v: '以外部編輯器開啟暫存檔' },
    { k: 'note', v: '需 capi 的 blob 讀取；尚未實作。唯讀分頁沒有 stage / 編輯欄，只有行號與語法上色。' } ] },
  { grp: 'F', name: 'Save this revision as', key: '', primary: 'Save', f: [
    { k: 'ro', label: '來源', v: 'lane_allocator.dart @ a1b2c3d', mono: true },
    { k: 'focus', label: '存成', v: '~/Desktop/lane_allocator.a1b2c3d.dart', mono: true, hint: '預設檔名帶 hash，避免與工作區的檔混掉' },
    { k: 'note', v: '寫到工作區內的路徑時額外確認一次（會變成 untracked 檔）。' } ] },

  { grp: 'PULL', name: 'Pull', key: 'Ctrl/Cmd+Shift+P', primary: 'Pull', f: [
    { k: 'ro', label: '從', v: 'origin/main → main · 落後 4、領先 2', mono: true },
    { k: 'radio-on', v: 'Rebase 本地 commit 到遠端之上' },
    { k: 'radio', v: 'Merge（建一筆 merge commit）' },
    { k: 'radio', v: 'Fast-forward only（分岔就中止）' },
    { k: 'chk', v: '順便 prune 已消失的遠端分支' },
    { k: 'note', v: '這張預設不出現 — 工具列的 Pull 直接用 Preferences 的預設套用方式走。只有選單的 Pull… 或 Alt + 點工具列才開。' } ] },
  { grp: 'PULL', name: 'Set upstream', key: '', primary: 'Set upstream and pull', f: [
    { k: 'ro', label: '分支', v: 'feature/lane-allocator（尚未設 upstream）', mono: true },
    { k: 'focus', label: '跟蹤', v: 'origin/feature/lane-allocator', mono: true, hint: '同名的遠端分支自動預選；不存在時主按鈕改為 Push and set upstream' },
    { k: 'chk-on', v: '之後此分支都記住這個設定' },
    { k: 'note', v: '接在 pull 第 2 段失敗後自動彈出；設完直接繼續原本的 pull。' } ] },
  { grp: 'PULL', name: 'Pull blocked', key: '', primary: 'Stash and pull', f: [
    { k: 'list', label: '這些檔案兩邊都改了', v: 'lib/graph/lane_allocator.dart\nlib/ui/tab_row.dart', mono: true },
    { k: 'note', v: '遠端的 4 個 commit 會碰到這 2 個檔案，而它們有未提交的變更。' },
    { k: 'chk-on', v: 'pull 完自動還原 stash（衝突時保留在 stash 不弄丟）' },
    { k: 'note', v: '三個出口都給：Stash and pull（主）、Discard and pull（danger）、Cancel。與 P18 Checkout blocked 同型。' } ] },
];

const WTS = [
  { name: 'git-branch-manager', path: '~/src/git-branch-manager', br: 'main', sel: true, cur: true },
  { name: 'gbm-0.5', path: '~/src/wt/gbm-0.5', br: 'release/0.5' },
  { name: 'gbm-bisect', path: '~/src/wt/gbm-bisect', br: 'HEAD 分離', warn: true },
  { name: 'gbm-lfs', path: '~/wt/gbm-lfs', br: 'feature/lfs', gone: true },
];

const PANELSPEC = [
  { p: 'manage-worktrees', list: 'worktree 名稱 + 分支 + 狀態', detail: '路徑、HEAD、待提交數、鎖定原因', bar: 'Add、Prune、Open、Remove' },
  { p: 'manage-stashes', list: 'stash 編號 + 訊息 + 時間', detail: '檔案清單 + diff（唯讀）', bar: 'Apply、Pop、Drop、Create' },
  { p: 'manage-remotes', list: 'remote 名稱 + URL', detail: 'fetch / push URL、tracking ref 數、最後 fetch', bar: 'Add、Edit、Prune、Remove' },
  { p: 'manage-submodules', list: '路徑 + 目前 commit', detail: 'URL、預期 vs 實際 commit、是否初始化', bar: 'Init、Update、Sync、Open' },
  { p: 'manage-lfs', list: '追蹤型別 + 檔數 + 大小', detail: '對應檔案、本地快取狀態', bar: 'Track、Untrack、Fetch、Prune' },
  { p: 'patches', list: '.patch 檔或待建清單', detail: 'patch 內容 diff 預覽', bar: 'Create from commits、Apply…、Save as' },
  { p: 'interactive-rebase', list: 'commit 序列（可拖曳排序）', detail: '每筆的動作（pick / squash / drop）與訊息編輯', bar: 'Start、Abort、Reset order' },
  { p: 'bisect', list: '已標記的 good / bad 步驟', detail: '目前待測 commit、剩餘步數、自訂測試指令', bar: 'Good、Bad、Skip、Reset' },
  { p: 'reflog', list: 'reflog 項目（時間 + 動作）', detail: '該 commit 的明細與可回得的 ref', bar: 'Restore branch、Checkout、Copy SHA' },
  { p: 'blame', list: '檔案內容（每行帶作者）', detail: '選到的行對應的 commit 明細', bar: '上一版、忽略空白、跳到 commit' },
  { p: 'file-history', list: '該檔的 commit 清單', detail: '逐版 diff（唯讀）', bar: '欄位選擇器、含重命名、Compare' },
  { p: 'line-history', list: '選定行區的演化', detail: '每一步的前後對照', bar: '擴大行區、跳到 commit' },
];

const IAMAP = [
  { grp: '大型管理面板（12）', items: 'manage-stashes / worktrees / remotes / submodules / lfs、patches、interactive-rebase、bisect、reflog、blame、file-history、line-history', to: '分頁（與 History / Working copy / Compare 同一條分頁列）', why: '有工具列 + 清單 + 明細的畫面不適合 modal：使用者需要邊看圖邊操作，且要能同時開兩個' },
  { grp: '中型表單 / 確認框（8）', items: 'reset-branch、cherry-pick、create-tag、clean-untracked、undo-last、credential、checkout-recovery、delete-branch-recovery', to: 'Dialog（沒例外套 P6 共用外殼）', why: '一次決定、做完就走，遡到底不超過五個欄位' },
  { grp: 'operation-log', items: 'operation-log dialog', to: '刪除 — 改走 P10 底部抽屜', why: '同一份資料兩套介面，抽屜已實作且符合規格' },
  { grp: '應用層（3）', items: 'about、keyboard-shortcuts、manage-base-folders', to: 'Dialog（app-wide，不綁 repo）', why: 'manage-base-folders 已在 P11 Preferences 裡，只需能單獨開' },
];

const TOOLSMENU = [
  { label: 'Stashes…', note: '分頁' },
  { label: 'Worktrees…', note: '分頁' },
  { label: 'Remotes…', note: '分頁' },
  { label: 'Submodules…', note: '分頁' },
  { label: 'Large files (LFS)…', note: '分頁' },
  { label: 'Patches…', note: '分頁' },
  { label: 'Reflog…', note: '分頁' },
  { label: 'Rewrite history', note: '', submenu: true },
];

const TOOLSSUB = [
  { label: 'Interactive rebase…' },
  { label: 'Bisect…' },
  { label: 'Clean untracked files…', danger: true },
];

const FILECTX = [
  { label: 'Open diff', note: '' },
  { label: 'Stage / Unstage', note: '' },
  { label: 'Discard changes…', note: '', danger: true },
  { label: 'Ignore', note: '', submenu: true },
  { label: 'History', note: '', submenu: true, hi: true },
  { label: 'Copy path', note: '' },
  { label: 'Reveal in Finder', note: '' },
  { label: 'Open in terminal', note: '' },
];

const FILECTXSUB = [
  { label: 'File history…' },
  { label: 'Blame…' },
  { label: 'Line history…', note: '選行後' },
];

const WELCOME = [
  { label: 'Open repository…', key: 'Ctrl/Cmd+O', primary: true },
  { label: 'Clone repository…', key: 'Ctrl/Cmd+Shift+N' },
  { label: 'New repository…', key: 'Ctrl/Cmd+N' },
];

const RECENTS = [
  { name: 'git-branch-manager', path: '~/src/git-branch-manager', meta: 'main · 2 小時前' },
  { name: 'linux', path: '~/src/kernel/linux', meta: 'master · 昨天' },
  { name: 'chromium', path: '~/work/chromium/src', meta: 'main · 3 天前' },
];

const REVISIONS = [
  { area: 'Shortcut', was: 'Ctrl/Cmd+Shift+F 同時給 Find in files 與 Repository → Fetch', now: 'Fetch 保留 Shift+F（工具列 F / P / P 三顆同組，不能拆）；Find in files 改 Ctrl/Cmd+Shift+H' },
  { area: 'Shortcut', was: 'Ctrl/Cmd+Shift+T 同時給 File list as tree 與 Stash changes', now: 'tree 切換保留 Shift+T（View 選單的 toggle 家族）；Stash changes 改 Ctrl/Cmd+Shift+S' },
  { area: 'MENUS 表', was: 'Repository → Stage selected lines 只在 P3 內文，沒進表', now: '已加入 Repository 選單，快捷鍵 Ctrl/Cmd+Alt+S' },
  { area: 'MENUS 表', was: 'Rename current branch… 無快捷鍵；Edit 無 Select all', now: 'Branch → Rename branch… = F2；Edit → Select all = Ctrl/Cmd+A（搭 P13 多選）' },
  { area: 'Log', was: 'LOGRULES 寫 2,000 筆，程式是 500', now: '預設 500，Preferences 可調到 2,000；上限候選值顯示在畫面上' },
  { area: 'Log', was: 'Log 有底部抽屜與 operation-log dialog 兩套', now: '只留抽屜；operation-log dialog 從規格中刪除（LOGRULES 新增「只有一套」一列）' },
];

const OPENQ = [
  { q: '自訂標題列要不要做？', d: 'P1 畫了 Windows / Linux 自繪標題列，程式端沒做。建議前者降級為選項：先用系統標題列，規格標注「後期選配」，避免主畫面被一個依賴卡住。' },
  { q: '管理面板走分頁這件事認不認？', d: '改成分頁後，這 12 個畫面的造形就不用各自發明：一律是〈工具列 + 左清單 + 右明細〉，與 P12 Compare 同型。不認的話我就回頭畫 12 個各自的 dialog。' },
  { q: '滿出選單（tab_row 18 項）何時拆？', d: '新的 Tools 選單 + file context menu 的 History flyout 上線後就可以拆。拆之前兩套入口並存不算違規，但標籤要先改成 sentence case。' },
  { q: '還要我畫哪些？', d: 'Tier C 的 Checkout / Merge / Rebase 欄位較多，有共用外殼但沒版面；可以接著畫。Tier B-1 的 12 個面板可以先畫一個樣版（建議 manage-worktrees）當其他畫面的模板。' },
];

const RENAMEVALID = [
  { case: '名稱重複', act: '輸入框轉紅，下方寫「已存在 feature/x」，Rename disabled' },
  { case: '含 git 不允許的字元', act: '即時標出違規字元（空白、~ ^ : ? * [ \\、結尾 .lock）' },
  { case: '空白或未改動', act: 'Rename disabled，不出現錯誤紅字' },
  { case: '有 upstream 但未勾遠端更名', act: '下方 hint：「新分支不會有 upstream，之後需重新 push -u」' },
  { case: '分支正在被 rebase / merge 佔用', act: '整個 dialog 不開啟，改出提示「先完成或中止進行中的作業」' },
];

const MULTIKEYS = [
  { key: '單擊', act: '只選這一項，anchor 移到這一項' },
  { key: 'Shift + 單擊', act: 'anchor 到此項的連續範圍' },
  { key: 'Ctrl / Cmd + 單擊', act: '切換單項，anchor 移到此項' },
  { key: 'Shift + ↑ / ↓', act: '以鍵盤延伸範圍' },
  { key: 'Ctrl / Cmd + A', act: '全選當前清單' },
  { key: 'Esc', act: '縮回單選（保留 anchor 項）' },
  { key: '右鍵已選項', act: '不改 selection，選單標題顯示數量' },
  { key: '拖曳', act: '多選不支援拖曳（避免誤拖 3 個分支），停用' },
];

const MULTIACTS = [
  { obj: 'Branch', act: 'Delete', behav: '支援 — 確認 dialog 逐項列名稱與未 push commit 數', ok: true },
  { obj: 'Branch', act: 'Push / Fetch', behav: '支援 — 依序執行，失敗項不中斷其餘', ok: true },
  { obj: 'Branch', act: 'Rename / Checkout / Set upstream', behav: 'disabled — 單項專屬，tooltip：「只能對單一分支執行」', ok: false },
  { obj: 'Commit', act: 'Copy SHA', behav: '支援 — 每行一個 hash 複製' },
  { obj: 'Commit', act: 'Cherry-pick / Revert / Squash', behav: '僅連續範圍可用，不連續時 disabled', ok: true },
  { obj: 'Commit', act: 'Reset here / Create tag / Create branch', behav: 'disabled — 需要單一目標 commit', ok: false },
  { obj: 'File', act: 'Stage / Unstage / Discard', behav: '支援 — 這是工作區最常用的多選' },
  { obj: 'File', act: 'Open diff / Open in terminal', behav: 'disabled — 一次只能開一份 diff', ok: false },
  { obj: 'Stash', act: 'Drop', behav: '支援；Apply / Pop 為單項專屬，多選 disabled' },
];

const MULTIBRANCHMENU = [
  { label: 'Fetch', note: '3' },
  { label: 'Push', note: '3' },
  { label: 'Checkout', note: '單項', dis: true },
  { label: 'Rename…', note: '單項', dis: true },
  { label: 'Set upstream…', note: '單項', dis: true },
  { label: 'Copy branch names', note: '3' },
  { label: 'Delete 3 branches…', note: '', danger: true },
];

const MULTICOMMITS = [
  { msg: 'Add askpass helper', sha: '4b8f01c', lane: 1 },
  { msg: 'Fix lane allocator overflow', sha: 'a1b2c3d', lane: 1, sel: true },
  { msg: 'Cache graph rows per repo', sha: '9d02f4e', lane: 1, sel: true },
  { msg: 'Side-by-side conflict view', sha: '2e6a7bd', lane: 3, sel: true },
  { msg: 'Bump libgit2 to 1.8.1', sha: 'c71ba90', lane: 1, sel: true, anchor: true },
  { msg: 'Initial worktree support', sha: '5f9e213', lane: 2 },
];

const BRANCH_TREE = [
  { name: 'main', icon: 'git-branch', state: 'synced', badge: '↑2', depth: 0, current: true },
  { name: 'feature', folder: true, open: true, depth: 0, badge: '3' },
  { name: 'graph-lanes', icon: 'cloud-off', state: 'gone', badge: 'gone', depth: 1 },
  { name: 'lfs-prune', icon: 'git-branch', state: 'local', badge: 'local', depth: 1 },
  { name: 'worktrees', icon: 'cloud', state: 'remote', badge: '', depth: 1, dim: true },
  { name: 'bugfix', folder: true, open: true, depth: 0, badge: '2' },
  { name: 'rebase-conflict', icon: 'git-branch', state: 'synced', badge: '↓1', depth: 1 },
  { name: 'lane-overflow', icon: 'cloud', state: 'remote', badge: '', depth: 1, dim: true },
  { name: 'release', folder: true, open: false, depth: 0, badge: '4' },
];

const BRANCH_STATES = [
  { st: 'Local 與 remote 同步', icon: 'git-branch', badge: '無', note: '最常見的狀態。實心分支圖示，名稱一般色。' },
  { st: 'Local 領先 / 落後', icon: 'git-branch', badge: '↑2 / ↓1', note: '同一個圖示，右側加 ahead/behind 數字。同時領先又落後（diverged）顯示 ↑2↓1。' },
  { st: 'Local only（無 upstream）', icon: 'git-branch', badge: 'local', note: '還沒 push 過。badge 用文字而非圖示，避免與 ahead 混淆。Push 後 badge 自動消失。' },
  { st: 'Remote only（未 checkout）', icon: 'cloud', badge: '無', note: '雲朵圖示 + 半透明，代表本機還沒有這條分支。點兩下即 checkout 成本機分支，圖示隨即變成實心。' },
  { st: 'Remote 已刪除', icon: 'cloud-off', badge: 'gone', note: '本機還在、遠端沒了。cloud-off + warning 色 + gone badge。真正移除 remote-tracking ref 要執行 Prune（見下方說明）。' },
  { st: '目前分支', icon: 'git-branch', badge: '—', note: '名稱加粗、整列以 selected 底色標示，永遠置頂於所屬資料夾內，且不受 filter 影響。' },
];

const TERMINALS = [
  { os: 'Windows', app: 'Windows Terminal', cmd: 'wt.exe -d "{path}"（找不到時退回 powershell.exe -NoExit -Command cd "{path}"）' },
  { os: 'macOS', app: 'Terminal.app', cmd: 'open -a Terminal "{path}"' },
  { os: 'Linux', app: '系統預設', cmd: 'x-terminal-emulator --working-directory="{path}"（依序試 gnome-terminal、konsole、xterm）' },
];

const PREFNAV = ['General', 'Repository sources', 'Git', 'Appearance', 'Shortcuts', 'Advanced'];

const BASEFOLDERS = [
  { path: '~/dev', depth: '2', found: '14 repos' },
  { path: '~/work/clients', depth: '3', found: '7 repos' },
  { path: '/Volumes/ext/archive', depth: '1', found: '2 repos · 離線' },
];

const P11 = [
  { n: 1, el: 'Preferences 左側分頁', key: 'Ctrl/Cmd+,', note: '六段：General / Repository sources / Git / Appearance / Shortcuts / Advanced。這裡全部是應用層級設定，單一 repo 的設定在 Repository → Settings…（見 06）。' },
  { n: 2, el: 'Base folders 清單', key: '—', note: '可加入多個根目錄，每列是路徑 + 掃描深度 + 目前找到幾個 repo。深度獨立設定，因為 ~/dev 這種扁平目錄用 2 層就夠，而 monorepo 集合可能要 3 層。路徑不存在或磁碟未掛載時該列標為離線，保留設定不自動刪除。' },
  { n: 3, el: 'Add folder…', key: '—', note: '開系統原生資料夾選擇器。加入後立刻掃描一次，結果寫進 log（見 10）。' },
  { n: 4, el: '自動掃描', key: '—', note: '開啟後依設定的間隔在背景重掃，屬於低優先度作業，只在 status bar 的 +N task 內顯示。關閉時只在按下 Rescan now 才掃。' },
  { n: 5, el: '掃描結果摘要', key: '—', note: '永遠顯示實際數字：找到幾個 repo、跨幾個資料夾、上次掃描時間與耗時。被深度上限擋掉的資料夾數也一併寫出，不做無聲截斷。' },
  { n: 6, el: '記錄手動開啟的位置', key: '—', note: '預設開啟。使用者透過 Open repository… 打開的 repo，其所在資料夾會被記進另一份清單，不會混進 base folders。這樣不必為了一個臨時專案去改掃描設定。' },
  { n: 8, el: '全域 gitignore', key: '—', note: 'Git 段。開關 + 路徑欄 + Browse / Edit，寫入 core.excludesFile，與 CLI 共用。內建純文字編輯器可直接改，存檔即重算 working copy。已由使用者 .gitconfig 設定過時帶入現值並標註來源，不覆寫。停用只移除設定不刪檔。' },
  { n: 9, el: '自動 fetch', key: '—', note: 'General 段。只針對目前開啟的 repository，預設每 10 分鐘一次，切換 repo 時重置計時。純 fetch 不動 working tree。可選同時 prune、計量網路暫停。背景低優先度，失敗不彈窗；結果反映在 ahead/behind 與 gone 標記。' },
  { n: 7, el: '手動紀錄清單', key: '—', note: '顯示筆數與最近一筆，可展開逐筆移除或整批清空。清空只影響清單，不會刪除磁碟上的 repo——這點寫在按鈕旁邊。' },
];

const CHANGEVIEWS = [
  { obj: 'Commit', where: 'History 分頁：右側 Changed files（02-10）+ 下方 Commit detail（02-08）', how: '選 commit → 檔案清單即時更新；點檔案在 detail 區顯示該檔 diff；雙擊 commit 開獨立視窗，適合長 body 與逐檔審閱。' },
  { obj: 'Stash', where: 'Sidebar STASH 段：點一下展開 inline 檔案清單', how: '展開列出該 stash 的檔案與增刪行數；點檔案開 Diff 分頁（唯讀，標題註明 stash@{0}）。右鍵 05-H 的 View diff 等同此動作。stash 不佔用 History 的選取狀態。' },
  { obj: 'Working copy', where: 'Working Copy 分頁（03）', how: 'unstaged / staged 兩欄 + 下方 diff，可逐行 stage。' },
  { obj: '兩個 ref 之間', where: 'Compare 分頁', how: '見下方 compare 規格。結果是唯讀的三段式：commits、files、diff。' },
];

const COMPARES = [
  { pair: 'Branch ↔ Branch', entry: '同時選兩個分支 → 右鍵 Compare，或 Repository → Compare…', out: 'commits 分兩欄（只在左 / 只在右），files 為合併後的差異。常用於 merge 前預覽。' },
  { pair: 'Branch ↔ Tag', entry: '同上，第二個選 tag', out: '通常用來看某版之後改了什麼。標題直接寫 v0.5.0 → main。' },
  { pair: 'Commit ↔ Commit', entry: 'History 內 Ctrl/Cmd 點選兩個 commit → 右鍵 Compare', out: '兩點之間的完整差異；若非祖先關係，另外標示 merge base 並提供切換「三點 / 兩點」比較。' },
  { pair: 'Stash ↔ 任意 ref', entry: '右鍵 stash → Compare with…', out: 'stash 一律放在右側（新的一方）。唯讀，不能從這裡 stage。' },
  { pair: '任意 ref ↔ Working copy', entry: '右鍵該 ref → Compare with working copy', out: '唯一可寫的比較：files 欄的每個檔案可直接 checkout 覆蓋成該 ref 的版本，動作前有確認。' },
];

const TASKS = [
  { task: 'Fetch / Pull / Push', where: 'Status bar 進度區', cancel: '可取消', note: '顯示遠端名與已傳輸物件數（12,480 / 31,206）。取消即中斷連線，本機 ref 不變。' },
  { task: 'Clone', where: '該 repository 列 + status bar', cancel: '可取消', note: '兩段進度：receiving objects、resolving deltas，各自顯示實際數字。取消會刪除尚未完成的目標資料夾，並在 log 寫明刪了哪個路徑。' },
  { task: 'History 掃描 / 建圖', where: 'History 分頁頂端細進度條', cancel: '可取消', note: '大 repo 專用。顯示已讀 commit 數與耗時（199,960 / 199,960 · 331 ms）。取消保留已載入的部分，不清空畫面。' },
  { task: 'Checkout / Merge / Rebase', where: 'Banner + status bar', cancel: '不可取消', note: '會改寫 working tree，中途中斷比跑完更危險。改為明確禁用取消鈕，並在 tooltip 說明原因。' },
  { task: 'Prune / GC / LFS 抓取', where: 'Status bar，摺疊在 tasks 計數內', cancel: '可取消', note: '低優先度，不搶畫面。完成只在 log 留一行，不跳任何提示。' },
  { task: '外部檔案變更監看', where: '不顯示', cancel: '—', note: '常駐背景作業。只有偵測到變更並實際刷新清單時，才在 log 記一行。' },
];

const ERRCASES = [
  { err: 'Push 被拒（non-fast-forward）', mode: '視窗', action: 'Pull then push' },
  { err: '需要認證 / 憑證過期', mode: '視窗', action: 'Sign in…' },
  { err: 'Pull 產生衝突', mode: '視窗', action: 'Resolve conflicts…（開 08 視窗）' },
  { err: '找不到 git 或版本過舊', mode: '視窗', action: 'Open preferences' },
  { err: '磁碟空間不足 / 權限不足', mode: '視窗', action: 'Show in file manager' },
  { err: '自動 fetch 失敗、網路不通', mode: 'Status bar + log', action: '無按鈕，下次排程自動重試' },
  { err: '掃描 base folder 時某層無權限', mode: 'Status bar + log', action: '無按鈕，log 寫出路徑' },
];

const LOGRULES = [
  { k: '記什麼', v: '每一次實際執行的 git 指令原文、工作目錄、結束代碼、耗時；以及應用層事件（開啟 repo、切分支、prune 掉哪些 ref）。' },
  { k: '不記什麼', v: '認證資訊、remote URL 中的 token、檔案內容。密碼欄位一律以 •••• 取代後才寫入。' },
  { k: '層級', v: 'info / warning / error 三級。error 會同時在 status bar 亮紅點，直到使用者開過 log 面板才熄。' },
  { k: '保留', v: '記憶體中預設保留最近 500 筆，Preferences 可調到 2,000（上限值一律寫在畫面上，不隱藏）。寫檔保留 7 天並輪替。' },
  { k: '只有一套', v: 'Log 只有底部抽屜這一個實作（main.log splitter）。不另開 operation log dialog — 同一份資料兩套介面會各自漂移。' },
  { k: '匯出', v: 'Copy all、Save as…（純文字）。回報問題時附這份即可，不需要另外重現。' },
  { k: '錯誤呈現', v: '不用會自動消失的 toast。錯誤進 log 面板並在 status bar 常駐一則可點的摘要，點了才展開，關掉才消失。' },
];

const L0 = 15, L1 = 32, RH = 26;
const Y = (i) => i * RH + 13;
const C0 = 'var(--graph-lane-1)', C1 = 'var(--graph-lane-2)';

const CHIP_LOCAL = 'font-size:9px;padding:1px 5px;border-radius:999px;background:var(--accent);color:var(--text-on-accent);white-space:nowrap;flex-shrink:0;display:inline-flex;align-items:center;gap:3px';
const CHIP_HEAD = 'font-size:9px;padding:1px 5px;border-radius:999px;background:var(--accent);color:var(--text-on-accent);white-space:nowrap;flex-shrink:0;box-shadow:0 0 0 2px var(--accent-subtle);display:inline-flex;align-items:center;gap:3px';
const CHIP_REMOTE = 'font-size:9px;padding:1px 5px;border-radius:999px;border:1px dashed var(--border-strong);color:var(--text-tertiary);white-space:nowrap;flex-shrink:0';
const CHIP_TAG = 'font-size:9px;padding:1px 5px;border-radius:999px;border:1px solid var(--warning);color:var(--warning);white-space:nowrap;flex-shrink:0';

const GRAPH_ROWS = [
  { msg: 'Fix lane allocator overflow gutter', hash: 'a1b2c3d', lane: 0, sel: true, author: 'j.chen', me: true, date: '2h',
    chips: [{ label: 'HEAD → main', style: CHIP_HEAD }] },
  { msg: 'Cap lane allocation at 48 lanes', hash: 'd41f8ce', lane: 0, author: 'j.chen', me: true, date: '6h',
    chips: [{ label: 'origin/main', style: CHIP_REMOTE }] },
  { msg: 'Merge branch feature/graph-lanes', hash: '7c3d9e2', lane: 0, author: 'a.iyer', date: 'Aug 13', chips: [] },
  { msg: 'Add askpass helper for HTTPS prompts', hash: '4b8f01c', lane: 0, author: 'r.osei', date: 'Aug 12', chips: [] },
  { msg: 'Key lane colour off seed commit', hash: 'd3f21ab', lane: 1, author: 'j.chen', me: true, date: 'Aug 11',
    chips: [{ label: 'feature/graph-lanes', style: CHIP_LOCAL, synced: true }] },
  { msg: 'Add geometric publish schedule', hash: '9f0e1aa', lane: 1, author: 'a.iyer', date: 'Aug 10',
    chips: [{ label: 'v0.5.0', style: CHIP_TAG }] },
  { msg: 'Implement side-by-side conflict view', hash: '2e6a7bd', lane: 0, author: 'a.iyer', date: 'Aug 9', chips: [] },
];

const GRAPH_COLS = [
  { label: 'Graph', on: true, locked: true }, { label: 'Message', on: true, locked: true },
  { label: 'Refs', on: true }, { label: 'Author', on: true }, { label: 'Date', on: true },
  { label: 'Commit hash', on: true }, { label: 'Committer', on: false }, { label: 'Changed files', on: false },
];

const GRAPH_LINES = [
  { d: `M${L0} ${Y(0)} L${L0} ${Y(6)}`, c: C0 },
  { d: `M${L1} ${Y(4)} L${L1} ${Y(5)}`, c: C1 },
  { d: `M${L0} ${Y(2)} C ${L0} ${Y(2) + 17}, ${L1} ${Y(4) - 17}, ${L1} ${Y(4)}`, c: C1 },
  { d: `M${L1} ${Y(5)} C ${L1} ${Y(5) + 17}, ${L0} ${Y(6) - 17}, ${L0} ${Y(6)}`, c: C1 },
];

const GRAPH_DOTS = GRAPH_ROWS.map((r, i) => ({
  x: r.lane === 0 ? L0 : L1, y: Y(i), r: 4.2,
  f: r.lane === 0 ? C0 : C1, s: 'var(--surface-panel)', w: 2,
})).concat([{ x: L0, y: Y(0), r: 7, f: 'none', s: 'var(--accent)', w: 1.5 }]);

const HIST = [
  { msg: 'Fix lane allocator overflow gutter', hash: 'a1b2c3d', lane: 'var(--graph-lane-1)', sel: true },
  { msg: 'Add geometric publish schedule', hash: '9f0e1aa', lane: 'var(--graph-lane-2)' },
  { msg: 'Merge branch feature/graph-lanes', hash: '7c3d9e2', lane: 'var(--graph-lane-1)' },
  { msg: 'Add askpass helper for HTTPS prompts', hash: '4b8f01c', lane: 'var(--graph-lane-1)' },
  { msg: 'Implement side-by-side conflict view', hash: '2e6a7bd', lane: 'var(--graph-lane-3)' },
  { msg: 'Cap lane allocation at 48 lanes', hash: 'd41f8ce', lane: 'var(--graph-lane-1)' },
];

const P2 = [
  { n: 1, el: 'Menu bar', menu: '—', key: 'Alt / Ctrl+F2', note: 'macOS 在系統列；Windows / Linux 在標題列下方。Alt 開啟第一個選單並顯示助憶字母。' },
  { n: 2, el: 'Fetch / Pull / Push', menu: 'Repository → Fetch / Pull / Push', key: 'Ctrl/Cmd+Shift+F / P / Cmd+P', note: '三顆同組。Push 為主要樣式。conflict 狀態全部停用（見 07）。' },
  { n: 3, el: 'Search commits', menu: 'Edit → Find in history', key: 'Ctrl/Cmd+F', note: '就地過濾 commit 清單，支援 message / author / hash 前綴。' },
  { n: 4, el: 'Sidebar', menu: 'View → Toggle sidebar', key: 'Ctrl/Cmd+B', note: '只放目前 repo 的內容，三段：Branches（local 與 remote 合併成一份樹狀清單）、Tags、Stash。repository 清單已移出，改用 15 的切換彈窗。收合時寬度歸零，不留殘影。' },
  { n: 5, el: 'Splitter A', menu: '—', key: '雙擊還原', note: 'sidebar 與中央的分界，見 09。' },
  { n: 6, el: 'Commit list（graph）', menu: 'View → History', key: 'Ctrl/Cmd+1', note: '左側是實際繪製的 lane 連線：目前分支固定 lane 0 且全程直線，支線往右並自行轉折，分岔與合併以支線顏色的曲線相接。節點右側的 ref chip 標出 HEAD、本機分支與 origin 的位置：同步時只出一個 chip 並以雲朵圖示表示遠端也在此，分歧時才另外出現虛線的 origin chip。單擊選取並更新下方 detail；雙擊或 Enter 開獨立 commit 視窗；右鍵見 05-E。' },
  { n: 7, el: 'Splitter B', menu: '—', key: '雙擊還原', note: '清單與 commit detail 的水平分界。拖到底＝收起 detail。' },
  { n: 8, el: 'Commit detail 面板', menu: 'View → Commit detail', key: 'Ctrl/Cmd+D', note: 'subject + 完整 body + metadata。body 等寬字、保留換行、可選取。這是看 commit description 的主要位置。' },
  { n: 9, el: 'Splitter C', menu: '—', key: '雙擊還原', note: '中央與檔案清單的分界。' },
  { n: 10, el: 'Changed files', menu: '—', key: '↑ ↓ 移動', note: '該 commit 的檔案清單；單擊在 detail 區顯示該檔 diff。右鍵是專屬的 05-K，而非 working copy 的 05-F——可看該檔在此 commit 的 diff、與 working copy 比較、查看 file history 與 blame，並在第二層提供把單一檔案還原成此時狀態的動作。' },
  { n: 11, el: 'Status bar', menu: 'View → Status bar', key: '—', note: '分支、ahead/behind、commit 總數、掃描耗時、lane 上限。永遠顯示實際數字。upstream 消失時改顯示 upstream gone。' },
  { n: 12, el: 'Branches — 單一樹狀清單', menu: 'Remote → Prune remote branches', key: '—', note: 'Local 與 remote 不再分兩段，同一條分支只出現一次，由圖示表示它是本機獨有、遠端獨有、兩邊都有、或遠端已刪除（見左側圖示表）。名稱中的斜線自動摺成資料夾。遠端已刪除的分支不會靜默消失，真正移除需使用者執行 Prune。' },
  { n: 16, el: 'Graph 欄位選擇', menu: 'View → Graph columns', key: '—', note: 'History 標題列右側一顆按鈕開出勾選清單：Graph、Message、Refs、Author、Date、Commit hash、Committer、Changed files。Graph 與 Message 固定不可關，其餘可開關並拖曳排序。設定存在應用層級，所有 repo 共用；欄寬各自可拖曳並記憶。Date 欄採混合格式：24 小時內用相對時間（2h、6h），超過一天一律改絕對日期（Aug 13），跨年再補年份。相對時間只在一眼能算得出來的範圍內有意義，超過就該給確切日期。滑鼠停留顯示完整 ISO 8601 時間含時區。作者為本人的 commit，Author 欄以 accent 色加粗顯示，比對依據是 user.email。' },
  { n: 15, el: 'Repository 切換彈窗', menu: 'File → Switch repository…', key: 'Ctrl/Cmd+R', note: 'Sidebar 最上方一顆顯示目前 repo 的按鈕，點擊或按快捷鍵開彈窗。彈窗內是可搜尋的 repo 清單，每列顯示名稱與 ahead/behind，最近開啟的排前面；底部固定 Open / Clone 兩個入口。選定後彈窗關閉、整個視窗切到該 repo。Esc 關閉不切換。之所以獨立出來，是因為切 repo 是低頻但影響全視窗的動作，和高頻的分支操作混在同一份清單會互相干擾。' },
  { n: 14, el: 'Branch filter', menu: 'Edit → Filter branches', key: 'Ctrl/Cmd+Shift+E', note: '一個輸入框同時過濾 Branches、Tags、Stash 三段：子字串比對、不分大小寫、斜線視為分隔（打 gl 可命中 feature/graph-lanes）。有輸入時資料夾全展開，清空後回到原本收合狀態。沒有命中的段落整段隱藏，不留空標題。右側顯示 命中/總數。目前分支永遠置頂顯示，即使不符合條件也不會被濾掉。Esc 清空並回到未過濾狀態，↓ 直接跳進第一個結果。' },
  { n: 13, el: 'History / Working Copy 分頁列', menu: 'View → History / Working copy', key: 'Ctrl/Cmd+1 / +2', note: '中央區最上方。常駐兩個分頁（Repository settings 已移為 dialog），Compare 以額外分頁的形式加在右側、可關閉。' + 'Working Copy 分頁右側常駐顯示未提交檔案數的 badge，數字為 0 時不顯示。切換分頁不影響 sidebar 選取與各面板寬度。Ctrl/Cmd+Tab 在兩個分頁間來回。' },
];

const P3 = [
  { n: 1, el: 'Unstaged 清單', menu: 'View → Working copy', key: 'Ctrl/Cmd+2', note: '勾選＝stage 整檔；拖曳到右欄同效。右鍵見 05-F。' },
  { n: 2, el: 'Splitter D', menu: '—', key: '雙擊還原', note: 'unstaged / staged 垂直分界，預設 1:1。' },
  { n: 3, el: 'Staged 清單', menu: 'Repository → Stage all', key: 'Ctrl/Cmd+Shift+S', note: '取消勾選＝unstage。拖回左欄同效。' },
  { n: 4, el: 'Splitter E', menu: '—', key: '雙擊還原', note: '檔案區與 diff 區的水平分界。' },
  { n: 5, el: 'Diff — 逐行 stage', menu: 'Repository → Stage selected lines', key: 'Ctrl/Cmd+Shift+Enter', note: '每個變更行左側一個 checkbox；右鍵可 Stage line / Stage hunk / Unstage hunk / Copy line。' },
  { n: 6, el: 'Summary 欄', menu: '—', key: 'Ctrl/Cmd+Enter 送出', note: 'commit 的 subject 行，50 字後變色提示，不硬性阻擋。' },
  { n: 7, el: 'Description 欄', menu: '—', key: 'Tab 由 summary 移入', note: 'commit body。等寬字，72 字位置有淡尺標。這是撰寫 description 的地方，閱讀在 02。' },
  { n: 8, el: 'Commit / Amend', menu: 'Repository → Commit / Amend last commit', key: 'Ctrl/Cmd+Enter / Ctrl/Cmd+Shift+A', note: 'staged 為 0 或 summary 為空時停用。Amend 會把上一筆訊息帶回兩個欄位。' },
  { n: 10, el: 'List / Tree 切換', menu: 'View → File list as tree', key: 'Ctrl/Cmd+Shift+T', note: '每個檔案清單標題右側一組兩鍵切換：平鋪完整路徑，或依資料夾摺成樹狀。樹狀模式下只有一個子項的資料夾會自動串接成 lib/app/views 一列，不會逐層縮排浪費寬度。資料夾列的 checkbox 是三態，勾選＝stage 整個資料夾。收合狀態與模式各清單獨立記憶。同一個設定套用到 Working Copy 兩欄、History 的 Changed files、Compare 的 Files、以及 Conflict 視窗的檔案清單。' },
  { n: 9, el: 'History / Working Copy 分頁列', menu: 'View → History / Working copy', key: 'Ctrl/Cmd+1 / +2', note: '與 History 分頁共用同一條分頁列，位置固定在中央區最上方。badge 顯示未提交檔案數（unstaged + staged 去重）。切走再切回時，diff 捲動位置與 commit 訊息草稿都保留。' },
];

const SCOPES = [
  { scope: '單一檔案', how: '點該列的 checkbox，或直接拖到另一欄', key: 'Space', note: '最基本的單位。整檔所有變更一起進 / 出暫存區。' },
  { scope: '多個檔案（不連續）', how: 'Ctrl/Cmd + 點選累加', key: 'Ctrl/Cmd+click', note: '選取後任一列的 checkbox 或右鍵動作會套用到整批。拖曳時整批一起移動。' },
  { scope: '連續一段檔案', how: 'Shift + 點選頭尾', key: 'Shift+click', note: '與 Ctrl/Cmd 可混用：先 Shift 選一段，再 Ctrl/Cmd 加減個別項。' },
  { scope: '整欄全部', how: '欄位標題列的全選 checkbox', key: 'Ctrl/Cmd+Shift+S', note: '標題 checkbox 有三態：全空 / 半選（indeterminate）/ 全選。半選狀態點一下＝全選。' },
  { scope: '整個資料夾', how: '樹狀模式下點資料夾列的 checkbox', key: 'Space', note: '僅樹狀模式提供。同樣是三態，勾選＝該資料夾底下所有檔案一起 stage。動作文字寫出實際檔案數。' },
  { scope: '單一 hunk', how: '點 hunk 標頭列（@@ …）', key: '—', note: '該段所有變更行一起處理。右鍵 Stage hunk / Unstage hunk。' },
  { scope: '任意連續行', how: 'diff 區按住拖過多行，或 Shift + ↑ ↓', key: 'Ctrl/Cmd+Shift+Enter', note: '最細的單位，可跨 hunk 但不能跨檔。選取後按鈕變成 Stage 12 lines。' },
];

const MENUS = [
  { title: 'File', items: [
    { label: 'New repository…', key: 'Ctrl/Cmd+N' }, { label: 'Open repository…', key: 'Ctrl/Cmd+O' },
    { label: 'Clone repository…', key: 'Ctrl/Cmd+Shift+N' }, { label: 'Switch repository…', key: 'Ctrl/Cmd+R' },
    { label: 'Add local repository…', key: '' },
    { label: 'Close window', key: 'Ctrl/Cmd+W' }, { label: 'Preferences…', key: 'Ctrl/Cmd+,' },
    { label: 'Exit', key: 'Alt+F4 / Cmd+Q' } ] },
  { title: 'Edit', items: [
    { label: 'Undo', key: 'Ctrl/Cmd+Z' }, { label: 'Redo', key: 'Ctrl/Cmd+Shift+Z' },
    { label: 'Cut', key: 'Ctrl/Cmd+X' }, { label: 'Copy', key: 'Ctrl/Cmd+C' }, { label: 'Paste', key: 'Ctrl/Cmd+V' },
    { label: 'Find in history', key: 'Ctrl/Cmd+F' }, { label: 'Find in files', key: 'Ctrl/Cmd+Shift+H' },
    { label: 'Filter branches', key: 'Ctrl/Cmd+Shift+E' }, { label: 'Select all', key: 'Ctrl/Cmd+A' } ] },
  { title: 'View', items: [
    { label: 'History', key: 'Ctrl/Cmd+1' }, { label: 'Working copy', key: 'Ctrl/Cmd+2' },
    { label: 'Next tab', key: 'Ctrl/Cmd+Tab' }, { label: 'File list as tree', key: 'Ctrl/Cmd+Shift+T' },
    { label: 'Graph columns', key: '', submenu: true },
    { label: 'Commit detail', key: 'Ctrl/Cmd+D' }, { label: 'Toggle sidebar', key: 'Ctrl/Cmd+B' },
    { label: 'Status bar', key: '' }, { label: 'Log', key: 'Ctrl/Cmd+Shift+L' }, { label: 'Reset panel sizes', key: 'Ctrl/Cmd+0' },
    { label: 'Theme', key: '', submenu: true } ] },
  { title: 'Repository', items: [
    { label: 'Fetch', key: 'Ctrl/Cmd+Shift+F' }, { label: 'Pull', key: 'Ctrl/Cmd+Shift+P' }, { label: 'Push', key: 'Ctrl/Cmd+P' },
    { label: 'Compare…', key: 'Ctrl/Cmd+Shift+C' },
    { label: 'Commit', key: 'Ctrl/Cmd+Enter' }, { label: 'Amend last commit', key: 'Ctrl/Cmd+Shift+A' },
    { label: 'Stage selected lines', key: 'Ctrl/Cmd+Alt+S' },
    { label: 'Stage all', key: 'Ctrl/Cmd+Shift+S' }, { label: 'Open in terminal', key: 'Ctrl/Cmd+`' },
    { label: 'Settings…', key: '' } ] },
  { title: 'Branch', items: [
    { label: 'New branch…', key: 'Ctrl/Cmd+Shift+B' }, { label: 'Checkout…', key: 'Ctrl/Cmd+Shift+O' },
    { label: 'Rename branch…', key: 'F2' }, { label: 'Merge into current…', key: 'Ctrl/Cmd+Shift+M' },
    { label: 'Rebase onto…', key: 'Ctrl/Cmd+Shift+R' }, { label: 'Stash changes', key: 'Ctrl/Cmd+Shift+S' },
    { label: 'Delete branch…', key: '', color: 'var(--danger)' } ] },
  { title: 'Remote', items: [
    { label: 'Add remote…', key: '' }, { label: 'Fetch all remotes', key: '' },
    { label: 'Prune remote branches', key: '' }, { label: 'Manage remotes…', key: '' } ] },
  { title: 'Help', items: [
    { label: 'Documentation', key: '' }, { label: 'Keyboard shortcuts', key: 'Ctrl/Cmd+/' },
    { label: 'Report an issue', key: '' }, { label: 'About', key: '' } ] },
];

const CTX = [
  { id: '05-A', title: 'Repository', target: '右鍵切換彈窗內的 repository 列（15）', items: [
    { label: 'Open in file manager', key: '' }, { label: 'Open in terminal', key: 'Ctrl/Cmd+`' },
    { label: 'Fetch', key: '' }, { label: 'Pull', key: '' }, { label: 'Push', key: '' },
    { label: 'Settings…', key: '' }, { sep: true }, { label: 'Remove from list', key: '', danger: true } ] },
  { id: '05-B', title: 'Local branch', target: '右鍵實心 git-branch 圖示的分支列', items: [
    { label: 'Checkout', key: 'Shift+O' }, { label: 'New branch from here…', key: '' }, { label: 'Rename…', key: 'F2' },
    { label: 'Merge into current', key: '' }, { label: 'Rebase current onto here', key: '' },
    { label: 'Compare with…', key: 'Ctrl/Cmd+Shift+C' },
    { label: 'Copy branch name', key: '' }, { sep: true }, { label: 'Delete branch…', key: '', danger: true } ] },
  { id: '05-C', title: 'Remote-only / gone 分支', target: '右鍵 cloud 或 cloud-off 圖示的分支列。gone 的列只留 Prune 與 Copy，其餘停用', items: [
    { label: 'Checkout as new local…', key: '' }, { label: 'Fetch this branch', key: '' },
    { label: 'Copy branch name', key: '' }, { label: 'Prune this ref', key: '' },
    { sep: true }, { label: 'Delete on remote…', key: '', danger: true } ] },
  { id: '05-J', title: 'Branch folder', target: '右鍵資料夾列（feature/、bugfix/…）', items: [
    { label: 'Expand all / Collapse all', key: '' }, { label: 'Fetch branches in folder', key: '' },
    { label: 'Copy folder prefix', key: '' },
    { sep: true }, { label: 'Delete merged branches…', key: '', danger: true } ] },
  { id: '05-D', title: 'Tag', target: '右鍵 sidebar TAGS 段的項目', items: [
    { label: 'Checkout tag (detached)', key: '' }, { label: 'Push tag', key: '' },
    { label: 'Compare with…', key: 'Ctrl/Cmd+Shift+C' },
    { label: 'Copy tag name', key: '' }, { sep: true }, { label: 'Delete tag…', key: '', danger: true } ] },
  { id: '05-E', title: 'Commit — 有第二層', target: '右鍵 history 的 commit 列', hasSub: true, items: [
    { label: 'Checkout this commit', key: 'Shift+O' }, { label: 'Merge into current', key: '' },
    { label: 'Cherry-pick', key: '' }, { label: 'Create branch here…', key: '' },
    { label: 'Compare with…', key: 'Ctrl/Cmd+Shift+C' },
    { label: 'Copy SHA', key: 'Ctrl/Cmd+C' }, { label: 'More actions', key: '', submenu: true } ],
    sub: [ { label: 'Rebase onto here', key: '' }, { label: 'Reset branch to here…', key: '' },
    { label: 'Revert commit', key: '' }, { label: 'Export as patch…', key: '' },
    { label: 'Compare with working copy', key: '' } ] },
  { id: '05-F', title: 'File（staged / unstaged）', target: '右鍵檔案列。有多選時全部動作改為複數並帶數量，例如 Stage 3 files', items: [
    { label: 'Stage 3 files', key: 'Space' }, { label: 'Open file', key: 'Ctrl/Cmd+Enter' },
    { label: 'Show in file manager', key: '' }, { label: 'Open terminal here', key: 'Ctrl/Cmd+`' },
    { label: 'Copy path', key: '' },
    { sep: true }, { label: 'Discard changes in 3 files…', key: '', danger: true } ] },
  { id: '05-K', title: 'Commit file（History 內）', target: '右鍵 History 的 Changed files 或 commit 展開後的檔案列。與 05-F 不同：這裡的檔案屬於某個歷史 commit，不是 working copy', items: [
    { label: 'View diff in this commit', key: '' },
    { label: 'Compare with working copy', key: 'Ctrl/Cmd+Shift+C' },
    { label: 'Open file at this revision', key: '' },
    { label: 'File history', key: '' },
    { label: 'Blame at this commit', key: '' },
    { label: 'Open terminal here', key: 'Ctrl/Cmd+`' },
    { label: 'Copy path', key: '' },
    { label: 'More actions', key: '', submenu: true } ],
    sub: [
      { label: 'Restore file to this state', key: '' },
      { label: 'Restore file to before this state', key: '' },
      { label: 'Restore and stage', key: '' },
      { label: 'Save this revision as…', key: '' },
      { label: 'Export as patch…', key: '' } ] , hasSub: true },
  { id: '05-G', title: 'Diff line / 行選取', target: '右鍵 diff 區。有拖選多行時第一項變成 Stage 12 lines', items: [
    { label: 'Stage 12 lines', key: 'Ctrl/Cmd+Shift+Enter' }, { label: 'Stage hunk', key: '' },
    { label: 'Unstage hunk', key: '' }, { label: 'Copy lines', key: '' },
    { sep: true }, { label: 'Discard 12 lines…', key: '', danger: true } ] },
  { id: '05-H', title: 'Stash entry', target: '右鍵 sidebar STASH 段的項目（已與 TAGS 分開）', items: [
    { label: 'Apply stash', key: '' }, { label: 'Pop stash', key: '' },
    { label: 'Create branch from stash…', key: '' }, { label: 'View diff', key: '' },
    { label: 'Compare with…', key: 'Ctrl/Cmd+Shift+C' },
    { sep: true }, { label: 'Drop stash…', key: '', danger: true } ] },
  { id: '05-I', title: 'Conflict hunk（08 視窗內）', target: '右鍵 conflict 視窗左 / 右欄的衝突段', items: [
    { label: 'Take this side', key: 'Alt+Left / →' }, { label: 'Take this line only', key: '' },
    { label: 'Take both — this side first', key: 'Alt+↓' }, { label: 'Open in external merge tool', key: '' },
    { sep: true }, { label: 'Discard from result', key: '', danger: true } ] },
];

const DIALOGS = [
  { name: 'Switch repository', from: 'File → Switch repository… / sidebar 頂端按鈕', key: 'Ctrl/Cmd+R', note: '輕量彈窗，非 modal dialog：貼齊按鈕下緣、寬度跟隨 sidebar。可搜尋清單 + 最近開啟排序 + 底部 Open / Clone。列上右鍵即 05-A。' },
  { name: 'Clone repository', from: 'File → Clone repository…', key: 'Ctrl/Cmd+Shift+N', note: 'URL、目標路徑、是否 recurse submodules。URL 貼上後自動帶出資料夾名。' },
  { name: 'New branch', from: 'Branch → New branch… / 05-B / 05-E', key: 'Ctrl/Cmd+Shift+B', note: '名稱、起點（下拉：目前分支 / 指定 commit / tag）、是否立刻 checkout。名稱重複即時擋下。' },
  { name: 'Rename branch', from: '05-B → Rename…', key: 'F2', note: '單一輸入欄。若已推送過會提示遠端仍是舊名。' },
  { name: 'Delete branch', from: 'Branch → Delete branch… / 05-B', key: '', note: '複述分支名與未合併的 commit 數；可勾選一併刪遠端。主按鈕為 danger。' },
  { name: 'Checkout', from: 'Branch → Checkout…', key: 'Ctrl/Cmd+Shift+O', note: '可搜尋的分支 / tag / commit 清單。working tree 有變更時提供 stash 後切換的選項。' },
  { name: 'Merge', from: 'Branch → Merge into current…', key: 'Ctrl/Cmd+Shift+M', note: '來源分支、合併策略（merge commit / fast-forward / squash）。預告可能衝突的檔案數。' },
  { name: 'Rebase', from: 'Branch → Rebase onto…', key: 'Ctrl/Cmd+Shift+R', note: '目標分支與 commit 數預覽。說明衝突時會停在第幾步。' },
  { name: 'Stash changes', from: 'Branch → Stash changes', key: 'Ctrl/Cmd+Shift+S', note: '訊息、是否含 untracked、是否保留已 stage 的內容。' },
  { name: 'Restore file to this state', from: '05-K → More actions → Restore file to this state', key: '', note: '把單一檔案還原成該 commit 當時的內容。dialog 寫出檔名、來源 commit 的 hash 與 summary，並說明目前 working copy 的該檔變更會被覆蓋（若有未提交變更則額外標紅）。Restore and stage 同時放進暫存區。不建立 commit，還原後仍可 discard。' },
  { name: 'Restore file to before this state', from: '05-K → More actions → Restore file to before this state', key: '', note: '還原成父 commit 的內容，等於抵消該 commit 對這一檔的改動。不建 revert commit；merge 或首筆 commit 時 disabled。' },
  { name: 'Discard changes', from: '05-F → Discard changes…', key: '', note: '列出實際檔名與行數。無法復原這件事要寫明。主按鈕為 danger。' },
  { name: 'Force push', from: 'Push（分支已分岔時）', key: '', note: '顯示會被覆蓋的遠端 commit 數。可在 Preferences 關閉此確認。' },
  { name: 'Delete remote branch', from: '05-C → Delete on remote…', key: '', note: '複述遠端與分支名，說明其他人 fetch 後才會看到。完成後 status bar 顯示結果訊息並提供 Undo（重新 push 同名分支）。主按鈕為 danger。' },
  { name: 'Prune remote branches', from: 'Remote → Prune remote branches', key: '', note: '逐條列出遠端已不存在、將從本機清掉的 remote-tracking 分支名，可個別取消勾選。只動 remote-tracking ref，不會碰本機分支。' },
  { name: 'Repository settings', from: 'Repository → Settings…', key: '', note: '四個分頁：General / Remotes / Identity / Performance。原本佔用主視窗中央，現已移除改為 dialog。' },
  { name: 'Preferences', from: 'File → Preferences…', key: 'Ctrl/Cmd+,', note: '應用層級六段：General / Repository sources / Git / Appearance / Shortcuts / Advanced。完整版面與 repository 來源設定見第 11 頁。與 repository settings 分開。' },
];

const STATES = [
  { k: '判定條件', clean: '無 sequencer 作業，且沒有 UU / AA / DD 檔案', conflict: 'merge、rebase、cherry-pick 或 revert 中斷，至少一個檔案未解' },
  { k: 'Banner', clean: '不顯示', conflict: '常駐警示列，寫明作業種類與進度（3 / 8）與衝突檔數' },
  { k: 'Toolbar', clean: 'Fetch / Pull / Push 全部可用', conflict: '三顆停用，改由 banner 提供 Abort / Skip / Continue / Resolve…' },
  { k: '切分支', clean: '可自由切換', conflict: '停用，需先 Continue 或 Abort' },
  { k: 'Working copy', clean: 'unstaged / staged 兩欄', conflict: '最上方多一段 Conflicted，該段檔案不能直接 stage' },
  { k: 'Commit', clean: '正常', conflict: '停用，直到全部標記 resolved 才由 Continue 代為 commit' },
  { k: 'Status bar', clean: 'main ↑2 ↓0 · clean', conflict: 'REBASE 3/8 · 2 conflicted，背景轉 danger 底色' },
  { k: '解衝突入口', clean: '不適用', conflict: 'banner 的 Resolve… 或雙擊衝突檔，開獨立視窗（見 08）' },
];

const P8 = [
  { n: 1, el: 'Conflicted files 清單', key: 'Ctrl/Cmd+↑ ↓', note: '紅點＝未解、綠勾＝已解、數字＝剩餘衝突段數。全綠時 Continue 才可按。' },
  { n: 2, el: 'Splitter F', key: '雙擊還原', note: '檔案清單與三欄區的分界，最小 120px。' },
  { n: 3, el: 'LEFT 欄（ours）', key: 'Alt+Left', note: '目前分支的版本。衝突段以 del 底色標示，非衝突段為 context 灰字。' },
  { n: 4, el: 'Hunk 套用鈕', key: 'Alt+Left', note: 'hover 該段時淡入。點一下把整段送進中欄；也可直接把整段拖進中欄，拖曳時中欄顯示落點highlight。' },
  { n: 5, el: 'Splitter G', key: '雙擊還原', note: '左欄與中欄分界。三欄預設 1 : 1.12 : 1。' },
  { n: 6, el: 'RESULT 欄', key: '—', note: '合併後真正會寫入的檔案。可直接編輯打字，不限於套用兩側。' },
  { n: 7, el: '順序徽章 ①②', key: '—', note: '點行套用的先後。第一個點的排上面，第二個排下面。移除中間某行時序號自動重排。' },
  { n: 8, el: 'Discard', key: 'Ctrl/Cmd+Z', note: '中欄每行右側的刪除鈕，或把該行拖出中欄。整段還原用 Undo。' },
  { n: 9, el: 'Splitter H', key: '雙擊還原', note: '中欄與右欄分界。' },
  { n: 10, el: 'RIGHT 欄（theirs）', key: 'Alt+Right', note: '被合併進來的版本。套用鈕在左緣，箭頭朝左。' },
  { n: 11, el: '底部動作列', key: 'Alt+↓ 下一段', note: 'Previous / Next conflict 在段之間跳；Mark resolved 標記整檔；Abort 中止整個 sequencer；Continue 續跑。' },
];

const MSGS = [
  { op: 'Merge', sum: "Merge branch 'feature/graph-lanes' into main", desc: '衝突檔清單以 # 註解行列出（Conflicts: LaneAllocator.dart …）。若遠端合併則帶入 pull request 樣式的第二行。' },
  { op: 'Rebase', sum: '沿用被套用 commit 的原 summary', desc: '沿用原 body 一字不改，並保留原 author 與 author date。第幾步 / 共幾步只顯示在標題列，不寫進訊息。' },
  { op: 'Cherry-pick', sum: '沿用來源 commit 的原 summary', desc: '原 body ＋ 一行 (cherry picked from commit a1b2c3d)，此行可在 Preferences 關閉。' },
  { op: 'Revert', sum: 'Revert "Fix lane allocator overflow gutter"', desc: '固定格式：空行後 This reverts commit a1b2c3d.，衝突檔以 # 註解附在最後。' },
];

const P10 = [
  { n: 1, el: 'Status bar — repo 狀態區', key: '—', note: '永遠顯示分支與 ahead/behind，不被背景作業擠掉。' },
  { n: 2, el: 'Status bar — 進度區', key: '—', note: '一次只顯示一個最前景的作業：圖示、名稱、實際數字、細進度條、Cancel。其餘作業摺疊成 +N task，點了展開清單。作業結束後停留 3 秒顯示結果再淡出。' },
  { n: 3, el: 'Status bar — 錯誤與 Log 入口', key: 'Ctrl/Cmd+Shift+L', note: '有 error 未讀時左側常駐紅色摘要，可點開直接跳到該筆 log。不使用會自動消失的 toast——錯誤必須留到使用者看過。' },
  { n: 5, el: '錯誤訊息視窗', key: 'Esc 關閉', note: '只有在使用者主動觸發的動作失敗、或需要使用者決定時才出現；背景作業失敗僅留在 status bar 與 log。內容三段：做了什麼失敗、為什麼（具體條件與數字）、git 原始輸出（摺疊、等寬、可複製）。主要按鈕是下一步動作而非 OK。同一錯誤重複發生只累加次數，不重複開窗。' },
  { n: 4, el: 'Log 面板（底部抽屜）', key: 'Ctrl/Cmd+Shift+L', note: '從 status bar 展開，高度可拖曳並記憶，摺疊時完全不佔空間。每筆有時間、層級圖示、git 指令原文、exit code、耗時。可依層級過濾、Copy all、Save as…。' },
];

const SPLITTERS = [
  { id: 'main.sidebar', where: 'Sidebar ↔ 中央', dir: '垂直', def: '250px', min: '180px', note: 'Ctrl/Cmd+B 可整條收起' },
  { id: 'main.detail', where: 'Commit list ↔ Commit detail', dir: '水平', def: '62 / 38', min: '160px', note: '拖到底＝收起 detail' },
  { id: 'main.files', where: '中央 ↔ Changed files', dir: '垂直', def: '186px', min: '140px', note: '僅 History 分頁' },
  { id: 'wc.columns', where: 'Unstaged ↔ Staged', dir: '垂直', def: '1 : 1', min: '200px', note: '' },
  { id: 'wc.diff', where: '檔案區 ↔ Diff', dir: '水平', def: '46 / 54', min: '150px', note: '' },
  { id: 'main.log', where: '主內容 ↔ Log 面板', dir: '水平', def: '收合', min: '90px', note: '摺疊時完全不佔空間' },
  { id: 'cw.files', where: 'Conflict：清單 ↔ 三欄', dir: '垂直', def: '158px', min: '120px', note: 'conflict 視窗獨立記憶' },
  { id: 'cw.panes', where: 'Conflict：左 ↔ 結果 ↔ 右', dir: '垂直 ×2', def: '1 : 1.12 : 1', min: '220px', note: '兩條連動，中欄永遠最寬' },
];

class Component extends DCLogic {
  state = { page: 'p1', theme: 'dark-technical' };

  go = (id) => (e) => { if (e && e.preventDefault) e.preventDefault(); this.setState({ page: id }); };
  step = (d) => () => {
    const i = PAGES.findIndex((p) => p.id === this.state.page);
    const n = Math.min(PAGES.length - 1, Math.max(0, i + d));
    this.setState({ page: PAGES[n].id });
  };
  setTheme = (t) => () => this.setState({ theme: t });

  lucideIcon(name, size, color) {
    const pascal = name.replace(/(^\w|-\w)/g, (m) => m.replace('-', '').toUpperCase());
    const def = window.lucide && window.lucide.icons && window.lucide.icons[pascal];
    if (!def) return null;
    return React.createElement('svg', {
      width: size || 14, height: size || 14, viewBox: '0 0 24 24', fill: 'none',
      stroke: color || 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round',
      style: { display: 'block', flexShrink: 0 },
    }, def.map((t, i) => React.createElement(t[0], Object.assign({ key: i }, t[1]))));
  }

  menuItems(items) {
    return items.map((i) => ({
      label: i.sep ? '' : i.label,
      key: i.key || '',
      cls: i.danger ? 'danger' : '',
      color: i.color || 'var(--text-primary)',
      arrow: i.submenu ? this.lucideIcon('chevron-right', 12, 'var(--text-tertiary)') : null,
    })).filter((i) => i.label);
  }

  dlgFields(f) {
    const k = f.k || 'text';
    const isChk = k === 'chk' || k === 'chk-on';
    const isRadio = k === 'radio' || k === 'radio-on';
    const on = k === 'chk-on' || k === 'radio-on';
    const isNote = k === 'note', isWarn = k === 'warn', isList = k === 'list';
    const mono = f.mono ? 'var(--font-mono)' : 'var(--font-ui)';
    let box;
    if (isChk || isRadio) box = 'font-size:11.5px;color:var(--text-primary);line-height:1.5';
    else if (isNote) box = 'font-size:10.5px;color:var(--text-tertiary);line-height:1.7';
    else if (isWarn) box = 'font-size:10.5px;color:var(--text-secondary);line-height:1.65;background:var(--surface-sunken);border:1px solid var(--border-subtle);border-left:2px solid var(--warning);border-radius:var(--radius-md);padding:8px 9px;flex:1';
    else box = 'font-size:11px;font-family:' + mono + ';white-space:pre-line;padding:' + (isList ? '7px 9px' : '5px 8px')
      + ';border-radius:var(--radius-md);flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;'
      + 'border:1px solid ' + (k === 'focus' ? 'var(--accent)' : 'var(--border-default)')
      + ';background:' + (k === 'ro' || isList ? 'var(--surface-sunken)' : 'var(--surface-panel)')
      + ';color:' + (k === 'ro' ? 'var(--text-secondary)' : 'var(--text-primary)');
    const mark = isChk
      ? 'width:12px;height:12px;border-radius:3px;flex-shrink:0;margin-top:2px;border:1.5px solid ' + (on ? 'var(--accent)' : 'var(--border-strong)') + ';background:' + (on ? 'var(--accent)' : 'transparent')
      : isRadio
        ? 'width:12px;height:12px;border-radius:999px;flex-shrink:0;margin-top:2px;border:' + (on ? '3.5px solid var(--accent)' : '1.5px solid var(--border-strong)') + ';background:var(--surface-panel)'
        : 'display:none';
    return {
      label: f.label || '', labelDisp: f.label ? 'block' : 'none',
      v: f.v, boxStyle: box, markStyle: mark,
      hint: f.hint || '', hintDisp: f.hint ? 'block' : 'none',
    };
  }

  dlgGroup(grp) {
    return DLGS.filter((d) => d.grp === grp).map((d) => ({
      name: d.name, key: d.key || '', keyDisp: d.key ? 'inline-block' : 'none',
      primary: d.primary,
      btnCls: d.danger ? 'gbm-btn gbm-btn-danger gbm-btn-sm' : 'gbm-btn gbm-btn-primary gbm-btn-sm',
      fields: d.f.map((f) => this.dlgFields(f)),
    }));
  }

  renderVals() {
    const s = this.state;
    const cur = PAGES.find((p) => p.id === s.page) || PAGES[0];
    return {
      theme: s.theme,
      pages: PAGES.map((p) => ({ ...p, tag: p.tag || '', selCls: p.id === s.page ? 'selected' : '', onClick: this.go(p.id) })),
      themes: [
        { id: 'dark-technical', short: 'Dark' },
        { id: 'light-ide', short: 'Light' },
        { id: 'neutral-professional', short: 'Neutral' },
      ].map((t) => ({
        short: t.short, onClick: this.setTheme(t.id),
        bg: s.theme === t.id ? 'var(--accent)' : 'transparent',
        fg: s.theme === t.id ? 'var(--text-on-accent)' : 'var(--text-secondary)',
      })),
      curNum: cur.num, curTitle: cur.title, curIntent: cur.intent,
      icArrowR: this.lucideIcon('arrow-right', 13, 'var(--text-on-accent)'),
      icArrowL: this.lucideIcon('arrow-left', 13, 'var(--text-on-accent)'),
      icX: this.lucideIcon('x', 12, 'var(--danger)'),
      icCheck: this.lucideIcon('check', 12, 'var(--success)'),
      icMin: this.lucideIcon('minus', 12, 'var(--text-secondary)'),
      icSq: this.lucideIcon('square', 11, 'var(--text-secondary)'),
      icClose: this.lucideIcon('x', 12, 'var(--text-secondary)'),
      icChevron: this.lucideIcon('chevron-right', 12, 'var(--text-tertiary)'),
      icFetch: this.lucideIcon('download-cloud', 12), icPull: this.lucideIcon('arrow-down-to-line', 12), icPush: this.lucideIcon('arrow-up-from-line', 12),
      icBranchBtn: this.lucideIcon('git-branch-plus', 12), icStashBtn: this.lucideIcon('inbox', 12),
      icSearch: this.lucideIcon('search', 12, 'var(--text-tertiary)'),
      icRepo: this.lucideIcon('folder-git-2', 12, 'var(--text-tertiary)'),
      icBranch: this.lucideIcon('git-branch', 12, 'var(--text-tertiary)'),
      icTag: this.lucideIcon('tag', 12, 'var(--text-tertiary)'),
      icFile: this.lucideIcon('file-text', 12, 'var(--text-tertiary)'),
      icRemote: this.lucideIcon('cloud', 12, 'var(--text-tertiary)'),
      icRemoteGone: this.lucideIcon('cloud-off', 12, 'var(--warning)'),
      icChevDown: this.lucideIcon('chevron-down', 12, 'var(--text-tertiary)'),
      icStash: this.lucideIcon('inbox', 12, 'var(--text-tertiary)'),
      icList: this.lucideIcon('list', 11, 'var(--text-tertiary)'),
      icColumns: this.lucideIcon('columns-3', 11, 'var(--text-tertiary)'),
      icTree: this.lucideIcon('folder-tree', 11, 'var(--text-on-accent)'),
      icCompare: this.lucideIcon('git-compare', 12, 'var(--text-tertiary)'),
      icFolderPlus: this.lucideIcon('folder-plus', 12, 'var(--text-secondary)'),
      icFolderSearch: this.lucideIcon('folder-search', 12, 'var(--text-tertiary)'),
      icTrash: this.lucideIcon('trash-2', 12, 'var(--danger)'),
      branchTree: BRANCH_TREE.map((b) => {
        const col = b.state === 'gone' ? 'var(--warning)' : b.state === 'remote' ? 'var(--text-tertiary)' : 'var(--text-primary)';
        const icon = b.folder
          ? this.lucideIcon(b.open ? 'chevron-down' : 'chevron-right', 11, 'var(--text-tertiary)')
          : this.lucideIcon(b.icon, 11, b.state === 'gone' ? 'var(--warning)' : b.state === 'remote' ? 'var(--text-tertiary)' : 'var(--text-secondary)');
        return {
          name: b.folder ? b.name + '/' : b.name,
          icon, pad: (8 + b.depth * 11) + 'px',
          dim: b.dim ? '.62' : '1',
          color: b.folder ? 'var(--text-secondary)' : col,
          weight: b.current ? '600' : '400',
          strike: b.state === 'gone' ? 'line-through' : 'none',
          badge: b.badge || '',
          badgeColor: b.state === 'gone' ? 'var(--warning)' : 'var(--text-tertiary)',
          selCls: b.current ? 'selected' : '',
        };
      }),
      branchStates: BRANCH_STATES.map((b) => ({ ...b, glyph: this.lucideIcon(b.icon, 13, b.icon === 'cloud-off' ? 'var(--warning)' : b.icon === 'cloud' ? 'var(--text-tertiary)' : 'var(--text-secondary)') })),
      icAlert: this.lucideIcon('alert-triangle', 13, 'var(--diff-del-text)'),
      isP1: s.page === 'p1', isP2: s.page === 'p2', isP3: s.page === 'p3', isP4: s.page === 'p4',
      isP5: s.page === 'p5', isP6: s.page === 'p6', isP7: s.page === 'p7', isP8: s.page === 'p8', isP9: s.page === 'p9',
      isP10: s.page === 'p10', tasks: TASKS, logRules: LOGRULES, p10rows: P10,
      isP11: s.page === 'p11', isP12: s.page === 'p12', isP13: s.page === 'p13',
      isP14: s.page === 'p14', isP15: s.page === 'p15', isP16: s.page === 'p16',
      isP17: s.page === 'p17', isP18: s.page === 'p18', isP19: s.page === 'p19', isP20: s.page === 'p20',
      dlgsC: this.dlgGroup('C'), dlgsB2: this.dlgGroup('B2'), dlgsF: this.dlgGroup('F'), dlgsPull: this.dlgGroup('PULL'),
      pullSteps: PULLSTEPS, pullErr: PULLERR, isP21: s.page === 'p21',
      panelSpec: PANELSPEC,
      wts: WTS.map((w) => ({
        name: w.name, path: w.path, br: w.br,
        selCls: w.sel ? 'selected' : '',
        color: w.gone ? 'var(--warning)' : 'var(--text-primary)',
        icon: this.lucideIcon(w.gone ? 'alert-triangle' : w.warn ? 'git-commit-horizontal' : 'folder-git-2', 12, w.gone ? 'var(--warning)' : 'var(--text-tertiary)'),
        badge: w.cur ? 'current' : w.gone ? '路徑不存在' : '',
      })),
      iaMap: IAMAP, revisions: REVISIONS, openQ: OPENQ, recents: RECENTS,
      welcomeActs: WELCOME.map((w) => ({ ...w, cls: w.primary ? 'gbm-btn-primary' : 'gbm-btn-secondary' })),
      toolsMenu: TOOLSMENU.map((m) => ({
        label: m.label, note: m.note || '',
        arrow: m.submenu ? this.lucideIcon('chevron-right', 12, 'var(--text-tertiary)') : null,
      })),
      toolsSub: TOOLSSUB.map((m) => ({ label: m.label, color: m.danger ? 'var(--danger)' : 'var(--text-primary)' })),
      fileCtx: FILECTX.map((m) => ({
        label: m.label, note: m.note || '',
        color: m.danger ? 'var(--danger)' : 'var(--text-primary)',
        bg: m.hi ? 'var(--surface-panel-raised)' : 'transparent',
        arrow: m.submenu ? this.lucideIcon('chevron-right', 12, 'var(--text-tertiary)') : null,
      })),
      fileCtxSub: FILECTXSUB.map((m) => ({ label: m.label, note: m.note || '' })),
      icFolderOpen: this.lucideIcon('folder-open', 13, 'var(--text-tertiary)'),
      icCopy: this.lucideIcon('copy', 11, 'var(--text-tertiary)'),
      icPencil: this.lucideIcon('pencil', 12, 'var(--text-secondary)'),
      icCheckWhite: this.lucideIcon('check', 9, 'var(--text-on-accent)'),
      renameValid: RENAMEVALID, multiKeys: MULTIKEYS,
      multiActs: MULTIACTS.map((a) => ({ ...a, color: a.ok === false ? 'var(--text-tertiary)' : 'var(--text-primary)' })),
      multiBranchMenu: MULTIBRANCHMENU.map((m) => ({
        label: m.label, note: m.note || '',
        op: m.dis ? '.45' : '1',
        color: m.danger ? 'var(--danger)' : 'var(--text-primary)',
      })),
      multiCommits: MULTICOMMITS.map((c) => ({
        msg: c.msg, sha: c.sha, lane: 'var(--graph-lane-' + c.lane + ')',
        selCls: c.sel ? 'selected' : '',
      })),
      prefNav: PREFNAV.map((n, i) => ({ label: n, cls: i === 1 ? 'active' : '' })),
      baseFolders: BASEFOLDERS, p11rows: P11, changeViews: CHANGEVIEWS, compares: COMPARES, terminals: TERMINALS,
      icTerminal: this.lucideIcon('terminal', 12, 'var(--text-tertiary)'),
      icChevUp: this.lucideIcon('chevron-up', 12, 'var(--text-tertiary)'),
      icErr: this.lucideIcon('x-circle', 12, 'var(--danger)'),
      icOk: this.lucideIcon('check-circle-2', 12, 'var(--success)'),
      icWarn: this.lucideIcon('alert-triangle', 12, 'var(--warning)'),
      icLoader: this.lucideIcon('loader-circle', 12, 'var(--accent)'),
      icErrBig: this.lucideIcon('x-circle', 17, 'var(--danger)'),
      errCases: ERRCASES,
      histRows: HIST.map((h) => ({ ...h, selCls: h.sel ? 'selected' : '' })),
      graphRows: GRAPH_ROWS.map((r) => ({
        ...r, selCls: r.sel ? 'selected' : '',
        chips: r.chips.map((c) => ({ ...c, icon: c.synced ? this.lucideIcon('cloud', 9.5, 'var(--text-on-accent)') : null })),
        authorStyle: r.me
          ? 'font-size:9.5px;flex-shrink:0;width:44px;color:var(--accent);font-weight:600'
          : 'font-size:9.5px;flex-shrink:0;width:44px;color:var(--text-tertiary)',
      })),
      graphLines: GRAPH_LINES, graphDots: GRAPH_DOTS,
      graphCols: GRAPH_COLS.map((c) => ({
        label: c.label,
        box: c.on
          ? 'width:12px;height:12px;flex-shrink:0;border-radius:3px;border:1.5px solid var(--accent);background:var(--accent)'
          : 'width:12px;height:12px;flex-shrink:0;border-radius:3px;border:1.5px solid var(--border-strong);background:var(--surface-panel)',
        opacity: c.locked ? '.5' : '1',
        hint: c.locked ? '固定' : '',
      })),
      p2rows: P2, p3rows: P3, p8rows: P8,
      menuCols: MENUS.map((m) => ({ title: m.title, items: m.items.map((i) => ({ label: i.label, key: i.key || '', color: i.color || 'var(--text-primary)', arrow: i.submenu ? this.lucideIcon('chevron-right', 12, 'var(--text-tertiary)') : null })) })),
      ctxMenus: CTX.map((c) => ({
        id: c.id, title: c.title, target: c.target,
        items: this.menuItems(c.items),
        hasSub: !!c.hasSub, sub: c.sub ? this.menuItems(c.sub) : [],
      })),
      dialogs: DIALOGS.map((d) => ({ ...d, key: d.key || '—' })),
      scopes: SCOPES,
      stateRows: STATES, splitters: SPLITTERS, msgRows: MSGS,
      prevPage: this.step(-1), nextPage: this.step(1), goP5: this.go('p5'), goP2: this.go('p2'), goP10: this.go('p10'), goP14: this.go('p14'),
    };
  }
}

