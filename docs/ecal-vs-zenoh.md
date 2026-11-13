# Eclipse eCAL vs Eclipse zenoh 对比（一手源码核实）

- 核实日期：**2026-11-04**。核实版本：eCAL **v6.1.1**（GitHub Releases 最新稳定版，2026-04-02）；zenoh Rust 核心 **1.10.2**、zenoh-c **1.10.2**（2026-10-28）；zenoh-cpp `main`（C++17，绑定 zenoh-c 1.10.2）。本仓库配方当前 pin 的是 zenoh-c 1.10.1。
- 证据方式：eCAL 与 zenoh/zenoh-c/zenoh-cpp 均为 **codeload tarball 本地克隆**（浅于 git clone，含全部源码），逐文件读取；少量补充来自官方文档站与 GitHub Releases API（WebFetch）。文中标注 `[本地克隆]` 的均可在上述 tag 源码中复核。

## 一句话结论

两者都是 Eclipse 基金会的 C++ 优先开源通信中间件、都能 brokerless 组网，但设计目标不同：**eCAL 是"机器人/汽车域的单机组 + LAN 数据总线"**——topic 级 pub/sub + RPC + 时间同步 + 录放工具链，零拷贝靠同机共享内存，跨机靠 UDP 组播/TCP；**zenoh 是"分布式数据流总线"**——key expression 层级命名空间，除 pub/sub 外还有 query/reply、分布式存储、liveliness，传输面（QUIC/TLS/串口/WebSocket）和跨 NAT 能力远超 eCAL，但核心是 Rust 实现，C/C++ 只是绑定。同机大点云 + Windows/Linux 双栈的 SLAM 管线，eCAL 更贴；多机、跨网段、需要存储/查询/边缘互联，zenoh 更贴。

## 对比速查表

| 维度 | eCAL v6.1.1 | zenoh 1.10.2 |
|---|---|---|
| 定位 | DDS-lite 机器人/汽车 IPC 中间件，pub/sub + RPC | "Zero Overhead Pub/Sub, Store/Query and Compute" 数据流 |
| 命名模型 | topic 扁平字符串，无层级语义、无通配订阅 | key expression `a/b/c`，`*`/`**`/`$` 通配、selector 参数 |
| Broker | 无（强制 brokerless） | 可选：peer 无 broker；router 模式做路由/插件宿主；client 必须连 router |
| 传输 | shm / UDP 组播 / TCP | TCP、UDP uc+mc、TLS、QUIC、WS、串口、vsock、unix、shmem(特性开关) |
| 零拷贝 | 同机 SHM 全零拷贝（5.12+ 双向） | 同机 shmem transport（需开 feature，zenoh-c 默认关） |
| RPC | service/client 内置 | queryable/get 内置（兼作"按需计算"入口） |
| 存储 | 无（离线 HDF5 录放） | PublicationCache、storage-manager 插件 + RocksDB/S3/InfluxDB 后端 |
| 时间同步 | 内置（time master/slave） | 无（消息带 Timestamp，不做时钟同步） |
| Liveliness/匹配状态 | monitoring 周期上报 | liveliness 原语 + matching status 监听 |
| 语言 | C++17、C、Python、C#（Rust 为社区绑定） | Rust、C、C++、Python、Java、Kotlin、TS、Go + zenoh-pico(纯C) |
| ROS | rmw_ecal（ROS 2 RMW） | rmw_zenoh / zenoh-plugin-ros2dds（官方主推） |
| 工具链 | Monitor/Player/Recorder GUI 一等公民 | CLI + dashboard(实验) + REST admin space |
| 许可证 | **Apache-2.0**（非 EPL） | **EPL-2.0 OR Apache-2.0 双许可** |
| 构建 | 纯 CMake/C++，依赖少 | 核心 Rust(cargo)，C API 经 cmake→cargo，需 Rust 工具链 |

## 逐条展开

### 1. 定位与数据模型

