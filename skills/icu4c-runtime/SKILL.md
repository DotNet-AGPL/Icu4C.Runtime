---
name: icu4c-runtime
description: >-
  Use Icu4C.Runtime to ship app-local ICU4C with .NET apps (JIT and Native AOT) and to fix
  "Couldn't find a valid ICU package installed" or "Failed to load app-local ICU" in slim
  Linux images. Covers package choice, AppLocalIcu injection, InvariantGlobalization conflicts,
  $ORIGIN rpath, Windows-to-Linux cross-compilation and musl limits. 为 .NET 应用（JIT 与
  Native AOT）随包分发 ICU4C：选包、AppLocalIcu 注入、InvariantGlobalization 互斥、rpath
  与交叉编译注意事项。
license: Apache-2.0
metadata:
  authors: DotNet-AGPL
  package: Icu4C.Runtime
---

# Icu4C.Runtime — app-local ICU for .NET

Bundles ICU4C natives with a .NET app, so culture-aware APIs work on machines and containers
that do not have a system ICU installed. Works for JIT (framework-dependent) and Native AOT.

## When to use

Use this package when one of these is true:

- The app fails on Linux with
  `FailFast: Couldn't find a valid ICU package installed on the system`.
- The target image is slim (`debian:*-slim`, `alpine`, distroless) and has no `libicu`.
- You need the same ICU/CLDR data on every machine instead of whatever the distro ships.
- You publish Native AOT and use culture-sensitive APIs (`CultureInfo`, `DateTime` formatting,
  `string.Compare` with culture, `IdnMapping`, etc.).

Do **not** use it when `InvariantGlobalization=true` is intentional: invariant mode needs no ICU
and the natives would be dead weight.

## Choose the package

| Scenario | Package |
|---|---|
| One reference, works on every RID | `Icu4C.Runtime` (meta) |
| Known target RID, smaller restore | `Icu4C.Runtime.<rid>` (platform) |

Supported RIDs: `linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `win-x64`,
`win-arm64`, `osx-x64`, `osx-arm64`.

Do not reference the meta package **and** a platform package for the same RID.

## Minimal setup

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="79.1.1" />
</ItemGroup>
```

No code changes are required. The package targets:

- inject `System.Globalization.AppLocalIcu` = the packaged ICU version (`79.1`),
- set `System.Globalization.UseNls=false`,
- set `InvariantGlobalization=false` **only when you have not set it yourself**,
- for `PublishAot=true`, add an rpath (`$ORIGIN` on Linux, `@executable_path` on macOS).

The package ships ICU 79.1 (`libicu*.so.79.1`, `libicu*.79.1.dylib`, `icuuc79.dll`).

## Rules that matter

1. **Never set `InvariantGlobalization=true`** in a project that references this package. It emits
   `ICU4C003` and ICU is not enabled.
2. **Keep the natives next to the executable.** JIT resolves them through `deps.json`
   (`runtimes/<rid>/native/`); AOT copies them to the publish root. Do not move, rename or
   compress them.
3. **Alpine images set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true` by default.** Override it:
   `ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`.
4. **Portable publish (no `-r`) carries all 8 RIDs** under `runtimes/`. Publish with `-r <rid>` to
   keep only the target RID in the output.
5. A platform package only activates for its own RID. A RID without a matching package triggers
   `ICU4C001` and has no app-local ICU.

## Native AOT and cross-compilation

- The rpath is chosen by **target RID**, not host OS. A Windows host cross-compiling to
  `linux-x64` with `PublishAotCross.Tools` still gets `$ORIGIN`.
- On older package versions this was host-based; upgrade to a current package or add the rpath manually:
  `<LinkerArg Include="-Wl,-rpath,$ORIGIN" />` (do not wrap the value in single quotes; the
  whole-argument form `'-Wl,-rpath,$ORIGIN'` is also valid).
- Cross-compiling to **musl** with Zig produces a fully static binary (no dynamic section, no
  `INTERP`), so `dlopen` and app-local ICU cannot work. Build natively on Alpine instead.

## Verify

```bash
dotnet publish -c Release -r linux-x64
ls bin/Release/net*/linux-x64/publish | grep -i icu   # libicuuc/i18n/data.so.79.1
readelf -d bin/Release/net*/linux-x64/publish/<app> | grep -E 'RUNPATH|RPATH'
# expected: RUNPATH $ORIGIN   (no quotes)
bin/Release/net*/linux-x64/publish/<app> --help
```

On Windows, the publish folder must contain `icuuc79.dll`, `icuin79.dll`, `icudt79.dll` plus the
app-local `msvcp140*.dll` / `vcruntime140*.dll` staged by the package.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Failed to load app-local ICU: libicudata.so.79.1` | Natives next to the exe missing, or rpath missing. Check the publish root and `RUNPATH=$ORIGIN`. |
| `Couldn't find a valid ICU package installed` | `AppLocalIcu` was not injected: wrong RID, package not referenced for that RID, or an old restored version. |
| `Failed to load app-local ICU: icuuc79.dll` | Missing/wrong-architecture DLLs, or the MSVC runtime DLLs were removed from the output. |
| `ICU4C003` warning | Remove `<InvariantGlobalization>true</InvariantGlobalization>`. |
| `ICU4C001` warning | The target RID has no platform package; use the meta package or add the matching platform package. |
| App runs but cultures behave invariantly | `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true` is set in the environment/image. |

## 中文速查

- **适用**：Linux 精简镜像缺 `libicu`，启动报 `Couldn't find a valid ICU package`；或需要固定
  ICU/CLDR 版本、Native AOT 下使用文化相关 API。
- **选包**：全 RID 用 `Icu4C.Runtime`；已知目标 RID 用 `Icu4C.Runtime.<rid>`；两者不要同时引用。
- **三条铁律**：不要设 `InvariantGlobalization=true`（会告警 `ICU4C003` 且 ICU 失效）；
  原生库必须和 exe 同目录、不要改名；Alpine 镜像要显式
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`。
- **AOT/交叉**：rpath 按目标 RID 注入（Linux `$ORIGIN`、macOS `@executable_path`、Windows 不需要）；
  Windows→Linux 交叉编译可直接用；交叉到 musl 是静态产物，无法 `dlopen`，请在 Alpine 原生构建。
- **验证**：发布后确认发布根有 `libicu*`，`readelf -d` 的 `RUNPATH` 必须是 `$ORIGIN`（不带引号）。
- **报错对照**：`Failed to load app-local ICU` → 库没在 exe 旁或 rpath 缺失；
  `Couldn't find a valid ICU` → `AppLocalIcu` 未注入或包/RID 不匹配。

## References

- `README.md` — usage, sizes, platform notes.
- `docs/design.md` — targets design and packaging.
- `docs/native-dependency-portability.md` — glibc/musl/VC++/rpath deep dive.
- NuGet: <https://www.nuget.org/packages/Icu4C.Runtime>
