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

  // Iter 6: Real signatures matter. Mono uses strict signature matching for
  // MissingMethodException — `object FindPackagesForUser(string)` does NOT
  // satisfy a call to `IEnumerable<Package> FindPackagesForUser(string,string)`.
  //
  // Strategy shift: return EMPTY collections instead of throwing. This lets
  // `IsInstalled()` return false naturally and the app proceeds past the
  // gate to whatever it actually does next (download? register? launch
  // browser?). That's the trace we want — the "what would the update do"
  // information the user is hoping to see.

  // FindPackagesForUser(packageFamilyName, userSecurityId) → IEnumerable<Package>
  // The two-string overload Xbox installer uses.
  .method public hidebysig instance class [mscorlib]System.Collections.Generic.IEnumerable`1<class Windows.ApplicationModel.Package>
          FindPackagesForUser(string user, string packageFamilyName) cil managed
  {
    ldc.i4.0
    newarr Windows.ApplicationModel.Package
    ret
  }

  // Single-arg overload (older API surface, kept for safety)
  .method public hidebysig instance class [mscorlib]System.Collections.Generic.IEnumerable`1<class Windows.ApplicationModel.Package>
          FindPackagesForUser(string user) cil managed
  {
    ldc.i4.0
    newarr Windows.ApplicationModel.Package
    ret
  }

  // FindPackages() — no args overload
  .method public hidebysig instance class [mscorlib]System.Collections.Generic.IEnumerable`1<class Windows.ApplicationModel.Package>
          FindPackages() cil managed
  {
    ldc.i4.0
    newarr Windows.ApplicationModel.Package
    ret
  }

  // FindPackages(packageFamilyName) — single-string overload
  .method public hidebysig instance class [mscorlib]System.Collections.Generic.IEnumerable`1<class Windows.ApplicationModel.Package>
          FindPackages(string packageFamilyName) cil managed
  {
    ldc.i4.0
    newarr Windows.ApplicationModel.Package
    ret
  }

  // Register/Add still throw — these would actually attempt MSIX deployment.
  // Throwing here is the explicit "this is the wall" signal.
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

// ============================================================================
// Windows.ApplicationModel.Package — represents an installed UWP package
// ============================================================================
// Iter 5: PackageManagerHelper iterates installed packages. Stub the type
// so type-load succeeds; properties return null/empty defaults.
// ============================================================================
.class public auto ansi Windows.ApplicationModel.Package
       extends [mscorlib]System.Object
{
  .method public hidebysig specialname rtspecialname
          instance void .ctor() cil managed
  {
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }

  .method public hidebysig specialname
          instance string get_Id() cil managed
  {
    ldnull
    ret
  }

  .property instance string Id()
  {
    .get instance string Windows.ApplicationModel.Package::get_Id()
  }
}

// ============================================================================
// Windows.Management.Deployment.PackageVolume — install target volume
// ============================================================================
// Iter 8: After the EULA Install button, InstallManager.BeginInstallAsync
// references AppInstallOptionsShim.TargetVolume of this type. Mono fails
// the field's type-load if the type doesn't exist, even when the value
// is null. Pure stub — no behaviour needed; installer treats null as
// "system default volume", which is what we want anyway since we have
// no real MSIX volume to point at.
// ============================================================================
.class public auto ansi Windows.Management.Deployment.PackageVolume
       extends [mscorlib]System.Object
{
  .method public hidebysig specialname rtspecialname
          instance void .ctor() cil managed
  {
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }

  .method public hidebysig specialname
          instance string get_Name() cil managed
  {
    ldstr ""
    ret
  }

  .method public hidebysig specialname
          instance bool get_IsSystemVolume() cil managed
  {
    ldc.i4.1
    ret
  }

  .method public hidebysig specialname
          instance bool get_IsOffline() cil managed
  {
    ldc.i4.0
    ret
  }

  .property instance string Name()
  {
    .get instance string Windows.Management.Deployment.PackageVolume::get_Name()
  }
  .property instance bool IsSystemVolume()
  {
    .get instance bool Windows.Management.Deployment.PackageVolume::get_IsSystemVolume()
  }
  .property instance bool IsOffline()
  {
    .get instance bool Windows.Management.Deployment.PackageVolume::get_IsOffline()
  }
}

// ============================================================================
// Windows.System.Profile.AnalyticsInfo — telemetry/version info facade
// ============================================================================
// Iter 5: WPF telemetry path queries this. Stub returns nothing useful.
// ============================================================================
.class public abstract auto ansi sealed Windows.System.Profile.AnalyticsInfo
       extends [mscorlib]System.Object
{
  .method public hidebysig specialname static
          string get_DeviceFamily() cil managed
  {
    ldstr "Windows.Desktop"
    ret
  }

  .property string DeviceFamily()
  {
    .get string Windows.System.Profile.AnalyticsInfo::get_DeviceFamily()
  }

  .method public hidebysig specialname static
          class Windows.System.Profile.AnalyticsVersionInfo get_VersionInfo() cil managed
  {
    newobj instance void Windows.System.Profile.AnalyticsVersionInfo::.ctor()
    ret
  }

  .property class Windows.System.Profile.AnalyticsVersionInfo VersionInfo()
  {
    .get class Windows.System.Profile.AnalyticsVersionInfo Windows.System.Profile.AnalyticsInfo::get_VersionInfo()
  }
}

// ============================================================================
// Windows.System.Profile.AnalyticsVersionInfo — version triplet returned by
// AnalyticsInfo.VersionInfo. Iter 7: app calls .VersionInfo and expects a
// real instance with DeviceFamily / DeviceFamilyVersion strings.
// ============================================================================
.class public auto ansi Windows.System.Profile.AnalyticsVersionInfo
       extends [mscorlib]System.Object
{
  .method public hidebysig specialname rtspecialname
          instance void .ctor() cil managed
  {
    ldarg.0
    call instance void [mscorlib]System.Object::.ctor()
    ret
  }

  // Match a recent Win10/11 build number — pretend to be 10.0.22621.x
  // (Windows 11 22H2). Format is a packed UInt64 as a decimal string.
  .method public hidebysig specialname
          instance string get_DeviceFamilyVersion() cil managed
  {
    ldstr "2814751208898560"
    ret
  }

  .property instance string DeviceFamilyVersion()
  {
    .get instance string Windows.System.Profile.AnalyticsVersionInfo::get_DeviceFamilyVersion()
  }

  .method public hidebysig specialname
          instance string get_DeviceFamily() cil managed
  {
    ldstr "Windows.Desktop"
    ret
  }

  .property instance string DeviceFamily()
  {
    .get instance string Windows.System.Profile.AnalyticsVersionInfo::get_DeviceFamily()
  }
}
