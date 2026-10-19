// SPDX-License-Identifier: MIT
using System.Runtime.InteropServices;
using System.Text;
using ThreeE.PhoneControl;
namespace ThreeE.PhoneHost;

// NSPasteboard through PhoneClipboard.m. Calls are serialized: the pasteboard
// is not thread-safe and the receiver may serve several requests at once.
public sealed class MacClipboard : IPhoneClipboard {
    [DllImport("ThreeEPhoneNative")] private static extern int ThreeEPasteboardWrite(byte[] text,int textLength,byte[] html,int htmlLength,byte[] png,int pngLength,byte[] paths,int pathsLength);
    [DllImport("ThreeEPhoneNative")] private static extern int ThreeEPasteboardRead(out IntPtr text,out int textLength,out IntPtr html,out int htmlLength,out IntPtr png,out int pngLength,out IntPtr paths,out int pathsLength);
    [DllImport("ThreeEPhoneNative")] private static extern void ThreeEPasteboardFree(IntPtr memory);
    private static readonly object gate=new();
    private static string DropRoot=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Library","Caches","3E","PhoneClipboard");

    public void Write(IReadOnlyList<ClipPart> parts) {
        byte[] text=null,html=null,png=null;var files=new List<string>();string folder=null;
        foreach(var part in parts) switch(part.Kind) {
            case "text": text=part.Data; break;
            case "html": html=part.Data; break;
            case "image": if(PhoneClipboard.IsPng(part.Data)) png=part.Data; else { folder??=PhoneClipboard.NewDropFolder(DropRoot); files.Add(PhoneClipboard.SaveFile(folder,part.Name,part.Data)); } break;
            case "file": folder??=PhoneClipboard.NewDropFolder(DropRoot); files.Add(PhoneClipboard.SaveFile(folder,part.Name,part.Data)); break;
        }
        var paths=files.Count==0?null:Encoding.UTF8.GetBytes(string.Join("\n",files));
        int written;
        lock(gate) written=ThreeEPasteboardWrite(text,text?.Length??0,html,html?.Length??0,png,png?.Length??0,paths,paths?.Length??0);
        if(written!=1) throw new IOException("macOS did not accept the clipboard contents.");
    }

    public ClipSnapshot Read() {
        IntPtr text,html,png,paths;int textLength,htmlLength,pngLength,pathsLength;
        lock(gate) if(ThreeEPasteboardRead(out text,out textLength,out html,out htmlLength,out png,out pngLength,out paths,out pathsLength)!=1) throw new IOException("macOS clipboard unavailable.");
        try {
            var snap=new ClipSnapshot{Text=Utf8(text,textLength),Html=Utf8(html,htmlLength),Png=Bytes(png,pngLength)};
            var list=Utf8(paths,pathsLength);
            if(list!=null) snap.Files.AddRange(list.Split('\n',StringSplitOptions.RemoveEmptyEntries));
            (snap.Width,snap.Height)=PhoneClipboard.PngSize(snap.Png);
            return snap;
        } finally { foreach(var memory in new[]{text,html,png,paths}) if(memory!=IntPtr.Zero) ThreeEPasteboardFree(memory); }
    }

    private static byte[] Bytes(IntPtr memory,int length) { if(memory==IntPtr.Zero||length<=0)return null;var data=new byte[length];Marshal.Copy(memory,data,0,length);return data; }
    private static string Utf8(IntPtr memory,int length) { var data=Bytes(memory,length);return data==null?null:Encoding.UTF8.GetString(data); }
}
