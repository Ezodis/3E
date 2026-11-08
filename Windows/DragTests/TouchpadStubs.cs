// No WinUI window or raw-input registration is created by frame assembly tests.
using ThreeFingerDragEngine.utils;
namespace ThreeFingerDragOnWindows.touchpad {
    public sealed class HandlerWindow {
        public readonly List<TouchpadContact[]> Frames=new();
        public void OnTouchpadContact(IntPtr device,List<TouchpadContact> contacts)=>Frames.Add(contacts.Where(c=>c.IsActive).ToArray());
        public void OnTouchpadInitialized(bool exists,bool installed) { }
    }
    static class Interop {
        public static IntPtr SetWndProc(IntPtr window,Func<IntPtr,uint,IntPtr,IntPtr,IntPtr> callback)=>IntPtr.Zero;
        public static IntPtr CallWindowProc(IntPtr old,IntPtr window,uint message,IntPtr w,IntPtr l)=>IntPtr.Zero;
    }
}
namespace ThreeFingerDragOnWindows.utils {
    static class Logger { public static void Log(string message){} }
    static class TouchpadHelper {
        public const uint WM_INPUT=255,WM_INPUT_DEVICE_CHANGE=254;
        public static bool Exists()=>true;
        public static bool Exists(IntPtr device)=>true;
        public static bool RegisterInput(IntPtr window)=>true;
        public static (IntPtr,List<TouchpadContact>,uint) ParseInput(IntPtr data)=>throw new NotSupportedException();
    }
}
namespace WinRT.Interop { static class WindowNative {public static IntPtr GetWindowHandle(object window)=>IntPtr.Zero;} }
namespace WinUICommunity { }
