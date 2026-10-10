# Icu4C.Runtime 项目启动文档

> **用途**：本文档是 `Icu4C.Runtime` 项目的完整启动蓝图。在新会话中，只需将本文档提供给 AI，即可基于此继续推进项目。  
> **目标**：构建一个开箱即用的 NuGet 包，为 .NET 10 应用提供 AppLocal ICU4C 运行时，同时支持 JIT 和 Native AOT，不依赖宿主机 ICU。

---

## 1. 项目背景与目标

### 1.1 问题
- .NET 运行时默认依赖系统安装的 ICU 库。
- 在多种宿主机环境（尤其是精简容器）中，ICU 可能缺失，导致 `FailFast: Couldn't find a valid ICU package`。
- 官方 `Microsoft.ICU.ICU4C.Runtime` NuGet 包已停止维护，无法满足 .NET 10 和 Native AOT 需求。

### 1.2 目标
- 提供 `Icu4C.Runtime` NuGet 包，用户仅需一行 `PackageReference`，即可在 JIT 和 AOT 场景下获得完整 ICU 功能。
- 包自动处理：ICU 二进制分发、`AppLocalIcu` 配置、rpath 注入、数据文件定位、版本匹配。
- 支持多平台 RID：Linux (glibc/musl)、Windows、macOS。
- 优先采用数据自嵌入（`--with-data-packaging=dll`），避免独立 `.dat` 文件。
- 为 AOT 场景提供可选的 musl 静态链接变体，实现极致环境无关。

---

## 2. 核心设计决策

| 决策 | 说明 |
|---|---|
| **包名** | `Icu4C.Runtime` |
| **默认数据打包** | `--with-data-packaging=dll`，数据嵌入 `libicudata.so` / `icudt.dll` |
| **JIT 场景** | 动态库 + `runtimes/{rid}/native/` + `AppLocalIcu` 运行时配置 |
| **AOT 场景** | 动态库复制到发布根目录 + 注入 rpath（Linux `$ORIGIN`，macOS `@executable_path`） |
| **AOT + musl 可选** | 后续提供 musl 静态链接子包，消除 glibc 依赖 |
| **版本推导** | targets 从二进制文件名动态提取 ICU 版本，避免硬编码 |
| **RID 覆盖** | 至少：`linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `win-x64`, `win-arm64`, `osx-x64`, `osx-arm64` |
| **开箱即用** | 所有配置通过 `buildTransitive` targets 自动注入，用户无需修改项目文件 |

---

## 3. 仓库结构

```
Icu4C.Runtime/
├── .github/workflows/build.yml
├── buildTransitive/
│   └── Icu4C.Runtime.targets
├── build/
│   └── Icu4C.Runtime.targets          # 与 buildTransitive 内容一致
├── scripts/
│   ├── build-icu-linux.sh             # 源码编译 Linux
│   ├── extract-icu-linux.sh           # 容器提取（快速验证）
│   ├── build-icu-windows.ps1          # Windows 构建（待补充）
│   ├── build-icu-macos.sh             # macOS 构建（待补充）
│   └── verify-local.sh                # nerdctl 本地验证
├── src/Icu4C.Runtime/
│   └── Icu4C.Runtime.csproj
├── tests/
│   ├── IcuJitTest/
│   │   ├── IcuJitTest.csproj
│   │   └── Program.cs
│   └── IcuAotTest/
│       ├── IcuAotTest.csproj
│       └── Program.cs
├── runtimes/                          # 由脚本生成，存放各 RID 原生库
├── README.md
├── LICENSE
└── .gitignore
```

---

## 4. 详细文件内容

### 4.1 `src/Icu4C.Runtime/Icu4C.Runtime.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <PackageId>Icu4C.Runtime</PackageId>
    <Version>77.1.0</Version>
    <Authors>DotNet-AGPL</Authors>
    <Description>AppLocal ICU4C runtime binaries for .NET. Supports JIT and Native AOT without host ICU dependency.</Description>
    <PackageLicenseExpression>Unicode-3.0</PackageLicenseExpression>
    <PackageProjectUrl>https://github.com/DotNet-AGPL/Icu4C.Runtime</PackageProjectUrl>
    <RepositoryUrl>https://github.com/DotNet-AGPL/Icu4C.Runtime</RepositoryUrl>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>
    <NoWarn>NU5128</NoWarn>
  </PropertyGroup>

  <ItemGroup>
    <None Include="..\..\build\**" Pack="true" PackagePath="build\" />
    <None Include="..\..\buildTransitive\**" Pack="true" PackagePath="buildTransitive\" />
    <None Include="..\..\runtimes\**" Pack="true" PackagePath="runtimes\" />
    <None Include="..\..\LICENSE" Pack="true" PackagePath="\" />
  </ItemGroup>

