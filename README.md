# agino-tiling

agino 的平铺窗口模式：在 DDE + KWin（X11）上，按工作区一键打开自动平铺。

- 新开的窗口自动进入布局（主区加堆栈、多列、单窗口满屏），关闭后其余窗口自动铺满。
- 任务栏上的"平铺"按钮（多任务视图左边）切换当前工作区，并显示状态；也可以用 Super+Y。
- 快捷键沿用主流平铺窗口管理器的习惯（Super+J/K、Super+Return、Super+Space 等，见 [docs/design.md](docs/design.md)）。

组成：KWin 脚本（布局引擎）、dde-shell 任务栏小程序、DConfig 定义。目标环境：agino 26（Debian 13 + DDE，X11）。当前状态：P1 开发中。

## 构建

构建依赖：cmake、qt6-base-dev、qt6-declarative-dev、qt6-tools-dev、qt6-l10n-tools、libdtk6core-dev、libdtk6gui-dev、libdde-shell-dev、libdde-shell-dock-dev。

```
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
sudo cmake --install build
```

许可证：GPL-3.0-or-later（见 [COPYING](COPYING)）。
