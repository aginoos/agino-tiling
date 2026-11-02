# agino-tiling 设计文档

版本：0.1.5（2026-11-02）。决策来源：agino infra `docs/decisions.md` D-168、D-169、D-171、D-172、D-188（4.3 的限幅和自动浮动、4.1 的弹窗验证和模态窗口）、D-191（4.8 记住窗口尺寸）；P0 原型与实测见 infra `docs/tiling.md` 8.1。本文是实现和测试的依据；实现中发现与本文不符时，先改本文再改代码。

## 1. 目标与范围

在 agino 26（Debian 13 + DDE，X11，KWin 6.3）上提供**按工作区开关的自动平铺**：

- 新开的窗口自动进入布局，其他窗口让位；关闭后剩下的铺满。
- 任务栏上一个按钮（多任务视图左边）一键切换当前工作区的平铺，并始终显示状态。
- 不用这个功能的用户不受影响：默认所有工作区都不平铺。

| 组件 | 位置 | 说明 |
|---|---|---|
| KWin 脚本 `agino-tiling` | `src/kwin-script/`，安装到 `/usr/share/kwin/scripts/agino-tiling/` | 布局引擎、快捷键、接管快速平铺；QML 声明式脚本，跑在 kwin 进程里 |
| 任务栏小程序 `org.agino.ds.dock.tiling` | `src/dock-applet/`，`.so` 装到 `/usr/lib/<multiarch>/dde-shell/`，QML 包装到 `/usr/share/dde-shell/org.agino.ds.dock.tiling/` | C++ `DAppletDock`；按钮、状态显示、会话总线对象 `org.agino.Tiling1`、DConfig 持久化 |
| DConfig `org.agino.tiling` | `data/dconfig/` | 记住哪些工作区在平铺 |

不在范围内：设置界面（P2）；Wayland（脚本本身可用，但未测试）；多个主区窗口。

## 2. 组件之间的协议

KWin 脚本只能**发起**会话总线调用（`DBusCall`），不能导出对象，也连不到系统总线（DConfig 的管理服务在系统总线上）。小程序可以调用脚本的全局快捷键（kglobalaccel `invokeShortcut`，组件 `kwin`）。协议因此是：

### 2.1 小程序导出：`org.agino.Tiling1`

服务名 `org.agino.Tiling1`，对象 `/org/agino/Tiling1`，接口 `org.agino.Tiling1`，会话总线。所有参数都是基本类型（KWin 的 `DBusCall` 不会生成 `v` 类型参数）。

| 方法 | 调用方 | 含义 |
|---|---|---|
| `CurrentChanged(s desktopId, b tiled)` | 脚本 | 当前工作区或它的状态变了（切换工作区、开关平铺、脚本启动或同步后）。小程序只更新按钮，**不写**持久化 |
| `TilingChanged(s desktopId, b tiled)` | 脚本 | 用户开关了某个工作区的平铺（按钮、快捷键）。小程序更新持久化集合 |
| `GetTiledDesktops() → as` | 脚本 | 取回持久化的平铺工作区 ID 列表 |
| `GetWindowSizes() → s` | 脚本 | 取回持久化的"记住的窗口尺寸"表（JSON 文本，4.8） |
| `SetWindowSizes(s json)` | 脚本 | 保存这张表；小程序检查格式和大小，不合格的拒绝并记一条 warning |

`desktopId` 是 KWin 虚拟桌面的 `id`（UUID 字符串，KWin 存在 kwinrc 里，跨登录不变）。小程序不清理已删除工作区的 ID；脚本忽略不存在的 ID。

### 2.2 快捷键：DDE 快捷键服务按键，脚本动作执行（D-172）

按键由 dde-services 的快捷键服务负责（`dde-services` 源码 `src/plugin-qt/shortcut/DEVELOPER_GUIDE.md`），所以快捷键出现在控制中心"键盘 → 快捷键"的"平铺"分类里，用户可以改键，冲突也由服务检测和提示。