- eCAL 自称 "enhanced Communication Abstraction Layer… middleware that enables scalable, high performance interprocess communication"，提供 pub/sub 与 server/client 两种模式，"almost no configuration required"（`ecal-6.1.1/README.md`）。消息协议无关：核心只搬字节，类型元信息（encoding/type/description 字符串）随 registration 上报（`ecal/core/include/ecal/pubsub/publisher.h` 构造函数参数 `data_type_info_`）。topic 是扁平字符串，未发现通配/层级语义（核心头文件与 `doc/rst` 中无 wildcard 相关代码，判为**仅精确匹配**——推断，基于源码检索）。
- zenoh 口号 "Zero Overhead Pub/Sub, Store/Query and Compute. unifies data in motion, data at rest, and computations"（`zenoh-main/README.md`）。一切数据挂在 key expression 下：`/` 分层，`*` 匹配单层、`**` 匹配任意多层、`$` 转义（zenoh.io/docs/manual/abstractions/，WebFetch）；selector `key?param=v` 让查询带参数。除 Sample 流外还有 Query/Reply、liveliness token、storage、admin space（`zenoh/src/api/`：`query.rs` `queryable.rs` `liveliness.rs` `publisher.rs` `subscriber.rs` `scouting.rs` `matching.rs`）。
- **实质差异**：zenoh 的命名空间是"可计算的路由键"（订阅可重叠、查询可按前缀+参数过滤）；eCAL 的 topic 只是通道名，选择逻辑留在应用层。zenoh 的 value 模型内置 timestamp/encoding（`zenoh/src/api/sample.rs`、`encoding.rs`），eCAL 的等价物是 Send 的 `time_` 参数与类型信息字符串。

### 2. 架构

- eCAL **brokerless**（README "eCAL is brokerless"）：每个进程链接 `ecal_core`，无守护进程。注册/发现走 UDP 组播（`ecal/core/src/config/default_configuration.cpp`：registration local/network 均默认 udp，可选 shm 注册）。跨机通信要求 `network_enabled` 打开，默认仅本机（`doc/rst/advanced/transport_layers.rst`）。没有多跳路由概念——每台机器都是对等端。
- zenoh 三种 session mode：`router` / `peer` / `client`（`zenoh-main/DEFAULT_CONFIG.json5` 第 12 行注释 "The node's mode (router, peer or client)"，默认 `peer`）。peer 模式与 eCAL 等价（进程间直连，broker 非必需）；router 提供多跳路由、插件宿主（存储、REST、桥接）与 gossip 发现；client 只能连 router，用于防火墙/嵌入式后的终端（`DEFAULT_CONFIG.json5` scouting 段：client 模式 timeout 找 router）。zenohd 是独立 router 二进制（`zenoh-main/zenohd/`）。
- **NAT/跨网段**：eCAL 基本依赖组播可达（同 L2/L3 域 + ttl），跨 NAT 无原生手段（文档未见任何 NAT 章节，判为**不支持**——推断）；zenoh 的 QUIC/TCP/TLS/WS `connect` 端点 + client 模式就是为穿透设计的（`zenoh/src/api/session.rs` 示例含 `tcp/10.10.10.10:7447`）。

### 3. 传输与零拷贝

- eCAL v6 传输层枚举只有三个：`none / udp_mc / shm / tcp`（`ecal/core/include/ecal/config/transport_layer.h`；v5 时代的 UDP 单播数据层在 v6 公开配置中已不存在）。默认优先级：本机 `shm > udp_mc > tcp`，跨机 `udp_mc > tcp`（`ecal/core/include/ecal/config/publisher.h:147-148`）。README 宣传 1–20 GB/s（本机场景）。
- eCAL 零拷贝：SHM 层基于命名内存映射文件 + 进程间信号量同步（`ecal/core/src/io/shm/`：`ecal_memfile.cpp`、`ecal_memfile_pool.cpp`、`ecal_memfile_sync.cpp`，Linux/Win32 各有实现）。默认 API 有 2 次拷贝（transport_layers.rst 表格），5.12 起可用低层 `CPayloadWriter` 直接向 memfile 写入实现**发布端零拷贝**，订阅端读取时同样原位访问（`doc/rst/advanced/layers/shm_zerocopy.rst`："Full eCAL Zero Copy mechanism is working for local (inner-host) publish-subscribe connections only"）。缓冲区按发布者配置 pool（`reader/writer_shm_attributes.h` 的 `memfile_buffer_count`）。大点云跨机走 UDP 会 IP 分片、丢一片即整帧丢，官方文档明确建议 ≥1 MiB 载荷用 TCP（`doc/rst/advanced/layers/tcp.rst` 16 MiB 例、`message_drops.rst`）。拷贝路径全在 C++。
- zenoh 传输：feature 列表 `transport_tcp/udp/tls/quic/quic_datagram/ws/serial/unixpipe/unixsock-stream/vsock` + `shared-memory` + `transport_compression` + `transport_multilink` + `uring`（`zenoh-main/zenoh/Cargo.toml [features]`；注意 `serial`、`shared-memory` 不在 default，`transport_unixpipe` 也非默认）。UDP 层大消息靠分片重组：接收端 defrag buffer 默认 **1 GiB**，超限丢弃；rx buffer 默认 65535 B，文档注释建议 16 MiB 级消息调大（`DEFAULT_CONFIG.json5:690-700`）。
- zenoh 零拷贝：`shared-memory` transport（`commons/zenoh-shm/`，POSIX shm + `shm/windows.rs`），同样仅限**同主机**进程间；zenoh-c 编译期默认关闭（`zenoh-c-1.10.2/CMakeLists.txt:29` `ZENOHC_BUILD_WITH_SHARED_MEMORY FALSE`）。payload 拷贝路径在 Rust 核心（ZBytes 尽量零拷贝传递，`zenoh/src/api/bytes.rs`）。
- **结论性差异**：同机大点云两者都能零拷贝，eCAL 的 SHM 是默认路径且开箱即用；zenoh 的 shmem 需要重编 zenoh-c 开 feature，跨机大帧两者都怕 UDP 丢片，但 zenoh 还有 QUIC 这个第三条路（TCP 之上带 datagram 模式，`transport_quic_datagram`）。

