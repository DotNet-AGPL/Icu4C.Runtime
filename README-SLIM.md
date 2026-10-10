# Icu4C.Runtime.&lt;rid&gt; (slim)

AppLocal ICU4C runtime binaries for a **single RID**, for .NET 10 — full globalization in
**JIT and Native AOT** without a host-installed ICU.

This is the slim variant: it bundles the binaries for one RID only (≈15 MB) instead of all RIDs
(≈120 MB). Use it when restore size matters and you know your target RID.

> Prefer the universal `Icu4C.Runtime` package if you need a single reference that works on every
> RID. **Do not reference both** the universal package and a slim package.

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

The package's targets inject `System.Globalization.AppLocalIcu`, set `InvariantGlobalization=false`
(unless you set it), and for `PublishAot=true` copy the libraries to the publish root and add an rpath.

If you use a slim package while building for a different RID, warning `ICU4C005` is emitted.

## Warning codes

| Code | Meaning |
|---|---|
| `ICU4C001` | Target RID is not covered by this package. |
| `ICU4C002` | No ICU native binaries found under the package's `runtimes/<rid>/native`. |
| `ICU4C003` | `InvariantGlobalization=true` conflicts with this package. |
| `ICU4C004` | Bundled binary major version doesn't match the declared ICU version. |
| `ICU4C005` | A slim package for a different RID is in use. |

## License

- This project is licensed under **AGPL-3.0-only** (see `LICENSE`).
- The bundled ICU binaries are licensed under the **Unicode License v3** (see `LICENSE-ICU`).