- **定义**：`data/shortcuts/`，由 `make-configs.py` 生成，生成结果入库。
  - 注册文件 `agino-tiling.ini` 装到 `/usr/share/deepin/org.deepin.dde.keybinding/`。`SubPaths` 用逗号分隔（QSettings 列表）。开发文档写的是分号，但 QSettings 把分号当作注释的开始，服务只会读到第一项。
  - 每个快捷键一份 DConfig（`org.deepin.dde.keybinding` 下的 `agino-tiling.shortcut.<名称>`）：
    - 字段：appId `agino-tiling`，分类 `Tiling`，`modifiable` 为真。
    - 触发方式是命令：`dbus-send` 调用 kglobalaccel 的 `invokeShortcut <脚本动作>`（组件 `kwin`）。
  - 名称的翻译用上下文 `agino-tiling`，装到 `/usr/share/deepin/org.deepin.dde.keybinding/translations/agino-tiling/`。
- **脚本动作**：KWin 脚本的 `ShortcutHandler` 都不设按键，只保留名称，供上面的命令、任务栏按钮（`AginoTilingToggle`）和小程序启动时的同步（`AginoTilingSync`）调用。
- **生效**：dde-services 对注册目录声明了 dpkg 触发器，装包、卸载后所有已登录会话自动重载（`ReloadConfigs`）。

| 名称（DConfig 子路径后缀） | 脚本动作 | 默认键 | 触发 | 作用 |
|---|---|---|---|---|
| `toggle` | `AginoTilingToggle` | Meta+Y | 松开 | 当前工作区平铺开/关 |
| `focus-next` / `focus-previous` | `AginoTilingFocusNext` / `...Previous` | Meta+J / Meta+K | 按下 | 焦点到下一个/上一个平铺窗口 |
| `move-next` / `move-previous` | `AginoTilingMoveNext` / `...Previous` | Meta+Shift+J / Meta+Shift+K | 按下 | 当前窗口与下一个/上一个交换位置 |
| `swap-master` | `AginoTilingSwapMaster` | Meta+Return | 按下 | 与主区交换；当前就是主区时与堆栈第一个交换 |
| `shrink-master` / `grow-master` | `AginoTilingShrinkMaster` / `...GrowMaster` | Meta+Ctrl+H / Meta+Ctrl+L | 按下 + 按住连发 | 主区宽度 −5% / +5%，范围 15%–85% |
| `next-layout` | `AginoTilingNextLayout` | Meta+Space | 松开 | 主区加堆栈 → 多列 → 单窗口满屏 → 回到开头 |
| `monocle` | `AginoTilingMonocle` | Meta+F | 松开 | 单窗口满屏开/关（关时回到之前的布局） |
| `float` | `AginoTilingToggleFloat` | Meta+Shift+Space | 松开 | 当前窗口浮动 / 回到平铺 |
| — | `AginoTilingSync` | 无 | — | 小程序启动时调用：脚本重新 `GetTiledDesktops`、应用、`CurrentChanged` |

默认键依据见 infra `tiling.md` 4A（已核对 DDE、KWin、fcitx5 无冲突）。deepin 25 上 uos-ai 占用 Meta+Space；agino 不带 uos-ai。

- **改默认键**：用户改过的键存在服务的 DConfig 用户层，没改过的用户随包里的默认值走，不需要迁移。
- **代价**：每次按键多启动一个 `dbus-send` 进程。tile1 实测，从服务发出 `ShortcutActivated` 到 KWin 收到动作约 50 ms。

0.1.0、0.1.1 的脚本动作自带 kglobalaccel 按键，用户的 `~/.config/kglobalshortcutsrc` 里会留着旧按键，与服务抢键。agino 正式发布前不写迁移（infra D-50），测试机手工删掉 `AginoTiling*` 行即可。

### 2.3 时序

- **脚本启动**（登录、KWin 重启）：调用 `GetTiledDesktops`；失败（小程序还没起来）就什么也不做，等 `AginoTilingSync`。
- **小程序启动**（登录、dde-shell 重启）：注册服务后调用 `AginoTilingSync`。
- **点击按钮** = `AginoTilingToggle`：脚本切换当前工作区 → `TilingChanged` → `CurrentChanged`。
- **切换工作区**：脚本 `CurrentChanged`。
- 收到 `GetTiledDesktops` 的结果时，脚本只把列表里的工作区**打开**平铺，不关闭已打开的（避免竞态时把用户刚打开的关掉）。

