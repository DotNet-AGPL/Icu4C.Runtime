# Icu4C.Runtime

AppLocal ICU4C runtime binaries for .NET 10 — full globalization (ICU) support in **JIT and Native
AOT**, without relying on a host-installed ICU.

`Icu4C.Runtime` is a **meta package**: it has no binaries of its own and depends on the per-RID
platform packages (`Icu4C.Runtime.<rid>`), which carry the natives. Reference the meta for a
one-line, works-everywhere setup, or reference a single platform package to keep restore small.

## Why

- The .NET runtime normally depends on a system-installed ICU. In slim containers it may be missing
  and apps crash with `FailFast: Couldn't find a valid ICU package`.
- `Microsoft.ICU.ICU4C.Runtime` is unmaintained and doesn't cover .NET 10 / Native AOT.
- These packages ship ICU binaries per RID, wire up `System.Globalization.AppLocalIcu` automatically,
  and (for AOT) inject an rpath so the loader finds the app-local libraries.

## Packages

| Package | Contents |
|---|---|
| `Icu4C.Runtime` | **meta** — no binaries; depends on the 8 platform packages |
| `Icu4C.Runtime.linux-x64` · `.linux-arm64` · `.linux-musl-x64` · `.linux-musl-arm64` | natives (one RID each) + `build/` targets |
| `Icu4C.Runtime.win-x64` · `.win-arm64` | natives (one RID each) + `build/` targets |
| `Icu4C.Runtime.osx-x64` · `.osx-arm64` | natives (one RID each) + `build/` targets |

On Windows, the platform packages also bundle app-local copies of the Microsoft Visual C++ 2015-2022
runtime (which the ICU DLLs require), so **no VC++ Redistributable needs to be installed**. See
`THIRD-PARTY-NOTICES.md`.

## Usage

Meta (one reference; works on every RID):

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="77.1.3" />
</ItemGroup>
```

Single platform (smaller restore, known target RID):

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.3" />
</ItemGroup>
```

For several RIDs, reference each one conditionally:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.3" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
  <PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.3" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
</ItemGroup>
```

No project-file changes are required. The packages:

- set `InvariantGlobalization=false` (unless you set it explicitly),
- inject `System.Globalization.AppLocalIcu` = the packaged ICU version,
- for `PublishAot=true`, add an rpath (`$ORIGIN` on Linux, `@executable_path` on macOS).

### JIT / framework-dependent

Native libraries come from `runtimes/<rid>/native/` through the standard NuGet native-asset
mechanism (deps.json) and are resolved at runtime.

### Native AOT

The natives are copied to the publish root by the SDK; the injected rpath plus
`System.Globalization.AppLocalIcu` (embedded into the executable by ILC) let the loader find them.

## Download & output size

Because NuGet cannot filter dependencies by RID, a project referencing the **meta** package restores
**all** platform packages (≈119 MB of package downloads, regardless of target RID). What ends up in
the app depends on the publish mode:

| Publish | ICU natives in the output |
|---|---|
| `-r <rid>` / Native AOT | only that RID (≈38 MB) |
| portable (no `-r`) | all 8 RIDs under `runtimes/<rid>/native/` |

To avoid the extra download, reference the specific `Icu4C.Runtime.<rid>` package instead.

## Supported RIDs

`linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `win-x64`, `win-arm64`,
`osx-x64`, `osx-arm64`.

## Platform notes

### Linux (glibc)

The glibc libraries are built on an **AlmaLinux 8 (glibc 2.28)** baseline with `gcc-toolset-13` and
the C++ runtime linked statically. They load on Debian 11+, Ubuntu 20.04+, RHEL/Alma/Rocky 8-9,
Amazon Linux 2/2023, Debian 12, etc. — required glibc is **2.28**, and there is no
`libstdc++.so.6` / `libgcc_s.so.1` dependency.

### Linux (musl / Alpine)

The musl libraries have no version floor and no `libstdc++`/`libgcc_s` dependency — they only need
musl. (The .NET runtime itself still needs `libstdc++` for **JIT** on musl; the official Alpine
images provide it. The AOT output needs neither.) Note that the official **.NET Alpine images set
`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true`** by default, so ICU is not used unless you override it:

```dockerfile
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
```

### Windows

No VC++ Redistributable is required — the MSVC runtime is bundled app-locally next to the ICU DLLs.

## Warnings

| Code | Meaning |
|---|---|
| `ICU4C001` | Target RID has no platform package (emitted by the meta package). |
| `ICU4C003` | `InvariantGlobalization=true` conflicts with this package; ICU won't be enabled. |

A platform package is silent when it is used while building for a different RID (it may also be
pulled in transitively by the meta package).

## How it works