### 4. 其他原语

- eCAL：service/client RPC（`ecal/core/include/ecal/service/{client,server}.h`，文档称其内部"more reliable"，走请求-响应关联，`doc/rst/getting_started/services.rst`）；**时间同步**（`ecal/core/include/ecal/time.h`：`IsSynchronized/GetTime/GetRealTime`，monitoring 上报 time_sync 状态 `types/monitoring.h`，实现 `ecal/core/src/time/ecal_timegate.cpp`——仿真/回放时统全局时钟，SLAM 场景价值大）；monitoring + logging 周期上报（`monitoring.h`、`log.h`）；HDF5 录制/回放（README，`thirdparty/hdf5`）；类型自省：topic 带 datatype+encoding+description，配 protobuf/flatbuffers/capnproto 序列化扩展包（`serialization/{protobuf,flatbuffers,capnproto}/`）。内部注册/监控线格式已从 v5 的 SBE 改为 protobuf-tag（`ecal/core/src/serialization/`、`ecal/core/pb/*.pbftags.h`）。
- zenoh：queryable/get（RPC+发现式查询合一）、**storage**（`zenoh-ext` 的 `PublicationCache`/`advanced_cache.rs`；router 插件 `zenoh-plugin-storage-manager`，外部后端 zenoh-backend-rocksdb/s3/influxdb，见 download.eclipse.org/zenoh 目录与 `zenoh-main/plugins/`）；**liveliness**（`zenoh/src/api/liveliness.rs`，可查历史 token 集合，比 eCAL 的 monitoring 轮询更事件化）；matching status（`api/matching.rs`，pub 得知是否有订阅者——QoS 语义）；zenoh-ext 的 AdvancedPublisher/Subscriber 提供大样本切片+确认传输（`zenoh-ext/src/advanced_publisher.rs`，README："advanced delivery guarantees"）；`zenoh-ext/group.rs` 提供组成员管理（实验性）。QoS：congestion_control(Drop/Block)、priority、reliability（`zenoh/src/api/sample.rs`、`DEFAULT_CONFIG.json5:1210`）。zenoh **无**时间同步（核心 API 无对应模块——源码检索，推断）。
- **一句话**：eCAL 的独门是时间同步 + 录放生态；zenoh 的独门是存储/查询 + liveliness + 传输层 QoS。

### 5. 发现与注册

