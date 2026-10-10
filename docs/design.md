# Icu4C.Runtime 设计说明

> 为 .NET 10 提供 AppLocal ICU4C 运行时二进制，支持 JIT 与 Native AOT，不依赖宿主机 ICU。

---

## 1. 目标

- 提供开箱即用的 NuGet 包：用户仅需一行 `PackageReference` 即可获得完整 ICU 功能。
- 自动完成：ICU 二进制分发、`AppLocalIcu` 配置注入、AOT rpath 注入、版本匹配。
- 覆盖 Linux(glibc/musl)、Windows、macOS 的 x64/arm64。
- 数据自嵌入（`--with-data-packaging=dll`），无需独立 `.dat`。

---

## 2. 包结构（B：meta + 每 RID 平台包）

| 包 | 内容 | 说明 |
|---|---|---|
| `Icu4C.Runtime`（meta） | 无二进制；依赖 8 个平台包 + `buildTransitive/` targets | 极小（~19KB） |
| `Icu4C.Runtime.<rid>`（平台包） | 单个 RID 的 native + `build/` targets | ≈15MB（Windows 包含 VC 运行库后略大） |

- 二进制**只存于平台包一份**（meta 不含二进制）。
- NuGet 不能按 RID 过滤依赖 → 引用 meta 会**还原全部 8 个平台包**（≈119MB）；但**指定 RID 的发布产物只含目标 RID**，便携发布含全部 RID。
- 支持 RID：`linux-x64`、`linux-arm64`、`linux-musl-x64`、`linux-musl-arm64`、`win-x64`、`win-arm64`、`osx-x64`、`osx-arm64`。

---

## 3. 核心设计决策

| 决策 | 说明 |
|---|---|
| 数据打包 | `--with-data-packaging=dll`，数据嵌入 `libicudata.so` / `libicudata.*.dylib` / `icudtNN.dll` |
| JIT | `runtimes/<rid>/native/` 经 NuGet 原生资产（deps.json）解析 |
| AOT | 原生库由 SDK 复制到发布根目录 + targets 注入 rpath（Linux `$ORIGIN`，macOS `@executable_path`） |
| AppLocalIcu 注入 | 在**求值期**注入 `RuntimeHostConfigurationOption`，JIT 与 AOT 均生效 |
| meta 与平台包 | meta 用 `buildTransitive/`（作用于消费方）；平台包用 `build/`（**仅直接引用生效**，避免被 meta 传递导入造成重复/告警） |
| 版本来源 | 包版本单一来源 `Directory.Build.props`；ICU 版本独立于包版本 |
| 多包发布 | 一次 CI 产出 9 个包；发布为手工控制 |
| Windows CRT | ICU 保持 /MD；随平台包内置 **app-local VC++ 运行库**（消费方无需安装 VC++ 再发行组件） |

---

## 4. 仓库结构

```
Icu4C.Runtime/
├── .github/workflows/build.yml
├── Directory.Build.props                     # IcuPackageVersion（包版本单一来源）
├── buildTransitive/
│   └── Icu4C.Runtime.targets                 # meta：buildTransitive，注入 AppLocalIcu + AOT rpath
├── build-slim/
│   └── Icu4C.Runtime.<rid>.targets           # 8 个平台包 shim（打包进包内 build/，RID 守卫）
├── scripts/
│   ├── build-icu-linux.sh                    # glibc 原生/交叉、musl 源码编译
│   ├── extract-icu-linux.sh                  # 从 Ubuntu 容器快速提取（仅验证用）
│   ├── build-icu-windows.ps1                 # MSVC 构建（ARM64 先建宿主工具）+ 随包 VC 运行库
│   ├── build-icu-macos.sh                    # macOS 构建 + install_name_tool
│   ├── verify-local.sh                       # 容器内 JIT/AOT 验证（Linux）
│   └── verify-windows.ps1                    # Windows JIT(RID/便携) + 运行库闭包验证
├── src/
│   ├── Icu4C.Runtime/Icu4C.Runtime.csproj         # meta 包（依赖 8 个平台包）
│   └── Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj  # 平台包（-p:IcuRid=...）
├── tests/
│   ├── IcuJitTest/ · IcuAotTest/ · Icu4C.Runtime.Tests/
├── runtimes/<rid>/native/                    # 原生库（由脚本/CI 生成，不入库）
├── README.md · README-SLIM.md
├── LICENSE (AGPL-3.0-only) · LICENSE-ICU (Unicode-3.0)
├── THIRD-PARTY-NOTICES.md                     # MS VC++ 运行库声明（Windows 包）
└── nuget.config
```

