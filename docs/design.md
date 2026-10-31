# agino-tiling 设计文档

版本：0.1.1（2026-10-31）。决策来源：agino infra `docs/decisions.md` D-168、D-169；P0 原型与实测见 infra `docs/tiling.md` 8.1。本文是实现和测试的依据；实现中发现与本文不符时，先改本文再改代码。

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

`desktopId` 是 KWin 虚拟桌面的 `id`（UUID 字符串，KWin 存在 kwinrc 里，跨登录不变）。小程序不清理已删除工作区的 ID；脚本忽略不存在的 ID。

### 2.2 脚本的全局快捷键（kglobalaccel 组件 `kwin`）

| 名称 | 默认键 | 作用 |
|---|---|---|
| `AginoTilingToggle` | Meta+Y | 当前工作区平铺开/关（任务栏按钮也调用它） |
| `AginoTilingFocusNext` / `AginoTilingFocusPrevious` | Meta+J / Meta+K | 焦点到下一个/上一个平铺窗口 |
| `AginoTilingMoveNext` / `AginoTilingMovePrevious` | Meta+Shift+J / Meta+Shift+K | 当前窗口与下一个/上一个交换位置 |
| `AginoTilingSwapMaster` | Meta+Return | 与主区交换；当前就是主区时与堆栈第一个交换 |
| `AginoTilingShrinkMaster` / `AginoTilingGrowMaster` | Meta+Ctrl+H / Meta+Ctrl+L | 主区宽度 −5% / +5%，范围 15%–85% |
| `AginoTilingNextLayout` | Meta+Space | 主区加堆栈 → 多列 → 单窗口满屏 → 回到开头 |
| `AginoTilingMonocle` | Meta+F | 单窗口满屏开/关（关时回到之前的布局） |
| `AginoTilingToggleFloat` | Meta+Shift+Space | 当前窗口浮动 / 回到平铺 |
| `AginoTilingSync` | 无 | 小程序启动时调用：脚本重新 `GetTiledDesktops`、应用、`CurrentChanged` |

默认键依据见 infra `tiling.md` 4A（已核对 DDE、KWin、fcitx5 无冲突）。

kglobalaccel 把每个动作的当前按键写进用户的 `~/.config/kglobalshortcutsrc`，并由常驻的 kglobalacceld 保存在内存里；脚本里的默认键只在动作第一次注册时生效。**以后的版本若改默认键，已安装的用户不会跟着变**，要迁移就得另写迁移（KDE 的做法是 kconf_update），不能只改这里的默认值。

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

权限 readwrite，visibility private，按用户保存。小程序用 DTK 的 `DConfig` 读写（appid 的选法见实现；安装路径与之对应）。

## 4. 布局引擎（脚本）

### 4.1 哪些窗口参与

参与：`normalWindow`，且不是 transient、dialog、splash、utility、specialWindow；不是最小化、全屏、置顶（keepAbove）、skipTaskbar；可移动、可缩放；不是固定尺寸（最小尺寸等于最大尺寸）；只在一个工作区上；不在用户浮动集合里；`resourceClass` 不在配置 `floatingClasses`（kwinrc `[Script-agino-tiling]`，逗号分隔，默认空）里。

### 4.2 布局（每个工作区、每块屏幕各自计算；工作区之间互不影响）

区域 = `Workspace.clientArea(KWin.PlacementArea, output, desktop)` 四周留间隙 `gap`（kwinrc `gap`，默认 8）。

- **主区加堆栈**（默认）：1 个窗口铺满；多于 1 个时，第一个是主区（宽度 = 可用宽 × `masterRatio`，默认 0.55，按工作区记），其余在右侧纵向等分。
- **多列**：等宽并排。
- **单窗口满屏**：所有窗口都占满区域，焦点窗口在最上面。

新窗口追加到顺序末尾（不打扰主区）。窗口关闭、最小化、全屏、浮动、换工作区或换屏后重新布局。

### 4.3 最小尺寸放不下

先按布局放，再读回 KWin 实际给出的几何；若某个窗口被 KWin 保持得比格子大（与别的窗口重叠），该屏改用"堆叠退让"。不按窗口声明的 `minSize` 判断：X11 上 KWin 并不强制大多数窗口（包括 DTK 窗口）的 WM_NORMAL_HINTS 最小尺寸，tile1 上声明最小宽 610 的终端被正常缩到 565（i3、sway 平铺时同样忽略这个提示）。退让时：主区照常；堆栈里的窗口都放在同一个矩形里（高度取堆栈区全高），焦点所在的那个在最上面。日志记一条 warning。

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

## 5. 任务栏小程序

- `DAppletDock` 子类；`dockOrder` 14（多任务视图是 15）；`dockItemInfo` 的 name/itemKey/settingKey 为 `agino-tiling`，displayName 为"平铺"（可翻译），用户可在任务栏设置里隐藏。
- 属性 `tiling`（bool，NOTIFY）；`Q_INVOKABLE toggle()`。
- 图标（DCI）：
  - 按钮：开/关两种状态，`agino-tiling-on`、`agino-tiling-off`，装到 `/usr/share/dsg/icons/`。两种状态靠形状区分，不只靠颜色：开是靛蓝底上的"主区加堆栈"，关是灰底上两个重叠的浮动窗口。风格对齐多任务视图图标：256 尺寸、3 倍、全彩，深色模式链接到浅色。
  - 任务栏设置（控制中心）：`dcc-agino-tiling`，装到 `/usr/share/dde-dock/icons/dcc-setting/`。控制中心按 `dcc-<name>.dci` 自己找到它，`dccIcon` 填这个路径作后备。16 尺寸、3 倍、调色板前景层，跟随主题着色。
  - 源文件 `data/icons/src/*.svg`，用 `data/icons/make-dci.py` 生成 .dci，两者都入库。
- 悬停提示："平铺：已开启/已关闭（Super+Y）"。
- 注册服务失败（另一个实例已占用）只记 warning，按钮仍可点击（快捷键路径不依赖服务）。

## 6. 翻译

agino 的 14 种语言（ar、de、en、es、fr、it、ja、ko、pt_BR、ru、uk、zh_CN、zh_HK、zh_TW），用 Qt `.ts`，范围是小程序的可见文字。KWin 快捷键的说明文字只在 KWin 的快捷键设置里出现（DDE 没有这个界面），保持英文。

## 7. 测试

- 单元测试：布局计算写成纯 JS 函数（`src/kwin-script/contents/code/layout.js`），用 `qmltestrunner` 测各布局、间隙、最小尺寸退让、交换。
- 虚拟机：`tests/vm/` 的脚本（来自 P0）扩展到本文各条行为，在 DDE X11 会话里跑。
- 真机：多屏、HiDPI、睡眠唤醒（P1 末尾）。
