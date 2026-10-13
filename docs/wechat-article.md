# Icu4C.Runtime：给 .NET 应用带上完整 ICU（JIT + Native AOT）

> 关键词：AppLocal ICU、Native AOT、Alpine/精简容器、跨平台、ARM64

## 一、你大概率见过这个崩溃

把 .NET 应用部署到**精简容器**（`alpine`、`chiseled`、裁剪过的 `runtime-deps`）时，很多人的第一课是这个：

```
Process terminated. Couldn't find a valid ICU package installed on the system.
```

原因不复杂：.NET 的全球化——`CultureInfo`、排序、日期/数字格式、时区、IDN——默认依赖**宿主机安装的 ICU**（`libicuuc` / `libicui18n` / `libicudata`）。容器里没装，启动即崩。

常见应对各有一摊事：`apt install libicu` 让镜像变大、还要跟基础镜像的发行版对齐；`InvariantGlobalization=true` 直接**放弃全球化**（中文显示、排序都退化成“原样输出”）；自己编译 ICU 再手工配置，平台多、版本多，难维护。再叠上 **Native AOT**（默认 rpath 被移除、加载方式与 JIT 不同），手工配置更劝退。

有没有一种“**一行引用、开箱即用、JIT 和 AOT 都支持**”的做法？有——就是本文介绍的 NuGet 包 **Icu4C.Runtime**。

## 二、Icu4C.Runtime 是什么

一句话：**把 ICU4C 运行时二进制按平台打包进 NuGet，并在编译期自动帮你配好 `AppLocalIcu` 与 AOT 的 rpath。**

也就是说：

- 你不需要在镜像里装 ICU；
- 你不需要改项目文件；
- 应用会加载**随包分发的、固定版本**的 ICU，行为跨环境一致。

它覆盖 **8 个 RID**：

```
linux-x64, linux-arm64, linux-musl-x64, linux-musl-arm64,
win-x64,  win-arm64,  osx-x64,        osx-arm64
```

glibc / musl、x64 / arm64、三大操作系统，全覆盖。

## 三、最快用法：一行搞定

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="77.1.4" />
</ItemGroup>
```

就这一行。`Icu4C.Runtime` 是个 **meta 包**：本身不含二进制，而是依赖 8 个**平台包**，把对应平台的 ICU 带进来。加上它之后，包会自动：

1. 注入 `System.Globalization.AppLocalIcu`（JIT 与 AOT 都生效）；
2. 设置 `InvariantGlobalization=false`（除非你自己显式设置过）；
3. 当 `PublishAot=true` 时，给链接器加上 rpath（Linux `$ORIGIN`、macOS `@executable_path`）。

## 四、8 个平台全覆盖，而且“不挑宿主”

除了覆盖广，它在“**要不要额外装运行库**”这件最容易翻车的事上也做了处理：

- **Windows**：ICU 的 DLL 依赖 MSVC 运行库——包**随附** `msvcp140` / `vcruntime140*`，**无需安装 VC++ Redistributable**；
- **Linux（glibc）**：在**老基线（AlmaLinux 8 / glibc 2.28）**上构建，并静态链接 C++ 运行库，覆盖 Debian 11–12、Ubuntu 20.04+、RHEL/Alma/Rocky 8–9 等；
- **Linux（musl）**：不依赖 `libstdc++` / `libgcc`，只依赖 libc——AOT 产物在裸 Alpine 上也能直接跑。

**JIT 与 Native AOT 都做过验证**：既跑通了官方运行时镜像，也在**原生发行版**（裸 `debian:12`、裸 `alpine:3.20`）上实测通过。

## 五、想省下载？用“平台包”

meta 包虽然方便，但因为 **NuGet 无法按 RID 过滤依赖**，引用它会把 8 个平台包**全部还原**（约 120MB）。目标平台明确时，直接引用**单个平台包**，只下约 15MB：

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" />
</ItemGroup>
```

多平台就条件引用：

```xml
<PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
<PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
```

| 环节 | 结果 |
|---|---|
| 引用 meta | 下载全部 8 个平台包（≈120MB） |
| `-r <rid>` / Native AOT 发布 | 产物**只含目标 RID** 的 ICU（≈40MB） |
| 便携发布（不带 `-r`） | 产物含**全部 8 个 RID** |

一句话：**关心下载量就引用单平台包；关心应用体积，AOT / 单 RID 发布只会带目标平台。**

## 六、常见问题

**Q：我需要改项目文件吗？**
不用。加 `PackageReference` 即可，其余由包的目标自动完成。

**Q：会覆盖我设置的 `InvariantGlobalization` 吗？**
不会。只有在你没设置时才置为 `false`。

**Q：Windows 上也要用吗？**
Windows 10+ 系统自带 ICU，通常不需要；但如果要**锁定 ICU 版本、跨环境行为一致**，同样可以引用。包会随附 MSVC 运行库，**不需要单独安装 VC++ Redistributable**。

**Q：Alpine 上为什么没生效？**
官方 **.NET Alpine 镜像默认 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true`**，需要在容器里覆盖为 `false`（`ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`）才会启用 ICU。

**Q：需要在系统里额外装什么运行库吗？**
基本不用：Windows 包自带 MSVC 运行库；Linux 包自带（或静态链接）C++ 运行库。glibc 版要求 **glibc ≥ 2.28**。

**Q：许可证？**
项目采用 **Apache-2.0**；随包分发的 ICU 为 **Unicode License v3**（包里已附 `LICENSE-ICU`）。

## 七、结语

**Icu4C.Runtime** 的目标只有一个：让“**全球化**”这件事在 .NET 上不再是个部署难题。

- 一行 `PackageReference`，JIT + Native AOT 全支持；
- 8 个平台 / 架构 RID，glibc、musl、Windows、macOS 全覆盖；
- 固定 ICU 版本，跨环境行为可预期；
- 想省下载就用单平台包。

**快速开始**

```bash
dotnet add package Icu4C.Runtime --version 77.1.4
```

- NuGet：https://www.nuget.org/packages/Icu4C.Runtime
- 单平台：`Icu4C.Runtime.linux-x64`、`Icu4C.Runtime.win-x64`、`Icu4C.Runtime.osx-arm64` …（同名规则）
- 源码：https://github.com/DotNet-AGPL/Icu4C.Runtime

> 许可证：项目 Apache-2.0；随包分发的 ICU 为 Unicode License v3。
