#!/usr/bin/env python3
"""Verify the app-local ICU shared libraries can be dlopen'ed on the current host.

Usage: dlopen-check.py <dir_with_libs> <version>   (version e.g. 77.1)
Loads libicudata first (as the .NET runtime does), then libicuuc and libicui18n.
"""
import ctypes
import os
import sys

libdir, version = sys.argv[1], sys.argv[2]
for name in (f"libicudata.so.{version}", f"libicuuc.so.{version}", f"libicui18n.so.{version}"):
    ctypes.CDLL(os.path.join(libdir, name))
print("dlopen OK")
