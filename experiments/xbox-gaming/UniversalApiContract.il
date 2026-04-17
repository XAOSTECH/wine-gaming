// UniversalApiContract.il — empty stub for Windows.Foundation.UniversalApiContract
//
// Compile:   ilasm /dll /key=<snk> UniversalApiContract.il
// Install:   gacutil /i Windows.Foundation.UniversalApiContract.dll
//            (or copy into prefix .NET GAC manually)
//
// This is a metadata-only "contract" assembly — like the real WinRT facade,
// it contains no executable types, only the assembly identity. Just having
// the assembly resolve is enough to satisfy Mono's type loader and stop the
// cascading failure in WPF's Setter initialisation.
//
// Note: PublicKeyToken in the original error is "null", meaning unsigned —
// so we don't actually need a strong-name key. ilasm /dll alone is enough.

.assembly extern mscorlib
{
  .publickeytoken = (B7 7A 5C 56 19 34 E0 89)
  .ver 4:0:0:0
}

.assembly Windows.Foundation.UniversalApiContract
{
  .ver 7:0:0:0
}

.module Windows.Foundation.UniversalApiContract.dll

// Deliberately empty — metadata-only contract assembly.
// Real WinRT contracts contain type-forwarders to Windows.* implementation
// DLLs that don't exist on Wine; an empty assembly is a strict superset of
// "nothing loadable" for our purpose (preventing the AssemblyLoadException).
