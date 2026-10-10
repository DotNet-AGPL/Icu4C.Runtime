# Third-party notices

## ICU (International Components for Unicode)

The `Icu4C.Runtime` packages bundle ICU4C binaries. ICU is distributed under the
**Unicode License v3**. See `LICENSE-ICU` for the full text.

## Microsoft Visual C++ Runtime (Windows packages only)

The Windows platform packages (`Icu4C.Runtime.win-x64`, `Icu4C.Runtime.win-arm64`)
include app-local copies of the Microsoft Visual C++ 2015-2022 Redistributable runtime
DLLs (`msvcp140*.dll`, `vcruntime140*.dll`). These files are required by the ICU DLLs,
which link against the DLL C runtime (`/MD`).

These files are distributed under the **Microsoft Software License Terms for the
Microsoft Visual C++ Redistributable** and are redistributable together with an
application. They are provided here so that consumers do not need to install the
VC++ Redistributable separately.

- Reference: <https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist>
- License/dependencies: each bundled binary is copyright Microsoft Corporation and is
  governed by its own license terms, not by the license of this project.
