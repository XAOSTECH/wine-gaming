// UniversalApiContract.il — stub for Windows.Foundation.UniversalApiContract
//
// Compile:   ilasm /dll UniversalApiContract.il
//
// Iteration 2: empty shell wasn't enough. Mono loaded the assembly but failed
// to resolve `Windows.UI.ViewManagement.UISettings` inside it. Now we define
// the type skeleton so Mono's class loader can compute field layout for
// XboxInstaller.Helpers.TextScaling+UnsafeUiSettings:_uiSettings.
//
// The methods themselves return harmless defaults — TextScaling's static
// constructor likely instantiates UISettings and reads TextScaleFactor;
// we return 1.0 (no scaling) and accept that any other property access
// will return zero/null.

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

// ============================================================================
// Windows.UI.ViewManagement.UISettings — accessibility/DPI settings facade
// ============================================================================
.class public auto ansi Windows.UI.ViewManagement.UISettings
       extends [mscorlib]System.Object
{
  // Parameterless constructor — UnsafeUiSettings probably does `new UISettings()`
  .method public hidebysig specialname rtspecialname
          instance void .ctor() cil managed
  {
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }

  // TextScaleFactor (double) — return 1.0 = 100% (no scaling)
  // Most likely property TextScaling reads. Real range: 1.0..2.25
  .method public hidebysig specialname
          instance float64 get_TextScaleFactor() cil managed
  {
    ldc.r8 1.0
    ret
  }

  .property instance float64 TextScaleFactor()
  {
    .get instance float64 Windows.UI.ViewManagement.UISettings::get_TextScaleFactor()
  }

  // TextScaleFactorChanged event — needed if the app subscribes to it.
  // add/remove no-op (the event will never fire).
  .method public hidebysig specialname
          instance void add_TextScaleFactorChanged(
            class [mscorlib]System.EventHandler`2<
              class Windows.UI.ViewManagement.UISettings,
              object> 'value') cil managed
  {
    ret
  }

  .method public hidebysig specialname
          instance void remove_TextScaleFactorChanged(
            class [mscorlib]System.EventHandler`2<
              class Windows.UI.ViewManagement.UISettings,
              object> 'value') cil managed
  {
    ret
  }

  .event class [mscorlib]System.EventHandler`2<
            class Windows.UI.ViewManagement.UISettings,
            object> TextScaleFactorChanged
  {
    .addon instance void Windows.UI.ViewManagement.UISettings::add_TextScaleFactorChanged(class [mscorlib]System.EventHandler`2<class Windows.UI.ViewManagement.UISettings, object>)
    .removeon instance void Windows.UI.ViewManagement.UISettings::remove_TextScaleFactorChanged(class [mscorlib]System.EventHandler`2<class Windows.UI.ViewManagement.UISettings, object>)
  }
}

// ============================================================================
// Windows.Management.Deployment.PackageManager — UWP/MSIX package management
// ============================================================================
// THIS IS THE WALL. PackageManager is how the Xbox installer registers the
// MSIX package containing the actual Xbox app. Wine has no MSIX activation
// model, so even with the type stubbed, runtime calls will fail.
//
// We stub it here so the FIELD LOAD in PackageManagerHelper:_packageManager
// succeeds — pushing the failure from "can't construct MainWindow" to
// "MainWindow constructed but first PackageManager call throws". That tells
// us which method gets called first and whether there's any path forward.
//
// All methods throw NotSupportedException; the .ctor is a no-op.
// ============================================================================
.class public auto ansi Windows.Management.Deployment.PackageManager
       extends [mscorlib]System.Object
{
  .method public hidebysig specialname rtspecialname
          instance void .ctor() cil managed
  {
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }

  // Common entry points the installer is likely to call. Each throws so
  // we get a clear "Wine cannot install MSIX packages" failure instead of
  // a confusing crash inside Mono.
  .method public hidebysig instance object FindPackagesForUser(string user) cil managed
  {
    ldstr "Wine has no UWP/MSIX support — Xbox app cannot be installed."
    newobj instance void [mscorlib]System.NotSupportedException::.ctor(string)
    throw
  }

  .method public hidebysig instance object FindPackages() cil managed
  {
    ldstr "Wine has no UWP/MSIX support — Xbox app cannot be installed."
    newobj instance void [mscorlib]System.NotSupportedException::.ctor(string)
    throw
  }

  .method public hidebysig instance object RegisterPackageAsync(
            class [mscorlib]System.Uri packageUri,
            object dependencyPackageUris,
            int32 deploymentOptions) cil managed
  {
    ldstr "Wine has no UWP/MSIX support — Xbox app cannot be installed."
    newobj instance void [mscorlib]System.NotSupportedException::.ctor(string)
    throw
  }

  .method public hidebysig instance object AddPackageAsync(
            class [mscorlib]System.Uri packageUri,
            object dependencyPackageUris,
            int32 deploymentOptions) cil managed
  {
    ldstr "Wine has no UWP/MSIX support — Xbox app cannot be installed."
    newobj instance void [mscorlib]System.NotSupportedException::.ctor(string)
    throw
  }
}