---

## 5. targets 设计

### 5.1 meta：`buildTransitive/Icu4C.Runtime.targets`
- 求值期注入 `RuntimeHostConfigurationOption System.Globalization.AppLocalIcu = 77.1`、`UseNls=false`；`InvariantGlobalization` 仅在未设置时置 false。
- AOT：注入 rpath（原生库由 SDK 从平台包自动复制到发布根）。
- 告警：`ICU4C001`（RID 未覆盖）、`ICU4C003`（InvariantGlobalization=true）。

### 5.2 平台包：`build/Icu4C.Runtime.<rid>.targets`
- `build/` 资产**仅对直接引用生效**，不被 meta 传递导入 → 不会因 8 个平台包同时存在而重复注入/告警。
- 仅当 `$(RuntimeIdentifier) == <rid>` 时注入 `AppLocalIcu`；AOT 时把本包 native 复制到发布根 + rpath。
- 其它 RID 时**静默**（no-op）。

### 5.3 告警

| 代码 | 含义 |
|---|---|
| `ICU4C001` | 目标 RID 无对应平台包（由 meta 发出） |
| `ICU4C003` | `InvariantGlobalization=true` 与本包冲突 |

---

## 6. 打包

- 平台包：`src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj`，参数化：
  ```bash
  dotnet pack src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj -c Release -o nupkg -p:IcuRid=linux-x64
  ```
- meta：`src/Icu4C.Runtime/Icu4C.Runtime.csproj`，`PackageReference` 到 8 个平台包（生成 nuspec 依赖，`exclude="Build,Analyzers"`），并用 `buildTransitive/**`。打包前需让平台包在本地 feed 中可用：
  ```bash
  dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg   # 从仓库本地源 nupkg 还原平台包
  ```
- 包版本来自 `Directory.Build.props` 的 `<IcuPackageVersion>`。

### 产物命名（与 AppLocalIcu 约定一致）

| 平台 | 文件名 |
|---|---|
| Linux | `libicuuc.so.<ver>`、`libicui18n.so.<ver>`、`libicudata.so.<ver>` |
| Windows | `icuucNN.dll`、`icuinNN.dll`、`icudtNN.dll`（NN=主版本）+ 内置 `msvcp140*.dll`、`vcruntime140*.dll` |
| macOS | `libicuuc.<ver>.dylib`、`libicui18n.<ver>.dylib`、`libicudata.<ver>.dylib` |

---

## 7. 原生库构建脚本

- `build-icu-linux.sh <icu-version> <rid>`：glibc 原生化或两段式交叉（先建 x64 宿主工具，再 `--with-cross-build`）；musl 在 Alpine 原生编译。支持 `ICU_CACHE_DIR`、`ICU_GH_PROXY`。
- `build-icu-windows.ps1 <icu-version> <rid>`：VS/MSBuild 构建 `allinone.sln`；非 x64 先构建 x64 宿主工具；产物从 `<workdir>/icu/bin64|binARM64` 拷贝。随后把 **VC++ 2015-2022 运行库**（`msvcp140*.dll`、`vcruntime140*.dll`）从 VS Redist 目录一并放入 `runtimes/<rid>/native/`，并校验 ICU DLL 导入的运行库均已就位（否则构建失败）。
- `build-icu-macos.sh <icu-version> <rid>`：`runConfigureICU MacOSX` + `install_name_tool` 改写为 `@loader_path/...`。
- `extract-icu-linux.sh`：仅用于快速验证。

---

## 8. CI（GitHub Actions）