## 3. 持久化：DConfig `org.agino.tiling`

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `tiledDesktops` | 字符串数组 | `[]` | 平铺中的工作区 ID |
| `windowSizes` | 字符串（JSON 对象） | `{}` | 记住的窗口尺寸，按应用（窗口类）：`[浮动宽, 浮动高, 平铺宽, 平铺高]`，0 表示不知道（4.8）；小程序最多收 128 个应用、64 KB |

权限 readwrite，visibility private，按用户保存。小程序用 DTK 的 `DConfig` 读写（appid 的选法见实现；安装路径与之对应）。

## 4. 布局引擎（脚本）

### 4.1 哪些窗口参与

参与：`normalWindow`，且不是 transient、dialog、splash、utility、specialWindow，也不是 modal（只带模态状态、类型却是普通窗口的"对话框"；窗口运行中变成模态时也重新判断）；不是最小化、全屏、置顶（keepAbove）、skipTaskbar；可移动、可缩放；不是固定尺寸（最小尺寸等于最大尺寸）；只在一个工作区上；不在用户浮动集合里；`resourceClass` 不在配置 `floatingClasses`（kwinrc `[Script-agino-tiling]`，逗号分隔，默认空）里。

弹出窗口的验证（tile1，2026-11-01，平铺开着，看窗口出现时已有窗口有没有被重排）：
- 不参与、不重排：编辑器的打开文件对话框（dialog、transient）和未保存提示（dialog、modal、transient）；终端的右键菜单和 `Qt.Popup`（不是 KWin 管理的窗口）；Qt 对话框（Qt 会自动补 transient）、`Qt.Tool`（utility）、`Qt.SplashScreen`、置顶窗口、DTK `DialogWindow`。
- 参与、会重排：普通窗口；只带 modal 状态、窗口类型是普通且没有 transient 的窗口；无边框的普通窗口（`FramelessWindowHint`）。应用若这样写它的"对话框"，就会被当成新窗口平铺。
- 没有结论：编辑器的设置对话框（Ctrl+, 没有出现新窗口）；控制中心和音乐里的各种弹窗没测。


### 4.2 布局（每个工作区、每块屏幕各自计算；工作区之间互不影响）

区域 = `Workspace.clientArea(KWin.PlacementArea, output, desktop)` 四周留间隙 `gap`（kwinrc `gap`，默认 8）。

- **主区加堆栈**（默认）：1 个窗口铺满；多于 1 个时，第一个是主区（宽度 = 可用宽 × `masterRatio`，默认 0.55，按工作区记），其余在右侧纵向等分。
- **多列**：等宽并排。
- **单窗口满屏**：所有窗口都占满区域，焦点窗口在最上面。

新窗口追加到顺序末尾（不打扰主区）。窗口关闭、最小化、全屏、浮动、换工作区或换屏后重新布局。

### 4.3 最小尺寸放不下

先按布局放，再读回 KWin 实际给出的几何；若某个窗口被 KWin 保持得比格子大（与别的窗口重叠），该屏改用"堆叠退让"。不按窗口声明的 `minSize` 判断：X11 上 KWin 并不强制大多数窗口（包括 DTK 窗口）的 WM_NORMAL_HINTS 最小尺寸，tile1 上声明最小宽 610 的终端被正常缩到 565（i3、sway 平铺时同样忽略这个提示）。退让时：主区照常；堆栈里的窗口都放在同一个矩形里（高度取堆栈区全高），焦点所在的那个在最上面。日志记一条 warning。

缩小和放大主区域的快捷键（`AginoTilingShrinkMaster` / `AginoTilingGrowMaster`）按窗口声明的最小宽度限幅：主区域不窄于主区域窗口的 `minSize.width`，堆栈区不窄于堆栈里最宽的 `minSize.width`，每块屏幕各自算，取最严的。到了限度就停，不报错；已经越过限度时，这个方向的键不再往外走，反方向仍可用。两个最小宽度放不下时不限幅，交给上面的堆叠退让。只有这两个键这样做：布局本身仍不按 `minSize` 判断，窗口数量变化、屏幕变小时按上面的读回几何处理。起因：控制中心声明最小 910，缩小主区域把它压到 380（infra D-188 的真机复现）。纯函数 `ratioLimits`、`adjustedRatio` 在 `layout.js`，有单元测试。