- eCAL：UDP 组播注册，默认组基 `239.0.0.1`、端口 14002、ttl 3（本机模式走 `127.255.255.255` 回环组播）；数据面 udp_mc 按 topic 动态分配组（`config/transport_layer.h:46-67`、`default_configuration.cpp`）。topic 级组播是为了减少无关流量（transport_layers.rst："topic name based dynamic multicast grouping"）。跨子网只能靠调大 ttl/开 IGMP 路由，防火墙环境未见官方方案（文档检索，判为**薄弱点**——推断）。Windows 上有可选 Npcap 接收器缓解（`npcap_enabled`，同文件）。
- zenoh：scouting = 组播 `224.0.0.224:7446`（ttl 1，同网段）+ **gossip**（router 在实例间转发发现信息，可跨子网）+ 显式 `connect/listen` 端点（`DEFAULT_CONFIG.json5:146-195`）。router-mediated 场景下 client/peer 经 gossip 得知全网；无 router 的纯 peer 跨网段需手工配端点。多网卡 `interface: "auto"`。
- 相同点：同网段都是"零配置 + 组播自动发现"；差异在跨子网时 zenoh 有 router/gossip/TCP 三条路，eCAL 依赖网络基建。

### 6. 语言绑定与生态

- eCAL：C++（核心，C++17）、C、Python、C# 官方绑定（`ecal-6.1.1/lang/{c,csharp,python}`，nanobind）；Rust 绑定是 Eclipse 项目外的社区仓库（README "rustecal"）。GUI 工具链一等公民：Monitor/Player/Recorder/Launcher（`app/{mon,play,rec,apps}`，Qt+FTXUI）。ROS：`rmw_ecal`（ROS 2 RMW 层，README:127）；README 明确支持接 Protobuf/CapnProto/Flatbuffers 自选。领域：汽车（Continental/AUMOVIO 主导，版权头可证）、HIL/台架测试、工业数据总线；Matlab/Simulink 工具箱（README）。
- zenoh：Rust 原生 + C（zenoh-c，即本仓库配方）+ **zenoh-pico 纯 C 实现**（MCU 级）+ C++（zenoh-cpp header-only）+ Python/Kotlin/Java/TypeScript/Go（`zenoh-main/README.md` "Language Support" 列表）。ROS 2 story：官方 rmw_zenoh（`zenoh-plugin-ros2dds` 系）——注意 zenoh-c README/仓库内未直接出现 ROS 字样，此条来自 zenoh.io 与 ROS 2 文档（**次级来源**）。桥接生态：zenoh-bridge-ros2dds/ros1/mqtt/websocket-REST（`plugins/zenoh-plugin-rest` 在核心仓库，其余在独立仓库——后者未本地核实，标**推断**）。领域：物联网/边缘（Eclipse IoT 工作组），也进机器人（ROS 2）与自动驾驶数据链路。
- 治理：eCAL 属 Eclipse **Automotive** WG（projects.eclipse.org/projects/automotive.ecal），zenoh 属 Eclipse **IoT** WG（…/iot.zenoh）。对长期依赖的意义：两者都有基金会 IP 流程兜底；eCAL 主要厂商驱动（AUMOVIO/Continental），zenoh 多源（ADLINK 牵头 + 社区），绑定面与跨域活跃度更高。

### 7. 构建与依赖（打包视角）

- eCAL：CMake（`CMakeLists.txt`，cmake_minimum 3.15），核心硬依赖只有 **asio、ecaludp(自带构建)、protozero**，可选 `tcp_pubsub`、yaml-cpp、tclap（`ecal/core/CMakeLists.txt:42-59`）；GUI 才需要 Qt/FTXUI/HDF5。有 `conanfile.py`、`package.xml`（ROS 打包格式，但非 xmake 生态）。Windows 支持是官方的：MSVC 标志、`build_win/`、安装器、Win7+（`_WIN32_WINNT=0x0601`）。构建复杂度中等但仓库巨大（app+lang+serialization+samples），做 recipe 时建议只构 `ecal_core`+必要组件（`ECAL_CORE_*` 开关）。
- zenoh：核心是 Rust，**zenoh-c 的 CMake 只是 cargo 的外壳**（`zenoh-c-1.10.2/CMakeLists.txt:19` "Build zenohc library from rust sources"，经 cbindgen 生成头文件）——这就是 zenoh-c 配方必须带可用 Rust 工具链的根本原因；可用 `CARGO_COMMAND` 指定 cargo 版本、`ZENOHC_CUSTOM_TARGET` 交叉编译（README 给了 mingw 到 windows-gnu 的完整例子）。MSRV：zenoh 本体 1.75（`zenoh/Cargo.toml rust-version`，且有 `zenoh-pinned-deps-1-75` 应对），开发 toolchain 1.97.1；zenoh-c 提供 `ZENOHC_MSRV_1_75` 开关。zenoh-cpp 仅需 C++17 编译器，header-only，`ZENOHCXX_ZENOHC` 选择 zenoh-c 后端（`zenoh-cpp-main/CMakeLists.txt:15,31,67`）。zenohd 若需要（router 模式）另需编 Rust 二进制。
- **许可证核实结果（纠偏）**：eCAL = Apache-2.0（`LICENSE.txt` 首行）；zenoh 全系 = **EPL-2.0 OR Apache-2.0** 双许可（`zenoh-main/Cargo.toml:80`、LICENSE 目录含两份全文）。两者都能商用，但 zenoh 的 EPL 侧带弱传染（修改其源码需回馈；链接使用无碍），对"只当依赖用"的你实质差异不大。

