using System.ComponentModel;
using System.Diagnostics;

ProcessStartInfo processInfo = new ProcessStartInfo
{
    UseShellExecute = true,
    FileName = "3£.exe",
    Arguments = "FromElevator"
};
try{
    Process.Start(processInfo);
}catch(Win32Exception ex){
    Debug.WriteLine(ex);
}