# GTSAM 4.3.0 Windows 支持交接

## 结论

只改了一个文件：`packages/g/gtsam/xmake.lua`。Windows 分支在 4.3.0 上真正卡住的不是符号/链接问题，
而是**源码编码**：4.3.0 的头文件引入了 UTF-8 数学符号（如 `gtsam/base/MatrixLieGroup.h:69-70` 的
`⊗` U+2297），MSVC 在中文代码页 936 下报 `warning C4819`，而 GTSAM 在 MSVC 上默认
`GTSAM_BUILD_WITH_WERROR=ON`（`cmake/GtsamBuildTypes.cmake:90-94, 125-126`），把它升级成
`error C2220`，构建在 14/288 就停了。

修法是在 Windows 上追加 `-DCMAKE_CXX_FLAGS_INIT=/utf-8`（`:105-111`），让 MSVC 按 UTF-8 读源码。
**没有**关掉 `/WX`——那会掩盖其他真实警告。

验证环境：Windows 11 / x64 / MSVC 14.52（VS 2026）/ CMake 4.3.3 / Ninja / xmake 3.1.2。

## 为什么是 `CMAKE_CXX_FLAGS_INIT`

直接用 `-DCMAKE_CXX_FLAGS=/utf-8` 会覆盖 CMake 在 `project()` 时写入的平台默认值。实测最终
`CMakeCache.txt` 中保留正确的值：

```
CMAKE_CXX_FLAGS:STRING=/utf-8 /DWIN32 /D_WINDOWS /GR /EHsc
GTSAM_BUILD_WITH_WERROR:BOOL=ON
BUILD_SHARED_LIBS:BOOL=ON
```

即 `/utf-8` 被前置追加，平台 flags 一个没丢，`/WX` 也还在。

## 其他 Windows 相关的核对结果

| 项 | 位置 | 4.3.0 上的结论 |
| --- | --- | --- |
| `LPInitSolver.cpp` 排除 | recipe `:55-99` | 补丁仍生效：4.3.0 的 `gtsam_unstable/CMakeLists.txt` 用 `excluded_sources` 列表，gsub 把该文件加进去，日志确认 `Patched ... excluded LPInitSolver.cpp` |
| `/FORCE:MULTIPLE` | recipe `:113-119` | 4.3.0 顶层 `CMakeLists.txt:74-78` 在 MSVC 下**自己**设置并覆盖 `CMAKE_*_LINKER_FLAGS`，所以 recipe 这几行对 4.3 是冗余；保留作为 4.2.x 的 fallback，无副作用 |
| Cephes 链接顺序 | recipe `:24-29` | 4.3 拆出 `cephes-gtsam`，手工指定 `gtsam_unstable → gtsam → cephes-gtsam` 顺序仍然必要 |
| `Dbghelp` | recipe `:31-36` | 4.3 `gtsam/CMakeLists.txt:293` 仍以 PRIVATE 链接，静态库消费方需要显式 `dbghelp` |
| TBB | recipe `:18-22` | Windows 继续跳过，`GTSAM_WITH_TBB=OFF` |

`on_install` 的平台列表本来就包含 `windows`（`:39`），`add_versions("4.3.0", ...)` 在 `:10` 已有，
这两处不需要改。

## 验证结果

验证工程（临时目录）：

```lua
add_requires("gtsam 4.3.0", {system = false, configs = {shared = true}})
target("gtsam_probe")
    set_kind("binary")
    set_languages("c++17")
    add_files("main.cpp")
    add_packages("gtsam")
```

`main.cpp` 用包 `on_test` 同样的片段（`BetweenFactor<Point2>` + `noiseModel::Unit`）。

| 项目 | 结果 |
| --- | --- |
| `xmake f -c -p windows -a x64 -m release -y` | **通过**，含 `on_test` 片段；日志 `=> install gtsam 4.3.0 .. ok` |
| `xmake build -y -v gtsam_probe` | **通过**，链接行含 `gtsam_unstable.lib gtsam.lib cephes-gtsam.lib dbghelp.lib` 及 boost 库 |
| `xmake run gtsam_probe` | **通过**，`RUN_EXIT=0` |

动态库确实生成（`dumpbin /exports`）：

| DLL | 大小 | 导出符号 |
| --- | --- | --- |
| `bin/gtsam.dll` | 7.7 MB | 9589 |
| `bin/gtsam_unstable.dll` | 1.2 MB | 633 |
| `bin/cephes-gtsam.dll` | 33 KB | 23 |

对应 `lib/gtsam.lib`（5.9 MB）、`lib/gtsam_unstable.lib`（379 KB）、`lib/cephes-gtsam.lib`（6.4 KB）
都生成。C4819 / C2220 / LNK2005 计数均为 0。

## 已知边界

- **4.2.2 未完整回归**：本机 MSVC 在全量构建中出现 `cl.exe` CPU=0 僵死（与 ecal 那次同类），
  终止后 xmake 工具链探测跑到 mingw/vcpkg，装出了配置错误的静态包。已把包目录恢复到验证前状态。
  `/utf-8` 只是追加编译 flags，对 4.2.x 的纯 ASCII 源码无语义影响，但不等于实测通过。
  建议在 CI 或另一台机器上补一次 4.2.x 回归。
- **mingw / clang-cl / Linux / debug 未回归**：改动只在 `is_plat("windows")` 分支内。
- **本机 `/MP` 僵死**：GTSAM 在 `cmake/GtsamBuildTypes.cmake:121` 注入 `/MP`，配合 `/FS` 共享 PDB，
  本机偶发编译进程僵死，终止后增量续跑可完成。这是环境问题，不是 recipe 缺陷。
- `add_requires` 必须带 `system = false`，否则会命中系统里的 gtsam，验证不到这份 recipe。

改动范围：`packages/g/gtsam/xmake.lua` 与本文档。交付状态以 git log 为准。
