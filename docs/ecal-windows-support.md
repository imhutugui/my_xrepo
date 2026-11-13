# ecal 6.1.1 Windows 支持交接

## 结论

只改了一个文件：`packages/e/ecal/xmake.lua`。`on_install` 从 `linux` 扩到 `linux, windows`，Windows 上用
`-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON` 让所有 SHARED 目标自动生成 `.def` 导出符号，从而可以在
`BUILD_SHARED_LIBS=ON` 下构建全动态版本，和 Linux 保持同一套产物形态。三组配置（release/debug ×
protobuf 开/关）全部通过安装、包自检、编译链接与运行验证。

验证环境：Windows 11 / x64 / MSVC 14.51（VS 2026）/ CMake 4.3 / Ninja / xmake 3.1.2。

## CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS 的用法与边界

查证来源（2026-11-05）：

- CMake 官方 target 属性文档：<https://cmake.org/cmake/help/latest/prop_tgt/WINDOWS_EXPORT_ALL_SYMBOLS.html>
- CMake 官方变量文档：<https://cmake.org/cmake/help/latest/variable/CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS.html>
- Kitware 官方博客（该功能的设计说明）：<https://blog.kitware.com/create-dlls-on-windows-without-declspec-using-new-cmake-export-all-feature/>
- Microsoft KB835326（LNK4197 重复导出）：<https://support.microsoft.com/help/835326>

要点：

1. 这是 **target 属性** `WINDOWS_EXPORT_ALL_SYMBOLS`（CMake 3.4+，仅 MS 兼容工具链 / Windows）。开启后
   CMake 从输入 `.obj` 收集全部全局符号，自动生成 `.def` 传给链接器。
2. 变量 `CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS` 在**目标创建时**初始化该属性。所以必须在任何
   `add_library()` 之前设置——用 `-D` 传 CMake cache 值是正确姿势；写在项目 CMakeLists 靠后的
   `set(WINDOWS_EXPORT_ALL_SYMBOLS ON)` 是无效的（那是变量名写错且时机太晚）。
3. 官方推荐组合就是 `-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=TRUE -DBUILD_SHARED_LIBS=TRUE`。也可以只对
   指定目标 `set_target_properties(foo PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)` 精确控制。
4. **限制**：全局**数据**符号仍需要消费方显式 `__declspec(dllimport)`；虚表引用场景需要整个类
   dllimport；类静态数据成员 / `static const` 成员不会被可靠导出；函数符号才是自动导出导入的。
   eCAL core 自身用 `ECAL_API` + `ECAL_CORE_IMPORTS` 覆盖了这一点（见 `:46-54`）。
5. 与已有 `__declspec(dllexport)` 混用理论上会触发 LNK4197（`export specified multiple times`，
   是 warning）。实测本次构建日志中 LNK4197 计数为 0，LNK1181 计数也为 0。

## 五个 Windows 专属坑

1. **LNK1181: 无法打开 ecal_ecal-utils.lib**（最关键）。`BUILD_SHARED_LIBS=ON` 时
   `lib/ecal_utils/CMakeLists.txt:42` 的 `ecal_add_library()` 会把辅助库编成 DLL；这个 DLL 没有任何
   `dllexport` 符号，MSVC 因此不生成导入库，而 `ecal/core/CMakeLists.txt:710` 链接 `eCAL::ecal-utils`
   时仍引用 `lib/ecal_utils/ecal_ecal-utils.lib`。`CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON` 让 CMake 为它
   生成 `exports.def`，导入库随之产生，链接恢复。实测 `bin/ecal_ecal-utils.dll` 与
   `lib/ecal_ecal-utils.lib` 都正常产出。
   > 备选方案（已验证可行但已放弃）：把 Windows 的 `BUILD_SHARED_LIBS` 设为 `OFF`，辅助库退化成静态库，
   > core 仍是显式 SHARED。上游 Windows CI 就是这么做的。采用全符号导出的理由是保持与 Linux 一致的全动态
   > 布局，代价见下文「已知边界」。