</Project>
```

### 4.2 `buildTransitive/Icu4C.Runtime.targets`（核心）

```xml
<Project>

  <PropertyGroup>
    <InvariantGlobalization>false</InvariantGlobalization>
    <_IcuSupportedRids>linux-x64;linux-arm64;linux-musl-x64;linux-musl-arm64;win-x64;win-arm64;osx-x64;osx-arm64</_IcuSupportedRids>
  </PropertyGroup>

  <!-- 从原生二进制文件名动态推导 ICU 版本 -->
  <UsingTask TaskName="GetIcuVersion" TaskFactory="RoslynCodeTaskFactory"
             AssemblyFile="$(MSBuildToolsPath)\Microsoft.Build.Tasks.Core.dll">
    <ParameterGroup>
      <NativeDir ParameterType="System.String" Required="true" />
      <IcuVersion ParameterType="System.String" Output="true" />
    </ParameterGroup>
    <Task>
      <Using Namespace="System.IO" />
      <Using Namespace="System.Text.RegularExpressions" />
      <Code Type="Fragment" Language="cs"><![CDATA[
        IcuVersion = "";
        if (Directory.Exists(NativeDir)) {
          foreach (var f in Directory.GetFiles(NativeDir, "libicuuc.so.*")) {
            var m = Regex.Match(Path.GetFileName(f), @"libicuuc\.so\.(\d+\.\d+)");
            if (m.Success) { IcuVersion = m.Groups[1].Value; break; }
          }
          if (string.IsNullOrEmpty(IcuVersion)) {
            foreach (var f in Directory.GetFiles(NativeDir, "icuuc*.dll")) {
              var m = Regex.Match(Path.GetFileName(f), @"icuuc(\d+)\.dll");
              if (m.Success) { IcuVersion = m.Groups[1].Value; break; }
            }
          }
        }
      ]]></Code>
    </Task>
  </UsingTask>

  <!-- 检测目标 RID 是否被覆盖 -->
  <Target Name="_IcuValidateRid" BeforeTargets="PrepareForBuild">
    <PropertyGroup>
      <_IcuNativeDir>$(MSBuildThisFileDirectory)..\runtimes\$(RuntimeIdentifier)\native\</_IcuNativeDir>
    </PropertyGroup>
    <Warning Condition="'$(RuntimeIdentifier)' != '' And !$(_IcuSupportedRids.Contains('$(RuntimeIdentifier)'))"
             Text="ICU4C001: Icu4C.Runtime does not provide native binaries for RID '$(RuntimeIdentifier)'. Supported RIDs: $(_IcuSupportedRids)." />
  </Target>

  <!-- 推导版本号 -->
  <Target Name="_IcuResolveVersion" BeforeTargets="PrepareForBuild">
    <GetIcuVersion NativeDir="$(_IcuNativeDir)">
      <Output TaskParameter="IcuVersion" PropertyName="_IcuResolvedVersion" />
    </GetIcuVersion>
  </Target>

  <!-- JIT / 框架依赖：走标准 NuGet 原生资产机制 -->
  <ItemGroup Condition="'$(PublishAot)' != 'true'">
    <RuntimeHostConfigurationOption Include="System.Globalization.AppLocalIcu"
        Value="$(_IcuResolvedVersion)" />
    <RuntimeHostConfigurationOption Include="System.Globalization.UseNls"
        Value="false" />
  </ItemGroup>

  <!-- Native AOT：复制到发布根目录 + 注入 rpath -->
  <ItemGroup Condition="'$(PublishAot)' == 'true'">
    <None Include="$(MSBuildThisFileDirectory)..\runtimes\$(RuntimeIdentifier)\native\*"
          CopyToOutputDirectory="PreserveNewest"
          Link="%(Filename)%(Extension)" />
    <LinkerArg Include="-Wl,-rpath,'$$ORIGIN'"
               Condition="$([MSBuild]::IsOSPlatform('Linux'))" />
    <LinkerArg Include="-Wl,-rpath,'@executable_path'"
               Condition="$([MSBuild]::IsOSPlatform('OSX'))" />
  </ItemGroup>