### 8. 成熟度与版本

- eCAL：源自 Continental（版权头 2016–2025），v6.0.0（2025-08，Eclipse 项目页）大改 API（"Reworked API" + config 体系，迁移指南 `doc/rst/versions/6.0/migration_guide.rst`），v6.1.0（2026-02-24）、v6.1.1（2026-04-02）为当前最新稳定版（GitHub Releases API）。v5→v6 是一次大破坏性升级；文档称 5.x 与 6.x 进程间可兼容通信（`doc/rst/advanced/compatibility.rst`，未逐条验证）。
- zenoh：2024-10 进入 1.0；此后小版本节奏约 2–3 个月（1.7.1 2025-12、1.8.0 2026-03、1.9.0 2026-04、1.10.0 2026-08、1.10.2 2026-10-28；Eclipse 项目页 + GitHub Releases API）。1.x 内遵守 semver，但大量能力藏在 `unstable` feature 后（`zenoh/Cargo.toml [features] unstable`），C++ 绑定 README 自述 "still under active development"。zenoh-c 1.10.2 依赖 zenoh `release/1.10.2` 分支精确版本（`zenoh-c-1.10.2/Cargo.toml:81`），升级需核心/绑定同步换版——配方维护量在这。
- 已知痛点（issue 趋势 + 文档，标注来源性质）：eCAL 文档中大量篇幅在讲 UDP 丢片/网卡配置（`message_drops.rst`、Npcap）——跨机大载荷是其弱区；zenoh 的 shmem 默认关、跨语言绑定功能面不完全对齐 Rust 核心（如 zenoh-c 的 shm Locality API 在 1.7 changelog 才补齐——zenoh.io blog，次级来源）。

### 9. 适用场景与选型建议

见文末"选型建议"。

## 相同点（两者确实共享的）

1. Eclipse 基金会项目、均有正式 WG 治理（automotive.ecal / iot.zenoh），许可证都含 Apache-2.0 一侧。
2. 都以**进程间数据总线**为核心卖点，pub/sub 是主模式，且都宣称"无 broker 也能跑"（eCAL 是纯 P2P；zenoh 是 peer 模式默认）。
3. 零拷贝都只承诺**同主机**共享内存路径；跨机都退化为网络栈 + 大消息分片问题。
4. 发现都是组播驱动的近零配置（239.x vs 224.0.0.224），都提供 RPC（service/client vs queryable/get）。
5. C++ 都是一等公民接口（eCAL 原生实现；zenoh 经 zenoh-c/zenoh-cpp 绑定），都支持 Linux+Windows，都被 ROS 生态做过 RMW/桥接（rmw_ecal / rmw_zenoh）。
6. 都提供按 publisher 选择传输层的能力（eCAL `layer_priority` 向量；zenoh 按端点/locator 配置）。

## 选型建议（针对：单机大点云 + 偶发双机，Linux/Windows，无 ROS 依赖）

