# Icu4C.Runtime.&lt;rid&gt;

AppLocal ICU4C runtime binaries for a **single RID**, for .NET 10 — full globalization in
**JIT and Native AOT** without a host-installed ICU.

This is a **platform package**: it bundles the natives for one RID (≈15 MB) plus a `build/` targets
file. It is also pulled in transitively by the `Icu4C.Runtime` meta package.

## Usage

Reference the package that matches your target RID, e.g. for `linux-x64`:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" />
</ItemGroup>
```

For multiple RIDs, reference each one conditionally:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
  <PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.4" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
</ItemGroup>
```

If instead you want a single reference that works on every RID, use the meta package
`Icu4C.Runtime` (which depends on all platform packages).

The package's `build/` targets:

- inject `System.Globalization.AppLocalIcu` **only when building for its RID**,
- set `InvariantGlobalization=false` (unless you set it),
- for `PublishAot=true`, copy the natives to the publish root and add an rpath.

When the package is used while building for a different RID, it is a silent no-op.

On Windows, this package also bundles app-local copies of the Microsoft Visual C++ 2015-2022 runtime
(required by the ICU DLLs), so **no VC++ Redistributable needs to be installed**.

## License

- This project is licensed under **Apache-2.0** (see `LICENSE`).
- The bundled ICU binaries are licensed under the **Unicode License v3** (see `LICENSE-ICU`).
- The Windows packages additionally bundle the Microsoft Visual C++ Redistributable runtime DLLs,
  under Microsoft's own license terms (see `THIRD-PARTY-NOTICES.md`).
