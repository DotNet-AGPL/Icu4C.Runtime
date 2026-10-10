# Icu4C.Runtime

AppLocal ICU4C runtime binaries for .NET 10 — use a single `PackageReference` to get full
globalization (ICU) support in **JIT and Native AOT**, without relying on a host-installed ICU.

## Why

- The .NET runtime normally depends on a system-installed ICU. In slim containers the ICU library
  may be missing and apps crash with `FailFast: Couldn't find a valid ICU package`.
- `Microsoft.ICU.ICU4C.Runtime` is no longer maintained and doesn't cover .NET 10 / Native AOT.
- This package ships ICU binaries per RID, wires up `System.Globalization.AppLocalIcu` automatically,
  and (for AOT) copies the binaries next to the executable and injects an rpath so the loader finds them.

## Usage

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime" Version="77.1.0" />
</ItemGroup>
```

That's it. No project-file changes required. The package's `buildTransitive` targets:

- set `InvariantGlobalization=false` (unless you set it explicitly),
- inject `System.Globalization.AppLocalIcu` = the packaged ICU version,
- for `PublishAot=true`, copy the native libraries to the publish root and add an rpath.

### JIT / framework-dependent

Native libraries come from `runtimes/{rid}/native/` through the standard NuGet native-asset
mechanism (deps.json) and are resolved at runtime.

### Native AOT

Native libraries are copied to the publish root and loaded from the application directory
(`System.Globalization.AppLocalIcu` embedded into the executable by ILC).

## Supported RIDs

`linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`, `win-x64`, `win-arm64`,
`osx-x64`, `osx-arm64`.

Unsupported RIDs produce warning `ICU4C001`.

## Warnings

| Code | Meaning |
|---|---|
| `ICU4C001` | Target RID has no bundled native binaries. |
| `ICU4C002` | No ICU native binaries found under the package's `runtimes/{rid}/native`. |
| `ICU4C003` | `InvariantGlobalization=true` conflicts with this package; ICU won't be enabled. |
| `ICU4C004` | The bundled binary's major version doesn't match the declared `_IcuVersion`. |

## Building the native binaries

ICU binaries are produced per RID and placed under `runtimes/{rid}/native/`.

- Linux (glibc/musl), from source: `scripts/build-icu-linux.sh <icu-version> <rid>`
- Linux quick extraction (validation): `scripts/extract-icu-linux.sh <rid> <ubuntu-version> <pkg>`
- Windows: `scripts/build-icu-windows.ps1 <icu-version> <rid>`
- macOS: `scripts/build-icu-macos.sh <icu-version> <rid>`

Then pack:

```bash
dotnet pack src/Icu4C.Runtime/Icu4C.Runtime.csproj -c Release -o nupkg
```

## Local verification

See `scripts/verify-local.sh`. It publishes the JIT and AOT test apps and runs them in containers.

## Versioning

Package version is `{icu-major}.{icu-minor}.{base}[.{revision}]`:

- `77.1.0` — first release for ICU 77.1
- `77.1.0.1`, `77.1.0.2`, … — bugfix / repack releases of the **same** ICU 77.1

The version is defined once in `Directory.Build.props` as `<IcuPackageVersion>`; the package and the
test projects both consume it.

- NuGet supports 4-part versions. **Do not use a zero 4th part** (`77.1.0.0` normalizes to `77.1.0`).
- The ICU version used for `AppLocalIcu` is independent: it lives in `_IcuVersion` inside
  `build*/Icu4C.Runtime.targets` and must match the bundled binaries' names.

## Building & releasing (CI)

The GitHub Actions workflow (`.github/workflows/build.yml`) builds all RIDs and packs a nupkg:

- runs on **`v*` tags**, on **pull requests** touching build files, and on **manual dispatch**
- **NuGet publishing is manual**: tag pushes and normal runs only build + upload artifacts.
  To publish, run the workflow manually with the `publish` input enabled (requires the
  `NUGET_API_KEY` repository secret). Otherwise download the `nupkg` artifact and push it yourself:

  ```bash
  dotnet nuget push Icu4C.Runtime.77.1.0.nupkg --api-key <KEY> --source https://api.nuget.org/v3/index.json
  ```

## License

- This project (`Icu4C.Runtime` build scripts, targets, and packaging) is licensed under the
  **GNU Affero General Public License v3.0** (AGPL-3.0-only). See [LICENSE](LICENSE).
- The bundled ICU binaries are licensed under the **Unicode License v3**. See
  [LICENSE-ICU](LICENSE-ICU). Redistribution must retain that copyright notice.