- **触发**：`v*` tag / PR（改动 `scripts/**`、`buildTransitive/**`、`build-slim/**`、`src/**`、`Directory.Build.props`、workflow）/ 手动 `workflow_dispatch`。
- **并发**：`concurrency` 同 ref 自动取消旧运行。**缓存**：ICU 源码。
- **矩阵**：

| RID | Runner | 方式 |
|---|---|---|
| linux-x64 | ubuntu-24.04 | 源码编译 |
| linux-arm64 | ubuntu-24.04-arm | 原生编译 |
| linux-musl-x64 | ubuntu-24.04 | alpine 容器 |
| linux-musl-arm64 | ubuntu-24.04-arm | alpine 容器 |
| win-x64 / win-arm64 | windows-2022 | MSVC（ARM64 两段式） |
| osx-x64 | macos-15-intel | 原生 |
| osx-arm64 | macos-14 | 原生 |

- 每个 RID 作业构建 native → 打**平台包** → 上传 `pkg-<rid>`。
- `pack` 作业：下载 `pkg-*` 到本地 feed → 还原并打 **meta** → 上传 `nupkg-core`。
- **发布**：仅手动 `workflow_dispatch` 且勾选 `publish` 时 `dotnet nuget push`（需 secret `NUGET_API_KEY`）。

---

## 9. 版本方案

- 包版本：`{icu-major}.{icu-minor}.{revision}`，如 `77.1.1`、`77.1.2`（前两段对应 ICU 版本，第三段为打包修订，从 1 开始）。
- 定义于 `Directory.Build.props` 的 `<IcuPackageVersion>`，包与测试项目共用。
- ICU 共享库自身版本为 `77.1`（`libicu*.so.77.1` 等），**包版本不改变库文件名**。
- ICU 版本（`_IcuVersion`，用于 `AppLocalIcu`）与包版本相互独立。

---

## 10. 本地验证

- Linux：`dotnet publish -r <rid>` 后在 `mcr.microsoft.com/dotnet/runtime:10.0` 运行；AOT 在 SDK 容器内发布，后在 `runtime-deps:10.0` 运行。
- Windows：`scripts/verify-windows.ps1` —— RID 发布与便携发布均运行 JIT 测试，并校验发布产物里 ICU DLL 依赖的 VC 运行库是否齐备（本机有 MSVC + Windows SDK 时另跑 AOT）。
- 关键判据：应用输出正确；AOT 的 `readelf -d` 含 `$ORIGIN`。
- 注意：ICU 系运行时 `dlopen` 加载，`ldd | grep icu` 不会显示；可"移走系统 ICU"证明 app-local 生效。
- 单测：`dotnet test tests/Icu4C.Runtime.Tests`。

---

## 11. 关键注意事项

- `AppLocalIcu` 的值必须与库文件名中的版本一致。
- AOT 必须在求值期注入 `RuntimeHostConfigurationOption`（ILC 在写 rsp 时读取）。
- .NET 10 已移除默认 rpath，AOT 必须显式注入。
- 平台包用 `build/`（非 `buildTransitive/`），否则被 meta 传递导入会重复注入/告警。
- restore 会下载全部平台包（NuGet 不按 RID 过滤依赖）；发布产物按 RID 过滤。
- Windows 上 ICU DLL 采用 `/MD`（DLL 版 CRT），依赖 `msvcp140.dll`/`vcruntime140*.dll`；这些运行库随包内置（app-local），消费方**无需**安装 VC++ 可再发行组件。
- AppLocalIcu 在 Windows 只用「应用目录 + System32」解析：自包含/RID 发布把 DLL 平铺到根目录；便携发布由运行时经原生搜索目录解析 `runtimes/<rid>/native/`（已验证可用）。
- 许可：项目 AGPL-3.0-only；ICU 二进制为 Unicode-3.0，再分发须保留声明；Windows 包内置的 MS VC++ 运行库遵循微软许可（见 `THIRD-PARTY-NOTICES.md`）。

---

## 12. 参考资源

- [ICU 官方源码](https://github.com/unicode-org/icu)
- [.NET AppLocal ICU 文档](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/globalization)
- [NuGet 版本格式](https://learn.microsoft.com/en-us/nuget/concepts/package-versioning)
