# Icu4C.Runtime 设计说明

> 为 .NET 10 提供 AppLocal ICU4C 运行时二进制，支持 JIT 与 Native AOT，不依赖宿主机 ICU。

---

## 1. 目标

- 提供开箱即用的 NuGet 包：用户仅需一行 `PackageReference` 即可获得完整 ICU 功能。
- 自动完成：ICU 二进制分发、`AppLocalIcu` 配置注入、AOT rpath 注入、版本匹配。
- 覆盖 Linux(glibc/musl)、Windows、macOS 的 x64/arm64。
- 数据自嵌入（`--with-data-packaging=dll`），无需独立 `.dat`。

---

## 2. 包结构（方案 C：通用 + 每 RID slim）

| 包 | 内容 | 典型 restore 体积 |
|---|---|---|
| `Icu4C.Runtime`（通用） | 全部 8 个 RID | ≈120 MB |
| `Icu4C.Runtime.linux-x64` / `.linux-arm64` / `.linux-musl-x64` / `.linux-musl-arm64` | 每包 1 个 RID | ≈15 MB |
| `Icu4C.Runtime.win-x64` / `.win-arm64` | 每包 1 个 RID | ≈15 MB |
| `Icu4C.Runtime.osx-x64` / `.osx-arm64` | 每包 1 个 RID | ≈15 MB |

- 通用与 slim **互不依赖**，由用户二选一引用（同时引用无收益）。
- NuGet 不支持"按 RID 选择依赖包"，因此**不使用**"元包依赖全部子包"的模式。

支持的 RID：`linux-x64`、`linux-arm64`、`linux-musl-x64`、`linux-musl-arm64`、`win-x64`、`win-arm64`、`osx-x64`、`osx-arm64`。

---

## 3. 核心设计决策

| 决策 | 说明 |
|---|---|
| 数据打包 | `--with-data-packaging=dll`，数据嵌入 `libicudata.so` / `libicudata.*.dylib` / `icudtNN.dll` |
| JIT | `runtimes/{rid}/native/` 经 NuGet 原生资产（deps.json）解析 |
| AOT | 原生库复制到发布根目录 + 注入 rpath（Linux `$ORIGIN`，macOS `@executable_path`） |
| AppLocalIcu 注入 | 在**求值期**注入 `RuntimeHostConfigurationOption`，JIT 与 AOT 均生效 |
| targets 复用 | 通用包与 slim 包共用核心逻辑，各自仅提供一层 id 同名 shim |
| 版本来源 | 包版本单一来源 `Directory.Build.props`；ICU 版本独立于包版本 |
| 多包发布 | 一次 CI 产出 9 个包；发布为手工控制 |

---

## 4. 仓库结构

```
Icu4C.Runtime/
├── .github/workflows/build.yml
├── Directory.Build.props                     # IcuPackageVersion（包版本单一来源）
├── buildTransitive/
│   ├── Icu4C.Runtime.targets                 # 通用 shim → Import 核心
│   └── _IcuRuntimeCore.targets               # 共享核心（逻辑唯一来源）
├── buildTransitive-slim/
│   └── Icu4C.Runtime.<rid>.targets           # 8 个 slim shim（设 _IcuPackageRid）
├── scripts/
│   ├── build-icu-linux.sh                    # glibc 原生/交叉、musl 源码编译
│   ├── extract-icu-linux.sh                  # 从 Ubuntu 容器快速提取（仅验证用）
│   ├── build-icu-windows.ps1                 # MSVC 构建（ARM64 先建 x64 宿主工具）
│   ├── build-icu-macos.sh                    # macOS 构建 + install_name_tool
│   └── verify-local.sh                       # 容器内 JIT/AOT 验证
├── src/
│   ├── Icu4C.Runtime/Icu4C.Runtime.csproj         # 通用包
│   └── Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj  # slim 包（-p:IcuRid=...）
├── tests/
│   ├── IcuJitTest/                           # JIT 测试
│   ├── IcuAotTest/                           # Native AOT 测试
│   └── Icu4C.Runtime.Tests/                  # xunit 单测
├── runtimes/<rid>/native/                    # 原生库（由脚本/CI 生成，不入库）
├── README.md · README-SLIM.md
├── LICENSE (AGPL-3.0-only) · LICENSE-ICU (Unicode-3.0)
└── nuget.config
```

---

## 5. targets 设计

### 5.1 共享核心 `buildTransitive/_IcuRuntimeCore.targets`

- 默认属性：`_IcuSupportedRids`（8 个）、`_IcuVersion`（=77.1）、`_IcuNativeDir`
  （由 `$(RuntimeIdentifier)` 经 `[MSBuild]::NormalizeDirectory` 计算）。
- 求值期注入：`RuntimeHostConfigurationOption System.Globalization.AppLocalIcu = $(_IcuVersion)`、
  `System.Globalization.UseNls=false`；`InvariantGlobalization` 仅在未设置时置 false。
- `GetIcuVersion`（RoslynCodeTaskFactory 内联任务）：扫描原生文件名，仅用于一致性告警；参数非必需、
  调用带条件（无 RID 时跳过，避免 `MSB4044`）。
- AOT：`PublishAot=true` 且 RID 非空时，将 `$(_IcuNativeDir)*` 复制到发布根目录；并注入
  `-Wl,-rpath,'$ORIGIN'`（Linux）/ `-Wl,-rpath,'@executable_path'`（macOS）。

### 5.2 shim