</Project>
```

### 4.3 `scripts/extract-icu-linux.sh`（快速验证）

```bash
#!/usr/bin/env bash
set -euo pipefail

RID="${1:-linux-x64}"
UBUNTU_VERSION="${2:-24.04}"
ICU_PKG="${3:-libicu74}"

OUT_DIR="$(pwd)/runtimes/${RID}/native"
mkdir -p "${OUT_DIR}"

echo "Extracting ICU from ubuntu:${UBUNTU_VERSION} (${ICU_PKG}) -> ${OUT_DIR}"

nerdctl run --rm \
  -v "${OUT_DIR}:/out" \
  "ubuntu:${UBUNTU_VERSION}" bash -c "
    apt-get update -qq && apt-get install -y -qq ${ICU_PKG} && \
    cp -a /usr/lib/x86_64-linux-gnu/libicu*.so* /out/ && \
    chmod 644 /out/libicu*.so*
  "

# 清理符号链接，仅保留实际文件
find "${OUT_DIR}" -type l -delete
ls -lh "${OUT_DIR}"
```

### 4.4 `scripts/build-icu-linux.sh`（源码编译）

```bash
#!/usr/bin/env bash
set -euo pipefail

ICU_VERSION="${1:-77.1}"
RID="${2:-linux-x64}"
OUT_DIR="$(pwd)/runtimes/${RID}/native"

ICU_TAG="release-$(echo ${ICU_VERSION} | tr '.' '-')"
WORK_DIR="$(mktemp -d)"
trap "rm -rf ${WORK_DIR}" EXIT

echo "Building ICU ${ICU_VERSION} for ${RID}"

cd "${WORK_DIR}"
curl -sSL -o icu.tgz \
  "https://github.com/unicode-org/icu/releases/download/${ICU_TAG}/icu4c-$(echo ${ICU_VERSION} | tr '.' '_')-src.tgz"
tar xzf icu.tgz
cd icu/source

./runConfigureICU Linux --with-data-packaging=dll
make -j"$(nproc)"

mkdir -p "${OUT_DIR}"
cp lib/libicuuc.so.${ICU_VERSION%.*}* "${OUT_DIR}/"
cp lib/libicui18n.so.${ICU_VERSION%.*}* "${OUT_DIR}/"
cp lib/libicudata.so.${ICU_VERSION%.*}* "${OUT_DIR}/"
find "${OUT_DIR}" -type l -delete

echo "Built:"
ls -lh "${OUT_DIR}"
```

### 4.5 `scripts/verify-local.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

RID="${1:-linux-x64}"

echo "=== JIT verification ==="
cd tests/IcuJitTest
dotnet publish -r "${RID}" -c Release
nerdctl run --rm \
  -v "$(pwd)/bin/Release/net10.0/${RID}/publish:/app" \
  -w /app \
  mcr.microsoft.com/dotnet/runtime:10.0 \
  ./IcuJitTest

echo ""
echo "=== AOT verification ==="
cd ../IcuAotTest
dotnet publish -r "${RID}" -c Release

