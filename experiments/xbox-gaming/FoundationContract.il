// FoundationContract.il — stub for Windows.Foundation.FoundationContract
//
// SafeUiSettings (the fallback path of XboxInstaller.Helpers.TextScaling)
// pulls in this contract — likely for IPropertyValue / IReference<T> /
// the WinRT projection types used by UISettings property accessors.
//
// We don't know exactly which types it touches yet — this is iter 1 (empty).
// Mono will tell us with a "Could not resolve type X in assembly
// FoundationContract" message which we'll fill in next.

.assembly extern mscorlib
{
  .publickeytoken = (B7 7A 5C 56 19 34 E0 89)
  .ver 4:0:0:0
}

.assembly Windows.Foundation.FoundationContract
{
  .ver 3:0:0:0
}

.module Windows.Foundation.FoundationContract.dll

// Empty for now — wait for Mono's next type-resolution error to tell us
// which class skeleton to add.
