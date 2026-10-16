// SPDX-License-Identifier: MIT
using System.Runtime.InteropServices;
namespace ThreeE.PhoneBar.Windows;

internal static class WindowsOutputVolume {
    [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] private class Enumerator { }
    [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDevices {
        [PreserveSig] int EnumAudioEndpoints(int flow,uint mask,out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow,int role,out IDevice device);
    }
    [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDevice {
        [PreserveSig] int Activate(ref Guid id,uint context,IntPtr parameters,[MarshalAs(UnmanagedType.IUnknown)] out object endpoint);
    }
    [ComImport,Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr callback);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr callback);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float level,ref Guid context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level,ref Guid context);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel,float level,ref Guid context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel,float level,ref Guid context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel,out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel,out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute,ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }
    private static T WithEndpoint<T>(Func<IVolume,T> action) {
        var devices=(IDevices)new Enumerator();IDevice device=null;object endpoint=null;
        try {
            Marshal.ThrowExceptionForHR(devices.GetDefaultAudioEndpoint(0,1,out device)); // Render, multimedia.
            var id=typeof(IVolume).GUID;
            Marshal.ThrowExceptionForHR(device.Activate(ref id,23,IntPtr.Zero,out endpoint));
            return action((IVolume)endpoint);
        } finally {
            if(endpoint!=null)Marshal.ReleaseComObject(endpoint);
            if(device!=null)Marshal.ReleaseComObject(device);
            Marshal.ReleaseComObject(devices);
        }
    }
    public static int? Read()=>WithEndpoint<int?>(endpoint=> {
        Marshal.ThrowExceptionForHR(endpoint.GetMasterVolumeLevelScalar(out float level));
        Marshal.ThrowExceptionForHR(endpoint.GetMute(out bool mute));
        return mute?0:(int)Math.Round(level*100);
    });
    public static void Write(int level)=>WithEndpoint(endpoint=> {
        var context=Guid.Empty;
        Marshal.ThrowExceptionForHR(endpoint.SetMasterVolumeLevelScalar(Math.Clamp(level,0,100)/100f,ref context));
        if(level>0)Marshal.ThrowExceptionForHR(endpoint.SetMute(false,ref context));
        return true;
    });
}
