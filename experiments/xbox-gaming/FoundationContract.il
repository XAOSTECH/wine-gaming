// FoundationContract.il — stub for Windows.Foundation.FoundationContract
//
// Iter 4: define TypedEventHandler<TSender, TResult> — the WinRT-style
// generic event delegate used by UISettings.TextScaleFactorChanged etc.
// SafeUiSettings ctor references this and crashed on field-load.

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

// ============================================================================
// Windows.Foundation.TypedEventHandler<TSender, TResult>
//   The WinRT projection of a delegate type — equivalent to
//   System.EventHandler but with strongly-typed sender/args.
// ============================================================================
.class public auto ansi sealed Windows.Foundation.TypedEventHandler`2<TSender, TResult>
       extends [mscorlib]System.MulticastDelegate
{
  .method public hidebysig specialname rtspecialname
          instance void .ctor(object 'object', native int 'method') runtime managed
  {
  }

  .method public hidebysig newslot virtual
          instance void Invoke(!TSender sender, !TResult args) runtime managed
  {
  }

  .method public hidebysig newslot virtual
          instance class [mscorlib]System.IAsyncResult BeginInvoke(
            !TSender sender,
            !TResult args,
            class [mscorlib]System.AsyncCallback callback,
            object 'object') runtime managed
  {
  }

  .method public hidebysig newslot virtual
          instance void EndInvoke(class [mscorlib]System.IAsyncResult result) runtime managed
  {
  }
}
