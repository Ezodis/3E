// SPDX-License-Identifier: MIT
using System.Xml.Linq;
namespace ThreeE.PhoneControl;

public static class AbletonIntegration {
    // Install only into existing Ableton user libraries, including relocated ones.
    // The embedded script travels with both platforms and survives app updates.
    public static void Install() {
        var home=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var preferences=OperatingSystem.IsMacOS()?Path.Combine(home,"Library","Preferences","Ableton"):
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Ableton");
        var libraries=new HashSet<string>();
        var standard=Path.Combine(OperatingSystem.IsMacOS()?Path.Combine(home,"Music"):Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"Ableton","User Library");
        if(Directory.Exists(standard))libraries.Add(standard);
        try {
            if(Directory.Exists(preferences))foreach(var version in Directory.EnumerateDirectories(preferences,"Live *"))try {
                var xml=XDocument.Load(Path.Combine(version,"Library.cfg"));
                var project=xml.Descendants("UserLibrary").Descendants("LibraryProject").FirstOrDefault();
                var parent=(string)project?.Element("ProjectPath")?.Attribute("Value");
                var name=(string)project?.Element("ProjectName")?.Attribute("Value");
                if(!string.IsNullOrEmpty(parent)&&!string.IsNullOrEmpty(name)) {
                    var library=Path.Combine(parent,name);if(Directory.Exists(library))libraries.Add(library);
                }
            }catch { /* One old Live version must not block the active library. */ }
        }catch { }
        foreach(var library in libraries)try { InstallTo(library); }catch { /* MIDI remains available if the library is offline/read-only. */ }
    }
    public static void InstallTo(string library) {
        var destination=Path.Combine(library,"Remote Scripts","_3E_Phone_Bar");
        Directory.CreateDirectory(destination);
        foreach(var name in new[]{"__init__.py","phone_bar.py","mapping.py"}) {
            using var resource=typeof(AbletonIntegration).Assembly.GetManifestResourceStream("ThreeE.PhoneControl.Ableton."+name)??throw new InvalidOperationException("Missing Phone Bar script: "+name);
            using var buffer=new MemoryStream();resource.CopyTo(buffer);var content=buffer.ToArray();
            var target=Path.Combine(destination,name);
            if(File.Exists(target)&&File.ReadAllBytes(target).SequenceEqual(content))continue;
            var temporary=target+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {File.WriteAllBytes(temporary,content);File.Move(temporary,target,true);}
            finally {if(File.Exists(temporary))File.Delete(temporary);}
        }
    }
}
