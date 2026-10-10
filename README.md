# Icu4C.Runtime

AppLocal ICU4C runtime binaries for .NET 10 — full globalization (ICU) support in **JIT and Native
AOT**, without relying on a host-installed ICU.

Two ways to consume it:

- **Universal** `Icu4C.Runtime` — all RIDs in one package (one-line reference, ≈120 MB restore).
- **Slim** `Icu4C.Runtime.<rid>` — one RID per package (≈15 MB each), for when restore size matters.

## Why

- The .NET runtime normally depends on a system-installed ICU. In slim containers it may be missing
  and apps crash with `FailFast: Couldn't find a valid ICU package`.
- `Microsoft.ICU.ICU4C.Runtime` is unmaintained and doesn't cover .NET 10 / Native AOT.
- This package ships ICU binaries per RID, wires up `System.Globalization.AppLocalIcu` automatically,
  and (for AOT) copies the binaries next to the executable and injects an rpath.

## Packages

| Package | Contents | Restore size |
|---|---|---|
| `Icu4C.Runtime` | all 8 RIDs | ≈120 MB |
| `Icu4C.Runtime.linux-x64` · `.linux-arm64` · `.linux-musl-x64` · `.linux-musl-arm64` | one RID each | ≈15 MB each |
| `Icu4C.Runtime.win-x64` · `.win-arm64` | one RID each | ≈15 MB each |
| `Icu4C.Runtime.osx-x64` · `.osx-arm64` | one RID each | ≈15 MB each |

## Usage

Universal (works on every RID):

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="77.1.0" />
</ItemGroup>
```

Slim (per RID — **do not reference both a slim package and the universal one**):

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.0" />
</ItemGroup>
```

For several RIDs, reference each one conditionally:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.0" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
  <PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.0" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
</ItemGroup>
```

No project-file changes are required. The package's `buildTransitive` targets:

- set `InvariantGlobalization=false` (unless you set it explicitly),
- inject `System.Globalization.AppLocalIcu` = the packaged ICU version,
- for `PublishAot=true`, copy the native libraries to the publish root and inject an rpath.

### JIT / framework-dependent

Native libraries come from `runtimes/{rid}/native/` through the standard NuGet native-asset
mechanism (deps.json) and are resolved at runtime.

### Native AOT

Native libraries are copied to the publish root and loaded from the application directory
(`System.Globalization.AppLocalIcu` embedded into the executable by ILC). On Linux the loader uses
`$ORIGIN`; on macOS `@executable_path`.

## Supported RIDs

`linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `win-x64`, `win-arm64`,
`osx-x64`, `osx-arm64`.

Unsupported RIDs produce warning `ICU4C001`.

## Warnings

| Code | Meaning |
|---|---|
| `ICU4C001` | Target RID has no binaries in this package. |
| `ICU4C002` | No ICU native binaries found under the package's `runtimes/<rid>/native`. |
| `ICU4C003` | `InvariantGlobalization=true` conflicts with this package; ICU won't be enabled. |
| `ICU4C004` | The bundled binary's major version doesn't match the declared ICU version. |
| `ICU4C005` | A slim package for a different RID is in use. |

## How it works

- Both package kinds share `buildTransitive/_IcuRuntimeCore.targets`.
- Each package ships an id-named shim that imports the core
  (`Icu4C.Runtime.targets` for the universal package, `Icu4C.Runtime.<rid>.targets` for slim).
- `AppLocalIcu` and `InvariantGlobalization` are injected at **evaluation time**, so they apply to
  both JIT and Native AOT (ILC reads `RuntimeHostConfigurationOption` while writing its rsp file).
- For AOT the core copies the libraries to the publish root and adds `-Wl,-rpath,'$ORIGIN'`
  (Linux) / `'@executable_path'` (macOS).

## Building the native binaries

ICU binaries are produced per RID and placed under `runtimes/<rid>/native/`.

- Linux (glibc/musl), from source: `scripts/build-icu-linux.sh <icu-version> <rid>`
- Linux quick extraction (validation only): `scripts/extract-icu-linux.sh <rid> <ubuntu-version> <pkg>`
- Windows: `scripts/build-icu-windows.ps1 <icu-version> <rid>`
- macOS: `scripts/build-icu-macos.sh <icu-version> <rid>`

The scripts honor `ICU_CACHE_DIR` (reuse the downloaded source) and `ICU_GH_PROXY` (GitHub proxy
when github.com is unreachable). Cross-compilation for Linux ARM64 builds the x64 host tools first.

## Packing

```bash
# Universal package (all RIDs)
dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg

# Slim packages (one per RID)
for rid in linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 win-x64 win-arm64 osx-x64 osx-arm64; do
  dotnet pack src/Icu4C.Runtime.Slim/Icu4C.Runtime.Slim.csproj -c Release -o nupkg -p:IcuRid=$rid
done
```

## Local verification

See `scripts/verify-local.sh`. It publishes the JIT and AOT test apps and runs them in containers.
ICU is loaded via `dlopen`, so `ldd | grep icu` will not show it — rely on the app output and, for
AOT, on `readelf -d` showing an `$ORIGIN` runpath.

## Versioning

Package version is `{icu-major}.{icu-minor}.{base}[.{revision}]`:

- `77.1.0` — first release for ICU 77.1
- `77.1.0.1`, `77.1.0.2`, … — bugfix / repack releases of the **same** ICU 77.1

The version is defined once in `Directory.Build.props` as `<IcuPackageVersion>`; all packages and the
test projects consume it.

- NuGet supports 4-part versions. **Do not use a zero 4th part** (`77.1.0.0` normalizes to `77.1.0`).
- The ICU version used for `AppLocalIcu` is independent: it lives in `_IcuVersion` inside
  `buildTransitive/_IcuRuntimeCore.targets` and must match the bundled binaries' names.

## Building & releasing (CI)

`.github/workflows/build.yml` builds all RIDs and packs the 9 packages (it uses arm64 Linux runners,
`macos-15-intel` for `osx-x64`, and `windows-2022`):

- runs on **`v*` tags**, on **pull requests** touching build files, and on **manual dispatch**
- **NuGet publishing is manual**: tag pushes and normal runs only build + upload artifacts. To
  publish, run the workflow manually with the `publish` input enabled (requires the `NUGET_API_KEY`
  repository secret). Otherwise download the `nupkg` artifact and push it yourself:

  ```bash
  dotnet nuget push "nupkg/*.nupkg" --api-key <KEY> --source https://api.nuget.org/v3/index.json
  ```

## License

- This project (`Icu4C.Runtime` build scripts, targets, and packaging) is licensed under the
  **GNU Affero General Public License v3.0** (AGPL-3.0-only). See [LICENSE](LICENSE).
- The bundled ICU binaries are licensed under the **Unicode License v3**. See
  [LICENSE-ICU](LICENSE-ICU). Redistribution must retain that copyright notice.