- **纯本机多进程传 64 线点云/体素流**：eCAL 更省事——SHM 零拷贝是默认路径、`CPayloadWriter` 低层 API 直接原位写、Windows 原生支持久经生产；你全栈 C++/xmake，不需要为构建引入 cargo。时间同步原语对多传感器管线也是白赚的。
- **两机之间传**：两者都建议 TCP 层（eCAL 文档明说 ≥1 MiB 用 TCP；zenoh 用 tcp/quic 端点）。跨 NAT、不可靠无线链路、需要 TLS/认证时，zenoh 明显更强（QUIC+TLS+auth 在默认 feature 里，`zenoh/Cargo.toml default`）。
- **需要"按需取最近值"（如外参/地图版本）、离线存储、异构设备（浏览器/Pico）接入**：选 zenoh，eCAL 没有对应物。
- **工程现实约束**：你已经把 zenoh-c/zenoh-cpp 配方跑通（1.10.1），增建 eCAL 配方的成本其实更低（纯 CMake、核心只依赖 asio/ecaludp/protozero，`xmake repo` 私有配方模式一致）。若目标只是"给 SLAM 管线换一个比 ROS 轻的总线"，eCAL 与场景更对口；若路线图里有云端/多站点/ROS2 混部，zenoh 是更能长出去的那棵树。
- 两者不必二选一：zenoh 桥（如 zenoh-bridge-ros2dds 同思路）可以接 eCAL 域与 zenoh 域的边界，但这类桥接目前无一方官方提供 eCAL↔zenoh，需自研（推断，基于两仓库均无相关插件）。

## 证据清单

本地克隆（codeload tarball，均可复核）：
- `eclipse-ecal/ecal` **v6.1.1**：`README.md`（定位/性能/brokerless/ROS2 rmw/OS 支持）；`ecal/core/include/ecal/config/transport_layer.h:35-67`（传输枚举+组播 239.0.0.1:14002/ttl/buffer）；`config/publisher.h:147-148`（本机/跨机层优先级）；`ecal/core/src/io/shm/`（memfile 池+同步原语）；`doc/rst/advanced/{transport_layers.rst,layers/tcp.rst,layers/shm_zerocopy.rst,message_drops.rst}`（零拷贝范围、TCP 动机、UDP 丢片）；`ecal/core/include/ecal/{time.h,service/,pubsub/publisher.h,types/monitoring.h}`（RPC/时间同步/类型信息）；`ecal/core/CMakeLists.txt:42-59`（asio/ecaludp/protozero/tcp_pubsub 依赖）；`LICENSE.txt`（Apache-2.0）；`serialization/{protobuf,flatbuffers,capnproto}`、`lang/{c,csharp,python}`、`app/{mon,play,rec}`。
- `eclipse-zenoh/zenoh` **main（≈1.10.2）**：`README.md`（定位/仓库结构/Language Support）；`zenoh/Cargo.toml [features]`（全部传输开关、MSRV 1.75）；`DEFAULT_CONFIG.json5`（mode、scouting 224.0.0.224:7446/gossip、fragmentation 1GiB、reliability）；`zenoh/src/api/`（query/queryable/liveliness/matching/scouting 源码）；`zenoh-ext/src/{advanced_publisher.rs,publication_cache.rs,group.rs}`；`commons/zenoh-shm/`（含 windows.rs）；`LICENSE`（EPL-2.0 + Apache-2.0 双许可文本）。
- `eclipse-zenoh/zenoh-c` **1.10.2**：`CMakeLists.txt:19,29,45-55`（cmake 壳调 cargo、shm 默认关、CARGO_COMMAND）；`Cargo.toml:81-84`（pin zenoh release/1.10.2）；`README.md:157-187`（交叉编译含 windows-gnu）。
- `eclipse-zenoh/zenoh-cpp` **main**：`CMakeLists.txt:15,31,60-67`（C++17、ZENOHCXX_ZENOHC、header-only 目标）；`README.md`（"under active development"）。

网络获取（WebFetch）：
- GitHub Releases API：`eclipse-ecal/ecal`（v6.1.1 2026-04-02 最新）、`eclipse-zenoh/zenoh` 与 `zenoh-c`（1.10.2 2026-10-28 最新，1.10.0=2026-08-14）。
- <https://zenoh.io/docs/manual/abstractions/>（keyexpr 通配/selector/storage 语义）。
- <https://projects.eclipse.org/projects/automotive.ecal/releases/v6.0.0>（eCAL 6.0 API 大改与语言绑定条目，搜索摘要）。

次级/未本地核实（已在文中标注）：rmw_zenoh、zenoh-bridge-* 系列、zenoh-backend-* 独立仓库（目录见 download.eclipse.org/zenoh 镜像索引）、rustecal。文档站对应页：https://eclipse-ecal.github.io/ecal/ （transport_layers / layers/tcp / layers/shm_zerocopy / message_drops 与克隆内 rst 一一对应）。