echo "--- rpath check ---"
readelf -d "bin/Release/net10.0/${RID}/publish/IcuAotTest" | grep -E 'RPATH|RUNPATH' || true

echo "--- ICU source check ---"
nerdctl run --rm \
  -v "$(pwd)/bin/Release/net10.0/${RID}/publish:/app" \
  -w /app \
  mcr.microsoft.com/dotnet/runtime-deps:10.0 \
  bash -c "ldd ./IcuAotTest | grep icu || true"

nerdctl run --rm \
  -v "$(pwd)/bin/Release/net10.0/${RID}/publish:/app" \
  -w /app \
  mcr.microsoft.com/dotnet/runtime-deps:10.0 \
  ./IcuAotTest
```

### 4.6 测试项目

**`tests/IcuJitTest/IcuJitTest.csproj`**：
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <InvariantGlobalization>false</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Icu4C.Runtime" Version="77.1.0" />
  </ItemGroup>
</Project>
```

**`tests/IcuAotTest/IcuAotTest.csproj`**：
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>false</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Icu4C.Runtime" Version="77.1.0" />
  </ItemGroup>
</Project>
```

**`Program.cs`（两个项目共用）**：
```csharp
using System.Globalization;

Console.WriteLine($"ICU available: {GlobalizationMode.Invariant == false}");
Console.WriteLine($"Current culture: {CultureInfo.CurrentCulture.Name}");

var zh = new CultureInfo("zh-CN");
Console.WriteLine($"zh-CN DisplayName: {zh.DisplayName}");
Console.WriteLine($"zh-CN Date: {DateTime.Now.ToString("D", zh)}");

var cmp = string.Compare("张三", "李四", StringComparison.CurrentCulture);
Console.WriteLine($"Sort 张三 vs 李四: {cmp}");

