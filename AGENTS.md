# AGENTS.md

QueMusic —— C++20 / Qt 6.10.3 / QML 写的跨平台桌面音乐播放器（Windows / macOS / Linux）。
C++ 与工作线程负责 I/O、解码、计算，QML 只做呈现（渲染走 Qt RHI）。
贡献流程见 `CONTRIBUTING.md`；插件（歌词界面 / 功能）契约在外部仓库 QuePlugins。

## 目录与职责

| 路径 | 内容 |
| --- | --- |
| 根 | `main.cpp`（QApplication、QML 引擎、C++ 单例注册）、`main.qml`、`SettingsView.qml` |
| `components/` | 可复用 QML 组件与跨模块单例（`pragma Singleton`） |
| `pages/` `layout/` `lyricsui/` | 页面、布局壳、可整体替换的歌词界面 |
| `cpp/` | C++ 实现：`audio/`（音频引擎、FFmpeg 解码、DSP）、`webdav/`、`plugins/`（插件宿主） |
| `api/` | 网易云 / 酷狗 / Bilibili 适配层 + 内置 `QCloudMusicApi`（Crypto++ 随仓库提供，不联网下载） |
| `cmake/external/` | 依赖统一入口：zlib / taglib / qwindowkit / ffmpeg，各自导出 `quemusic::*` target |
| `shaders/` `resources/` | 着色器（构建期编译为 .qsb）与随 QML 模块注册的静态资源 |
| `ThirdParty/` | 子模块：QWindowKit（无边框窗口）、TagLib（音频标签） |

QML 模块 URI 是 `QueMusic`（`main.qml` 本身参与注册，不是 `qrc:/` 相对加载）。

## 本机开发环境（已实测可用）

- Qt **6.10.3** 在 `~/Qt/6.10.3/gcc_64`。不要装 apt 的 qt6 混用：本机没装，且版本与官方包不一致，Wayland/平台插件会跟官方 Qt 的 ABI 打架。
- 换机或重装：`bash ~/Qt/fetch-qt-6.10.3.sh`。`aqtinstall` 在本机对每份归档都会报 checksum 错误（下载链路问题，不是镜像坏了），该脚本改用 curl 逐包下载官方归档 + `bsdtar` 解压，幂等可重跑。
- 本机没有系统 `libav*-dev`（安装要 sudo），所以**必须**开 `-DQUEMUSIC_FFMPEG_USE_QT=ON`：让 `cmake/external/ffmpeg.cmake` 使用 Qt 自带的 FFmpeg 7.1.3（`$QTDIR/lib/libavcodec.so.61`）。否则落到 pkg-config 分支并 FATAL_ERROR。

```bash
QTDIR=$HOME/Qt/6.10.3/gcc_64
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=$QTDIR -DQUEMUSIC_FFMPEG_USE_QT=ON \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -j"$(nproc)"          # 产物：build/bin/QueMusic
```

自检（与 CI 同一套，改完必跑）：

```bash
QTDIR=$HOME/Qt/6.10.3/gcc_64
$QTDIR/bin/qmllint -I build $(find . -name '*.qml' \
  -not -path './build/*' -not -path './ThirdParty/*' -not -path './api/QCloudMusicApi/*')
bash tests/smoke-stderr.sh build/bin/QueMusic 12   # 离屏启动一次；QML / 渲染错误即失败
```

- `just` 本机没装；`CMakePresets.json` 的构建目录是 `build/<presetName>`（与 CI、上面命令的 `build/` 不同）——排查问题以 `build/` 为准，别在两个目录间来回切。
- 仓库没有单元测试，验证就是「构建 + qmllint + 冒烟 + 真跑一次」。

## 改代码时要记住

- **新增 C++ 文件必须手工加进 `CMakeLists.txt` 里 `qt6_add_qml_module(... SOURCES ...)`**，没有 glob，不加就不参与编译。QML 则是按目录 `GLOB_RECURSE`（`CONFIGURE_DEPENDS`）收的，加 QML 不用改 CMake。
- 新增 QML 单例：文件写 `pragma Singleton`，并把路径补进 `set_source_files_properties(... QT_QML_SINGLETON_TYPE TRUE)`。
- 改了 `.frag` / `.vert` 必须重新构建（`qt6_add_shaders` 生成 .qsb）：Qt 6 不做运行时着色器编译，忘了就是特效静默消失。
- C++ 文件带 `// SPDX-License-Identifier: Apache-2.0` 头；暴露给 QML 用 `QML_ELEMENT` / `QML_SINGLETON`；构造函数不要给 QObject 参数默认值（QML 单例否则走默认构造分支，实例化逻辑不执行）。
- 耗时操作不要放 GUI 线程；网络请求统一走 `api/ApiHttp.h`（带超时）。
- 提交信息中文，写清「改了什么 + 为什么」；CHANGELOG 按 Keep a Changelog。

## 平台差异（在 Linux 上开发时最容易误判的几处）

- `ffmpeg/{include,lib,bin}` 里的 dll 与导入库只服务 Windows；Linux / macOS 走 Qt 自带（本机即此路）或系统 pkg-config。
- `icon.rc`、`cpp/WindowsSmtcManager.*`、WebDAV 的 DPAPI 加密都是 WIN32 专属。无托盘环境下会打印「当前平台不支持系统托盘，关闭窗口将直接退出」——属正常。
- `qmltc` 默认关闭，原因写在 `cmake/qmltc.cmake` 顶部（本工程 QML 依赖 QtQuick.Controls 且位于模块子目录，qmltc 编不了）——不要为了它改目录结构。
- Linux 上 Qt Multimedia 会打印 `No sample format supported found for device "dummy_source"`，那是缺少录音设备时的噪声，与播放无关。