- `Icu4C.Runtime` (meta) ships `buildTransitive/Icu4C.Runtime.targets`: it injects `AppLocalIcu` and
  adds the AOT rpath. Its nuspec lists the 8 platform packages as dependencies.
- A platform package ships the natives under `runtimes/<rid>/native/` and a `build/Icu4C.Runtime.<rid>.targets`.
  `build/` assets apply **only to direct references** (not transitively), so they are not re-applied
  when the platform packages arrive through the meta package. The platform targets inject
  `AppLocalIcu` only when building for their RID.

## Building the native binaries

ICU binaries are produced per RID and placed under `runtimes/<rid>/native/`.

- Linux (glibc/musl), from source: `scripts/build-icu-linux.sh <icu-version> <rid>` (the glibc
  artifacts are built on an old glibc baseline — AlmaLinux 8 / glibc 2.28 — with the C++ runtime
  statically linked, and `patchelf` is used to make the libraries resolve their siblings via
  `$ORIGIN`; see *Platform notes*)
- Linux quick extraction (validation only): `scripts/extract-icu-linux.sh <rid> <ubuntu-version> <pkg>`
- Windows: `scripts/build-icu-windows.ps1 <icu-version> <rid>` (also stages the app-local MSVC
  runtime DLLs next to the ICU DLLs, and fails if the runtime closure is incomplete)
- macOS: `scripts/build-icu-macos.sh <icu-version> <rid>`

The scripts honor `ICU_CACHE_DIR` (reuse the downloaded source) and `ICU_GH_PROXY` (GitHub proxy
when github.com is unreachable). Cross-compilation for Linux ARM64 builds the x64 host tools first.

## Packing

Pack the platform packages first, then the meta package (which resolves them from the local feed):

```bash
for rid in linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 win-x64 win-arm64 osx-x64 osx-arm64; do
  dotnet pack src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj -c Release -o nupkg -p:IcuRid=$rid
done
dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg
```

## Local verification

- Linux: `scripts/verify-local.sh` (container-based). ICU is loaded via `dlopen`, so
  `ldd | grep icu` will not show it — rely on the app output and, for AOT, on `readelf -d` showing an
  `$ORIGIN` runpath.
- CI: `scripts/verify-linux.sh` — static checks (glibc floor, exact inter-library NEEDED names,
  `$ORIGIN` runpath, no `libstdc++`/`libgcc_s`) plus JIT (linux-x64, linux-musl-x64) and AOT
  (linux-x64) smoke tests in the official runtime images with the system ICU hidden.
- Windows: `scripts/verify-windows.ps1` — publishes and runs the JIT test in RID-specific and
  portable modes and checks that the app-local MSVC runtime closure is complete; it also runs the
  Native AOT test when the MSVC toolset + Windows SDK are available.

## Versioning

Package version is `{icu-major}.{icu-minor}.{revision}` — the first two parts track the ICU version,
the third is the packaging revision (starts at 1):

- `77.1.1` — first release for ICU 77.1
- `77.1.2`, `77.1.3`, … — bugfix / repack releases of the **same** ICU 77.1

The version is defined once in `Directory.Build.props` as `<IcuPackageVersion>`; all packages and the
test projects consume it.

- The ICU shared libraries keep their own version (`77.1` → `libicu*.so.77.1`, `libicu*.77.1.dylib`,
  `icuuc77.dll`); the package version does not change the `.so`/`.dll` names.
- The ICU version used for `AppLocalIcu` is independent: it lives in `_IcuVersion` inside the targets.

## Building & releasing (CI)

`.github/workflows/build.yml` builds all RIDs and packs the 9 packages (it uses arm64 Linux runners,
`macos-15-intel` for `osx-x64`, and `windows-2022`):

- runs on **`v*` tags**, on **pull requests** touching build files, and on **manual dispatch**
- each package is uploaded as its **own artifact**: `pkg-<rid>` = the platform packages, `nupkg-core`
  = the (tiny) meta package
- **NuGet publishing is manual**: tag pushes and normal runs only build + upload artifacts. To
  publish, run the workflow manually with the `publish` input enabled (requires the `NUGET_API_KEY`
  repository secret). Otherwise download the package artifacts and push them yourself:

  ```bash
  dotnet nuget push "*.nupkg" --api-key <KEY> --source https://api.nuget.org/v3/index.json
  ```

## License

- This project (`Icu4C.Runtime` build scripts, targets, and packaging) is licensed under the
  **GNU Affero General Public License v3.0** (AGPL-3.0-only). See [LICENSE](LICENSE).
- The bundled ICU binaries are licensed under the **Unicode License v3**. See
  [LICENSE-ICU](LICENSE-ICU). Redistribution must retain that copyright notice.
- The Windows packages additionally bundle the Microsoft Visual C++ Redistributable runtime DLLs,
  which remain under Microsoft's own license terms. See
  [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