- 通用：`buildTransitive/Icu4C.Runtime.targets` 仅 `Import` 核心。
- slim：`buildTransitive-slim/Icu4C.Runtime.<rid>.targets` 设 `_IcuPackageRid`/`_IcuSupportedRids` 后
  `Import` 核心（打包进包的 `buildTransitive/`，与核心同目录）。

### 5.3 告警

| 代码 | 含义 |
|---|---|
| `ICU4C001` | 目标 RID 不在本包覆盖范围 |
| `ICU4C002` | 未找到 `runtimes/<rid>/native` 原生库 |
| `ICU4C003` | `InvariantGlobalization=true` 与本包冲突 |
| `ICU4C004` | 原生库主版本与声明 ICU 版本不一致 |
| `ICU4C005` | 使用了 RID 不匹配的 slim 包 |

---

## 6. 打包

- 通用：`src/Icu4C.Runtime/Icu4C.Runtime.csproj`，含 `buildTransitive/**` + `runtimes/**` + 许可/自述。
- slim：`src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj`，参数化：

```bash
dotnet pack src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj -c Release -o nupkg -p:IcuRid=linux-x64
```

- 包版本来自 `Directory.Build.props` 的 `<IcuPackageVersion>`（包与测试项目共用）。

### 产物命名（与 AppLocalIcu 约定一致）

| 平台 | 文件名 |
|---|---|
| Linux | `libicuuc.so.<ver>`、`libicui18n.so.<ver>`、`libicudata.so.<ver>` |
| Windows | `icuucNN.dll`、`icuinNN.dll`、`icudtNN.dll`（NN=主版本） |
| macOS | `libicuuc.<ver>.dylib`、`libicui18n.<ver>.dylib`、`libicudata.<ver>.dylib` |

---

## 7. 原生库构建脚本

- `build-icu-linux.sh <icu-version> <rid>`：glibc 原生化或两段式交叉（先建 x64 宿主工具，再
  `--with-cross-build`）；musl 在 Alpine 原生编译。支持 `ICU_CACHE_DIR`（复用源码）、
  `ICU_GH_PROXY`（GitHub 代理）。
- `build-icu-windows.ps1 <icu-version> <rid>`：VS/MSBuild 构建 `allinone.sln`；非 x64 先构建 x64
  宿主工具；产物从 `<workdir>/icu/bin64|binARM64` 拷贝 `icuuc/icuin/icudt`。
- `build-icu-macos.sh <icu-version> <rid>`：`runConfigureICU MacOSX`，并用 `install_name_tool` 将依赖
  改写为 `@loader_path/...`。
- `extract-icu-linux.sh`：仅用于快速验证（从发行版包提取）。

---

## 8. CI（GitHub Actions）

`.github/workflows/build.yml`：

- **触发**：推 `v*` tag / PR（改动 `scripts/**`、`buildTransitive*`、`src/**`、workflow 时）/ 手动
  `workflow_dispatch`。
- **并发**：`concurrency` 同 ref 自动取消旧运行。
- **缓存**：`actions/cache` 缓存 ICU 源码（配合 `ICU_CACHE_DIR`）。
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

- **pack**：汇总各 RID artifact → 打通用包与 8 个 slim 包（共 9 个）→ 上传 `nupkg` artifact。
- **发布**：仅当手动 `workflow_dispatch` 且勾选 `publish` 时执行 `dotnet nuget push`（需 secret
  `NUGET_API_KEY`）；tag 与普通运行只构建打包，不发布。

---

## 9. 版本方案

- 包版本：`{icu-major}.{icu-minor}.{base}[.{revision}]`，如 `77.1.0`、`77.1.0.1`、`77.1.0.2`。
- 定义于 `Directory.Build.props` 的 `<IcuPackageVersion>`，包与测试项目共用。
- NuGet 支持 4 段版本；**第 4 段不要用 0**（`77.1.0.0` 归一化为 `77.1.0`）。
- ICU 版本（`_IcuVersion`，用于 `AppLocalIcu` 与库文件名）与包版本相互独立。

---

## 10. 本地验证

- JIT：`dotnet publish -r <rid>` 后在 `mcr.microsoft.com/dotnet/runtime:10.0` 运行。
- AOT：在 Linux SDK 容器内 `dotnet publish -r <rid>`，后在 `runtime-deps:10.0` 运行。
- 关键判据：应用输出正确；AOT 的 `readelf -d` 含 `$ORIGIN`。
- 注意：ICU 系运行时 `dlopen` 加载，`ldd | grep icu` 不会显示。
- 可"移走系统 ICU"以证明 app-local 生效。
- 单测：`dotnet test tests/Icu4C.Runtime.Tests`。

---

## 11. 关键注意事项

- `AppLocalIcu` 的值必须与库文件名中的版本一致；核心 targets 从原生文件名推导用于校验。
- AOT 必须在求值期注入 `RuntimeHostConfigurationOption`（ILC 在写 rsp 时读取）。
- .NET 10 已移除默认 rpath，AOT 必须显式注入。
- 无 RID 的便携构建：`_IcuNativeDir` 为空，校验任务须跳过。
- 包体积：通用包 ≈120MB，slim 包 ≈15MB。
- 许可：项目 AGPL-3.0-only；ICU 二进制为 Unicode-3.0，再分发须保留声明。

---

## 12. 参考资源

- [ICU 官方源码](https://github.com/unicode-org/icu)
- [.NET AppLocal ICU 文档](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/globalization)
- [NuGet 版本格式](https://learn.microsoft.com/en-us/nuget/concepts/package-versioning)