**自动浮动（0.1.4，D-188）**：每次布局前，按窗口声明的最小尺寸（`minSize`）排一遍，放不下格子的窗口自动浮动：先恢复它平铺前的大小，不再参与布局，其余窗口照常平铺；一次只浮动一个（放不下的那个），再对剩下的重新判断，最后一个窗口永远不浮动。浮动状态不记在配置里：每次布局都从头判断，所以窗口关了、屏幕变大、布局换成单窗口以后，它自己回到平铺。和用户手动浮动是两回事：手动浮动的窗口（`userFloating`）不受影响，自动浮动的窗口被拖动后也不会参与交换。这样"堆叠退让"只剩两种情况：KWin 实际保持得比格子大（读回几何，上面的做法）和单窗口放不下。纯函数 `misfit`、`floatedForMinimums` 在 `layout.js`，有单元测试。


### 4.4 进入和退出平铺

进入前记下每个参与窗口的 `frameGeometry`；退出时逐一恢复（窗口仍存在的话）。平铺期间新开的窗口退出时留在当前位置。

### 4.5 用户的移动和缩放

- 拖动结束（`interactiveMoveResizeFinished`）：窗口中心落在另一个平铺窗口的格子里 → 交换顺序；否则弹回原位。
- 主区窗口在右边缘缩放 → 换算成新的 `masterRatio`。
- 其他缩放：弹回。

### 4.6 接管快速平铺和最大化（只在平铺的工作区）

DDE 的 Super+←/→/↑/↓ 经 fakewm 变成 KWin 的快速平铺和最大化。脚本监听参与平铺窗口的快速平铺和最大化状态（KWin 6.3 的具体属性/信号名在实现时核对源码）：

- 快速平铺到左半 → 移到主区；到右半 → 移到堆栈第一个；然后取消快速平铺并重新布局。
- 最大化 → 工作区切到单窗口满屏，这个窗口**保持最大化**。
- 取消最大化（Super+↓）且当前是单窗口满屏 → 回到之前的布局。
- 用其他方式离开单窗口满屏（Super+F、Super+Space）→ 重新布局时取消窗口的最大化。脚本自己取消最大化后 800 ms 内收到的"取消最大化"不当作 Super+↓。
- 关闭平铺时，最大化的窗口保持最大化，不恢复进入平铺前的位置。

0.1.0 在进入单窗口满屏时立刻取消了最大化。这样 fakewm 处理 Super+↓ 时去清除一个本来就没有的状态，KWin 不发信号，脚本也就收不到 Super+↓。0.1.1 改为保持最大化。

不平铺的工作区里一切保持 DDE/KWin 原有行为。

Super+↑/↓ 在 agino 上本来是失效的：dde-daemon 注册的 "Window Absolute Maximize"/"Window Unmaximize" 只有 deepin 的 KWin 分支实现。dde-appearance 1.1.84.5 起由 fakewm 提供（infra D-171）。更早的版本上只有 Super+F 能切换单窗口满屏。

### 4.7 日志

前缀 `agino-tiling:`，warning 级别（info/debug 会被过滤）。只记状态变化和异常，不记每次布局。

### 4.8 记住窗口尺寸（0.1.5，D-191）

起因：应用关窗时自己保存窗口尺寸（如文件管理器的 `WindowState`）。在平铺的工作区里关窗，存下的是格子的尺寸，之后在不平铺的工作区打开，窗口就偏小。

脚本按应用（`resourceClass` 小写）记两个尺寸，`sizes[app] = [浮动宽, 浮动高, 平铺宽, 平铺高]`（0 = 不知道）：

