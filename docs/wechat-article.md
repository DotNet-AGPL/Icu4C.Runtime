# Icu4C.Runtime：给 .NET 应用带上完整 ICU（JIT + Native AOT）

> 关键词：AppLocal ICU、Native AOT、Alpine/精简容器、跨平台、ARM64

## 一、先说痛点

如果你把 .NET 应用部署到**精简容器**（比如 `alpine`、`chiseled`、裁剪过的 `runtime-deps`）里，很可能见过这个崩溃：

```
Process terminated. Couldn't find a valid ICU package installed on the system.
Set the configuration flag System.Globalization.Invariant to true if you want to run
with no globalization support.
```

原因很简单：.NET 的全球化（CultureInfo、排序、日期格式、时区、IDN…）默认依赖**宿主机安装的 ICU 库**（`libicuuc` / `libicui18n` / `libicudata`）。容器里没装，就崩。

传统做法有三种，各有各的坑：

1. 在镜像里 `apt install libicu` —— 镜像变大、还得跟基础镜像的发行版版本对齐；
2. 设 `InvariantGlobalization=true` —— **放弃全球化**，中文显示、排序、日期全都退化成"原样输出"，很多库直接报错；
3. 自己编译、拷贝 ICU 二进制并手工配置 —— 能跑，但平台多、版本多，很难维护。

而现在，还能再加上一个新挑战：**Native AOT**。AOT 会把程序编译成原生可执行文件，ICU 的加载方式和 JIT 不一样（默认 rpath 被移除），手工配更是麻烦。

有没有一个"**一行引用、开箱即用、JIT 和 AOT 都支持**"的方案？

有。这就是本文介绍的 NuGet 包：**Icu4C.Runtime**。

---

## 二、Icu4C.Runtime 是什么

一句话：**把 ICU4C 运行时二进制按平台打包进 NuGet，并在编译期自动帮你配置 `AppLocalIcu` 和 AOT 的 rpath。**

也就是说：

- 你不需要在镜像里装 ICU；
- 你不需要改项目文件；
- 应用会加载**随包分发的、固定版本**的 ICU，行为在不同环境下**完全一致**。

它覆盖 8 个 RID：

```
linux-x64, linux-arm64, linux-musl-x64, linux-musl-arm64,
win-x64,  win-arm64,  osx-x64,        osx-arm64
```

glibc / musl、x64 / arm64、三大操作系统全覆盖。

而且在“要不要额外装运行库”这件事上，它尽量替你兜底：

- **Windows**：随包带上 MSVC 运行库（`msvcp140` / `vcruntime140*`），**无需安装 VC++ Redistributable**；
- **Linux（glibc）**：在**老基线（AlmaLinux 8 / glibc 2.28）**上构建，并静态链接 C++ 运行库，覆盖 Debian 11-12、Ubuntu 20.04+、RHEL/Alma/Rocky 8-9 等；
- **Linux（musl）**：不依赖 `libstdc++` / `libgcc`，只依赖 libc（AOT 产物在裸 Alpine 上也能直接跑）。

---

## 三、最快用法：一行搞定

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="77.1.4" />
</ItemGroup>
```

就这一行。它是个 **meta 包**：本身不含二进制，而是**依赖 8 个按平台拆分的包**，把对应平台的 ICU 带进来。

包会自动做三件事：

1. 把 `System.Globalization.AppLocalIcu` 注入到运行时配置（JIT 与 AOT 都生效）；
2. 设置 `InvariantGlobalization=false`（除非你自己显式设置过）；
3. 当 `PublishAot=true` 时，给链接器加上 rpath（Linux `$ORIGIN`、macOS `@executable_path`）。

### JIT / 框架依赖部署

原生库走标准的 NuGet native assets 机制（`runtimes/<rid>/native/` + `deps.json`），运行时自动找到。

### Native AOT

原生库会被复制到发布根目录，配合注入的 rpath 与内嵌的 `AppLocalIcu` 配置，加载器即可找到。

---

## 四、想省流量？用"平台包"

meta 包虽然方便，但因为 **NuGet 无法按 RID 过滤依赖**，引用它会把 8 个平台包**全部还原**（约 120MB 下载）。

如果你的目标平台是明确的，直接引用**单个平台包**，只下约 15MB：

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" />
</ItemGroup>
```

