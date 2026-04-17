#!/bin/bash
# try-native-dotnet.sh — launch Xbox installer with native .NET 4.8 instead
# of Wine-Mono. Requires `winetricks dotnet48` to have been run (init does this).
#
# Why: Wine-Mono has zero WinRT interop. The native .NET 4.8 framework has
# proper COM/WinRT type marshalling and may stub out UISettings cleanly.
#
# Usage:  ./try-native-dotnet.sh /path/to/XboxInstaller.exe

set -euo pipefail

EXE="${1:-}"
if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    echo "Usage: $0 /path/to/XboxInstaller.exe" >&2
    exit 1
fi

# n,b = native first, then builtin (Mono) as fallback for any other .NET refs.
# Cover all the .NET runtime entry points: mscoree (loader), mscorwks (CLR 2),
# clr (CLR 4), and the WPF assemblies that touched the failure path.
export WINEDLLOVERRIDES="mscoree,mscorwks,clr=n,b;PresentationCore,PresentationFramework,WindowsBase=n,b"

# Verbose Mono trace if we still hit Mono — helps confirm the override took.
export WINEDEBUG="${WINEDEBUG:-+mscoree,+loaddll}"

exec wig launch-exe "$EXE"