- **浮动尺寸**：最近一次不在布局里的尺寸。记录的时机：① 不在布局里的新窗口出现 400 ms 后（应用自己请求的尺寸；等一会儿是因为有的应用显示后才恢复尺寸），但尺寸和"平铺尺寸"相近时不记（那是被存小了的尺寸）；② 用户在不平铺时移动或缩放窗口结束时；③ 不在布局里的窗口关闭时（同时清除平铺尺寸，用户自己的选择优先，所以能自我纠正）；④ 在布局里关窗而浮动尺寸还不知道时，用平铺前保存的几何（`saved`）顶替。
- **平铺尺寸**：在布局里关窗时窗口的框架几何尺寸。
- **恢复**：不在布局里的新窗口出现 400 ms 后，若它的尺寸与平铺尺寸相差不超过 6 像素（`SIZE_TOLERANCE`，容差为装饰和缩放取整留的）且浮动尺寸已知，就改成浮动尺寸：保持窗口中心，限制在窗口所在屏幕、工作区的可用范围内（窗口比可用范围大时取可用范围的大小），然后清除平铺尺寸。
- **不处理**：对话框、transient、工具窗、启动画面、模态窗口、不可缩放或固定大小的窗口、例外列表（`floatingClasses`）里的类；最大化和全屏的窗口既不记也不改；在布局里新开的窗口照常排进布局。自动浮动的窗口算"不在布局里"。
- **持久化**：表经小程序存进 DConfig `windowSizes`（2.1、3），脚本启动和小程序启动（`AginoTilingSync`）时取回，本次已记的优先；每次变化 500 ms 后保存（关窗后会话可能很快结束）；最多 64 个应用，超出时丢最久没用的；小程序不在时不保存、不报错。纯函数 `sizesClose`、`restoredRect`、`remember`、`mergeSizes`、`parseSizes` 在 `layout.js`，有单元测试。
- **已知风险**：窗口可能先以小尺寸出现再变大（脚本在 400 ms 后才处理）；应用若在 400 ms 之后才恢复自己的尺寸，会和脚本打架（关窗时再次纠正）；按尺寸匹配是推断，应用自己保存的尺寸碰巧和平铺尺寸相近时会误判。测到的结果见 infra `docs/tiling.md` 8.7。

## 5. 任务栏小程序

- `DAppletDock` 子类；`dockOrder` 14（多任务视图是 15）；`dockItemInfo` 的 name/itemKey/settingKey 为 `agino-tiling`，displayName 为"平铺"（可翻译），用户可在任务栏设置里隐藏。
- 属性 `tiling`（bool，NOTIFY）；`Q_INVOKABLE toggle()`。
- 图标（DCI）：
  - 按钮：开/关两种状态，`agino-tiling-on`、`agino-tiling-off`，装到 `/usr/share/dsg/icons/`。两种状态靠形状区分，不只靠颜色：开是靛蓝底上的"主区加堆栈"，关是灰底上两个重叠的浮动窗口。风格对齐多任务视图图标：256 尺寸、3 倍、全彩，深色模式链接到浅色。
  - 任务栏设置（控制中心）：`dcc-agino-tiling`，装到 `/usr/share/dde-dock/icons/dcc-setting/`。控制中心按 `dcc-<name>.dci` 自己找到它，`dccIcon` 填这个路径作后备。16 尺寸、3 倍、调色板前景层，跟随主题着色。
  - 源文件 `data/icons/src/*.svg`，用 `data/icons/make-dci.py` 生成 .dci，两者都入库。
- 悬停提示："平铺：已开启/已关闭（按键）"。按键是悬停时向快捷键服务（`GetShortcut agino-tiling.shortcut.toggle`）取的当前值，用户在控制中心改键后跟着变；取不到时只显示状态。
- 注册服务失败（另一个实例已占用）只记 warning，按钮仍可点击（快捷键路径不依赖服务）。

## 6. 翻译

agino 的 14 种语言（ar、de、en、es、fr、it、ja、ko、pt_BR、ru、uk、zh_CN、zh_HK、zh_TW），用 Qt `.ts`。翻译范围：
- 小程序的可见文字：`src/dock-applet/translations/`。
- 控制中心里显示的快捷键名称和分类名：`data/shortcuts/translations/`，上下文 `agino-tiling`。

KWin 脚本动作的说明文字不在 DDE 的任何界面出现，保持英文。

## 7. 测试

- 单元测试：布局计算写成纯 JS 函数（`src/kwin-script/contents/code/layout.js`），用 `qmltestrunner` 测各布局、间隙、最小尺寸退让、交换。
- 虚拟机：`tests/vm/` 的脚本（来自 P0）扩展到本文各条行为，在 DDE X11 会话里跑。`run-ddekeys.sh` 逐个按真实按键，核对快捷键服务的 `ShortcutActivated` 和对 kglobalaccel 的 `invokeShortcut`，再测按住连发和经服务改键。
- 真机：多屏、HiDPI、睡眠唤醒（P1 末尾）。