多平台时代码里条件引用即可：

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
  <PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
</ItemGroup>
```

> 小提示：平台包用的是 `build/` 目标（仅**直接引用**生效），而 meta 用 `buildTransitive/`。所以即使平台包被 meta "顺带"依赖进来，也不会重复注入或产生告警。

### 下载量 vs 产物大小

| 环节 | 结果 |
|---|---|
| 还原（引用 meta） | 下载全部 8 个平台包（≈120MB） |
| `-r <rid>` / Native AOT 发布 | 产物**只含目标 RID** 的 ICU（≈40MB） |
| 便携发布（不带 `-r`） | 产物含**全部 8 个 RID**（放在 `runtimes/<rid>/native/`） |

一句话：**关心下载量就引用单平台包；关心应用体积，AOT/单 RID 发布只会带目标平台。**

---

## 五、它是怎么工作的（给好奇的你）

- `Icu4C.Runtime`（meta）只带一份 `buildTransitive`，负责注入 `AppLocalIcu` 和 rpath；它的 nuspec 里声明了 8 个平台依赖，并设置 `exclude="Build,Analyzers"`，保证平台包的 `build/` **不会**随依赖传递生效。
- 每个平台包带 `runtimes/<rid>/native/` 的真实库，以及一个 `build/Icu4C.Runtime.<rid>.targets`：**仅当构建的 RID 与包一致时**才注入配置（复制原生库 + rpath），否则静默跳过。
- 版本上有两个概念：
  - **包版本**：`77.1.N`（前两段是 ICU 版本，第三段是打包修订，从 1 开始）；
  - **ICU 库版本**：`77.1`（对应文件名 `libicu*.so.77.1`、`libicu*.77.1.dylib`、`icuuc77.dll`）。
  两者独立——包修 bug 升级到 `77.1.4`，库文件名不变。

---

## 六、常见问题

**Q：我需要改项目文件吗？**
不用。加 `PackageReference` 即可，其余由包的目标自动完成。

**Q：会覆盖我设置的 `InvariantGlobalization` 吗？**
不会。只有在你没设置时才置为 `false`。

**Q：Windows 上也要用吗？**
Windows 10+ 系统自带 ICU，通常不需要；但如果要**锁定 ICU 版本、跨环境行为一致**，同样可以引用。包会随附 MSVC 运行库，**不需要单独安装 VC++ Redistributable**。

**Q：能用在 Alpine / musl 上吗？**
可以，专门提供了 `linux-musl-x64`、`linux-musl-arm64`。唯一要注意：官方 **.NET Alpine 镜像默认 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true`**，需要在容器里覆盖为 `false`（`ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`）才会启用 ICU。

**Q：需要在系统里额外装什么运行库吗？**
基本不用：Windows 包自带 MSVC 运行库；Linux 包自带（或静态链接）C++ 运行库。glibc 版要求 **glibc ≥ 2.28**（覆盖 Debian 11+、Ubuntu 20.04+、RHEL/Alma/Rocky 8-9 等）。

**Q：对 .NET 版本有要求吗？**
AppLocal ICU 机制自 .NET 5 起提供；本包以当前 .NET 为构建基准，升级 .NET 一般无需改动用法。

**Q：ICU 的许可证？**
ICU 二进制是 Unicode License v3，再分发保留版权声明即可（包里已附 `LICENSE-ICU`）。

---

## 七、结语

**Icu4C.Runtime** 的目标只有一个：让"**全球化**"这件事在 .NET 上不再是个部署难题。

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
