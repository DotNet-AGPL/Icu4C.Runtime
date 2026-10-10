# Icu4C.Runtime.&lt;rid&gt;

AppLocal ICU4C runtime binaries for a **single RID**, for .NET 10 — full globalization in
**JIT and Native AOT** without a host-installed ICU.

This is a **platform package**: it bundles the natives for one RID (≈15 MB) plus a `build/` targets
file. It is also pulled in transitively by the `Icu4C.Runtime` meta package.

## Usage

Reference the package that matches your target RID, e.g. for `linux-x64`:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.1" />
</ItemGroup>
```

For multiple RIDs, reference each one conditionally:

```xml
<ItemGroup>
  <PackageReference Include="Icu4C.Runtime.linux-x64" Version="77.1.1" Condition="'$(RuntimeIdentifier)' == 'linux-x64'" />
  <PackageReference Include="Icu4C.Runtime.win-x64"   Version="77.1.1" Condition="'$(RuntimeIdentifier)' == 'win-x64'" />
</ItemGroup>
```

If instead you want a single reference that works on every RID, use the meta package
`Icu4C.Runtime` (which depends on all platform packages).

The package's `build/` targets:

- inject `System.Globalization.AppLocalIcu` **only when building for its RID**,
- set `InvariantGlobalization=false` (unless you set it),
- for `PublishAot=true`, copy the natives to the publish root and add an rpath.

When the package is used while building for a different RID, it is a silent no-op.

## License

- This project is licensed under **AGPL-3.0-only** (see `LICENSE`).
- The bundled ICU binaries are licensed under the **Unicode License v3** (see `LICENSE-ICU`).