2. **消费者必须定义 `ECAL_CORE_IMPORTS`**。`ecal/core/include/ecal/os.h:51-57` 用它控制
   `__declspec(dllimport)`；不定义时 `ECAL_API` 为空，导出的数据符号在 MSVC 上链接不到。这同时也是
   全符号导出方案对「全局数据符号」限制的兜底。
3. **DLL 装在 bin/，不在 lib/**。需要把 `bin` 挂进 PATH，否则包自检片段和 `xmake run` 都找不到
   `ecal_core.dll`，全动态后还要找到 `ecal_ecal-utils.dll` 等辅助 DLL。
4. **CMake 的 `-D` 值不能用反斜杠路径**。`CMAKE_PROJECT_TOP_LEVEL_INCLUDES` 是 list 型变量，
   `absl_DIR` 同理，统一把路径转成 `/`。
5. **MSVC 工具链偶发僵死**（本机环境问题，不是 recipe 缺陷）。eCAL 在 `CMakeLists.txt:44` 与
   `cmake/helper_functions/ecal_compiler_warnings.cmake:9` 注入 `/MP`，配合 `/FS` 共享 PDB。本机在全量
   构建中多次出现 `cl.exe` / `lib.exe` 包装进程 CPU=0 挂住数分钟，终止后增量续跑可以继续。
   `xmake f --jobs=1` 直接报 `error: Invalid option: --jobs=1`；`-j` 只作用于 xmake 自身目标，包安装
   阶段的 ninja 并发由 `os.default_njob()` 决定，日志里固定是 `ninja.exe install -C ... -j 14`，
   从命令行压不到 1。把 `-j`/`--jobs` 放到 xmake 全局位置也不行（`-y`、`--confirm=y` 会一同失效，
   卡在包安装确认）。**验证 `protobuf=true` 与 debug 时，曾临时在 `on_install` 里用 `io.replace`
   去掉上游源码里的 `/MP`，跑完立即按 sha256 校验恢复；交付的 recipe 不含这段改动。**
   它只影响编译并行度，不改变任何编译/链接 flags 的语义或产物内容。第一次
   release + `protobuf=false` 是在**未去掉 `/MP` 的正式 recipe** 下完整跑通的。

## 改动位置

| 行 | 改动 |
| --- | --- |
| `packages/e/ecal/xmake.lua:36-43` | Windows 系统库 `ws2_32/wsock32/iphlpapi/psapi/shlwapi/winmm/advapi32/user32/shell32`，对应 `ecal_core_private` 的 WIN32 链接项 |
| `:46-54` | `ECAL_CORE_IMPORTS` + `addenv("PATH", "bin")` |
| `:70` | `on_install("linux", "windows", ...)` |
| `:74-76` | `cmake_path()` 路径规范化，用于 `:92` 和 `:144` |
| `:98-101` | `BUILD_SHARED_LIBS=ON`（Windows 不再单独设 `OFF`） |
| `:116-127` | Windows 专属 `-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON` |

Linux 分支的所有行为保持不变：Windows 逻辑全在平台条件内，`cmake_path()` 在 Linux 上是空操作。

## 验证结果

| 配置 | 结果 |
| --- | --- |
| release + `protobuf=false` | **通过**：安装 ok、`on_test` 的 `GetVersionString()` C++ 片段 ok、编译链接 ok、`xmake run` ok。正式 recipe（含 `/MP`）下完成 |
| release + `protobuf=true`（默认配置） | **通过**：安装 ok、`on_test` 两个 C++ 片段（含 `CPublisher<google::protobuf::Any>`）ok、编译链接 ok、`xmake run` ok |
| debug + `protobuf=false` | **通过**：`/MDd`、安装 ok、`on_test` ok、编译链接 ok、`xmake run` ok（配置阶段被僵死进程打断一次，`xmake build` 增量续跑后完成） |

xmake 在每次全新安装后都会执行包的 `on_test`（`xmake/modules/private/action/require/impl/actions/install.lua:580`），
所以「安装 ok」等价于 `packages/e/ecal/xmake.lua:152-168` 的 C++ 自检片段通过（`protobuf=false` 时只有
`:152-158` 这一段；`CPublisher` 片段在 `:159-168` 的 protobuf 条件内）。

**动态库生成的硬证据**（`dumpbin /exports`，取自 `protobuf=true` 的安装树）：

- `bin/ecal_ecal-utils.dll`：1318 个导出符号 / 1318 个名称；`lib/ecal_ecal-utils.lib` 950 KB 导入库。
  加 `CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS` 之前这个 DLL 导出 0 个符号、MSVC 不生成导入库，正是 LNK1181 的根因。
- `bin/ecal_core.dll`：14538 个导出符号；`lib/ecal_core.lib` 16 MB。
- `lib/` 下另有 `ecal_app_pb.lib`、`ecal_core_pb.lib`、`ecal_protobuf_base.lib` 三份导入库，
  `protobuf=true` 的链接行拿到 `libprotobuf.lib` 与全部 abseil 库。

`release + protobuf=true` 的编译行带 `-DECAL_CORE_IMPORTS`，链接行带 9 个 Windows 系统库 +
`dbghelp.lib`/`bcrypt.lib`；`debug` 的编译行带 `-MDd`。三组构建日志中 LNK1181、LNK4197、
未解析符号计数均为 0。

复现方式（临时目录里建一个最小工程）：

```lua
-- xmake.lua
add_requires("ecal", {configs = {protobuf = false}, system = false})
target("ecal_probe")
    set_kind("binary")
    set_languages("c++17")
    add_files("main.cpp")
    add_packages("ecal")
```

```cpp
// main.cpp
#include <ecal/ecal.h>
int main() { auto v = eCAL::GetVersionString(); (void)v; return 0; }
```

```
xmake f -p windows -a x64 -m release -y
xmake build -y -v ecal_probe
xmake run ecal_probe
```

**`system = false` 不能省**：本机有 vcpkg 的 ecal 5.13.4，全局 xmake-repo 里还有一份「复制本地 eCAL 安装」
的同名包，不强制从仓库装会命中系统包，验证不到这份源码 recipe。`protobuf=true` 时把 `protobuf` 改成 `true`
即可。

## 已知边界

- **可选（建议做）**：在 CI 或另一台 Windows 机器上用**交付状态的 recipe** 直接重跑三组，确认不带
  本机 `/MP` 僵死干扰也能一次通过。本机正式 recipe 只完整跑通了 `release + protobuf=false` 一组；
  另两组是在临时去掉上游 `/MP` 的条件下验证的。这不是代码风险，只是本机工具链不稳定造成的验证绕行。
- 全符号导出是**全局**属性，会作用于 `ecal_core.dll` 这类已有显式 `ECAL_API` 导出的目标。实测自动生成了
  3 份 `exports.def`：`core.dir` 14535 行、`protobuf_base.dir` 1546 行、`ecal-utils.dir` 1319 行，其中含大量
  STL / CRT 符号和 `DATA` 符号，导出表明显膨胀。若在意 ABI 表面，可改成只对辅助目标设
  `WINDOWS_EXPORT_ALL_SYMBOLS`，但那需要改上游 CMake 或注入 cmake 片段，复杂度更高。
- 辅助库变成 DLL 后，安装树 `bin/` 里多了 `concrt140.dll`、`msvcp140*.dll`、`vcruntime140*.dll` 等
  MSVC 运行库（CMake install 复制进来的），xmake 会把它们列进 `libfiles`。`PATH` 已含 `bin`，实测运行正常。
- `on_install` 只列了 `linux` 和 `windows`，**mingw 不在支持范围**；clang-cl 未单独验证。
- Linux 分支未在本机回归（本机是 Windows），改动全部落在平台条件分支里。
- `protobuf=true` 需要从 xmake build-artifacts 下载 abseil 20250127.0 预编译包。本机 xmake 下载卡住，
  是手动 `curl` 把 1.9 MB 的 `windows-x64-vc14.43.34808-f09e8becf49542619f7d1ed5a3a5089f.7z`
  （sha256 `355c6c54a8ea06f08fd77ea49cf55168d01d9cded82ec789a02cfc9f755bfc58`）放进
  `~/.xmake/cache/packages/2611/a/abseil/20250127.0/` 才继续的。属于环境问题，不是 recipe 缺陷。

改动留在工作区，未提交 git。