var tz = TimeZoneInfo.Local;
Console.WriteLine($"TimeZone: {tz.Id} / {tz.DisplayName}");
```

### 4.7 `.github/workflows/build.yml`

```yaml
name: Build

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build-native:
    strategy:
      fail-fast: false
      matrix:
        include:
          - rid: linux-x64
            os: ubuntu-24.04
            configure: Linux
          - rid: linux-arm64
            os: ubuntu-24.04
            configure: Linux
            cross: aarch64-linux-gnu
          - rid: linux-musl-x64
            os: ubuntu-24.04
            container: alpine:3.20
          - rid: win-x64
            os: windows-2022
          - rid: osx-x64
            os: macos-13
          - rid: osx-arm64
            os: macos-14

    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Build ICU (Linux)
        if: startsWith(matrix.rid, 'linux-') && !matrix.container
        run: ./scripts/build-icu-linux.sh 77.1 ${{ matrix.rid }}

      - name: Build ICU (Linux musl)
        if: matrix.container
        run: |
          docker run --rm -v ${{ github.workspace }}:/work -w /work \
            ${{ matrix.container }} sh -c "
              apk add --no-cache build-base curl python3 &&
              ./scripts/build-icu-linux.sh 77.1 ${{ matrix.rid }}
            "

      - name: Build ICU (Windows)
        if: startsWith(matrix.rid, 'win-')
        shell: pwsh
        run: ./scripts/build-icu-windows.ps1 77.1 ${{ matrix.rid }}

      - name: Build ICU (macOS)
        if: startsWith(matrix.rid, 'osx-')
        run: ./scripts/build-icu-macos.sh 77.1 ${{ matrix.rid }}

      - uses: actions/upload-artifact@v4
        with:
          name: native-${{ matrix.rid }}
          path: runtimes/${{ matrix.rid }}/native/

  pack:
    needs: build-native
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - uses: actions/download-artifact@v4
        with:
          path: runtimes
          pattern: native-*

      - name: Restructure artifacts
        run: |
          for dir in runtimes/native-*; do
            rid="${dir#runtimes/native-}"
            mkdir -p "runtimes/${rid}/native"
            mv "${dir}"/* "runtimes/${rid}/native/"
            rmdir "${dir}"
          done
          find runtimes -type f | sort

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'

      - name: Pack
        run: dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg

      - name: Push
        if: startsWith(github.ref, 'refs/tags/')
        run: dotnet nuget push nupkg/*.nupkg --api-key ${{ secrets.NUGET_API_KEY }} --source https://api.nuget.org/v3/index.json
```

---

## 5. 本地验证流程

### 5.1 环境要求
- WSL2 + nerdctl + containerd
- .NET 10 SDK
- 项目放在 WSL 原生文件系统（如 `~/projects/`），避免 `/mnt/c` 权限问题

### 5.2 快速启动

```bash
# 1. 初始化仓库
git init Icu4C.Runtime && cd Icu4C.Runtime
mkdir -p build buildTransitive scripts src/Icu4C.Runtime tests/IcuJitTest tests/IcuAotTest .github/workflows

# 2. 复制本文档中的文件到对应位置

# 3. 赋予脚本执行权限
chmod +x scripts/*.sh

# 4. 快速提取 linux-x64 的 ICU（Ubuntu 24.04 → ICU 74.2）
./scripts/extract-icu-linux.sh linux-x64 24.04 libicu74

# 5. 打包 NuGet
dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg

# 6. 本地验证（JIT + AOT）
./scripts/verify-local.sh linux-x64
```

### 5.3 验证要点
- JIT：在 `mcr.microsoft.com/dotnet/runtime:10.0` 容器中运行，应输出中文和正确排序。
- AOT：在 `mcr.microsoft.com/dotnet/runtime-deps:10.0` 容器中运行，`ldd` 应显示 ICU 来自 `/app`。
- rpath：`readelf -d` 应包含 `$ORIGIN`。

---

## 6. 后续工作

1. **补齐 Windows/macOS 构建脚本**：
   - `scripts/build-icu-windows.ps1`
   - `scripts/build-icu-macos.sh`
2. **扩展 CI 矩阵**：覆盖所有声明的 RID，并处理交叉编译（如 Linux ARM64）。
3. **musl 静态链接变体（可选）**：
   - 在 Alpine 中编译 ICU 静态库，数据自嵌入。
   - 通过条件 MSBuild 目标，在 `PublishAot=true` 且 RID 为 `linux-musl-*` 时激活静态链接。
   - 需要处理 `libstdc++` 静态链接和链接器参数。
4. **完善 README**：面向消费端，说明只需一行 `PackageReference`，列出支持的 RID 和 ICU 版本。
5. **版本自动化**：CI 中自动从 ICU 官方获取最新稳定版，更新包版本。
6. **测试覆盖**：增加单元测试，验证 `CultureInfo`、排序、时区等行为。

---

## 7. 关键注意事项

- **版本匹配**：`AppLocalIcu` 的值必须与 ICU 库文件名中的版本严格一致，targets 已实现动态推导。
- **数据自嵌入**：使用 `--with-data-packaging=dll`，无需处理独立 `.dat` 文件。
- **AOT rpath**：.NET 10 已移除默认 rpath，必须显式注入 `LinkerArg`。
- **RID 警告**：未覆盖的 RID 会发出 `ICU4C001` 警告，避免静默失败。
- **许可证**：ICU 使用 Unicode-3.0，再分发需保留版权声明。
- **体积**：完整 ICU 数据约 27 MiB，包体积较大，但这是完整全球化的必要代价。

---

## 8. 参考资源

- [ICU 官方源码](https://github.com/unicode-org/icu)
- [.NET AppLocal ICU 文档](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/globalization)
- [归档项目 kkamegawa/ICU4C_Nuget](https://github.com/kkamegawa/ICU4C_Nuget)（思路参考）
- [CodeBrix.Platform.Unicode.ApacheLicenseForever](https://www.nuget.org/packages/CodeBrix.Platform.Unicode.ApacheLicenseForever)（Windows 参考）

---

**文档版本**：1.0  
**最后更新**：2026-10-10  
**适用 .NET 版本**：.NET 10  
**ICU 版本基准**：77.1（可替换）