// SPDX-License-Identifier: MIT
using System.Text.Json;
namespace ThreeE.PhoneControl;
// A bounded vocabulary, not executable commands or arbitrary MIDI bytes.
public sealed record PhoneDJCommand(string op,int control=0,int id=0,double x=0,int page=0,string target=null) {
    public static PhoneDJCommand Parse(JsonElement json) {
        string op=json.GetProperty("op").GetString();
        if(op is not ("open" or "state" or "close" or "page" or "target" or "begin" or "move" or "end" or "abort" or "cancel"))throw new InvalidDataException("Invalid DJ action");
        int Integer(string name,int max){if(!json.TryGetProperty(name,out var p))return 0;if(!p.TryGetInt32(out int n)||n<0||n>max)throw new InvalidDataException("Invalid DJ value");return n;}
        if(op is "begin" or "move" or "end" or "abort") {if(!json.TryGetProperty("control",out _)||!json.TryGetProperty("id",out _)||op=="move"&&!json.TryGetProperty("x",out _))throw new InvalidDataException("Missing DJ contact");}
        int control=Integer("control",28),id=Integer("id",1000000),page=Integer("page",1);
        double x=json.TryGetProperty("x",out var value)?value.GetDouble():0;
        if(!double.IsFinite(x)||Math.Abs(x)>10000)throw new InvalidDataException("Invalid DJ travel");
        string target=json.TryGetProperty("target",out var t)?t.GetString():null;
        if(op=="target"&&target is not ("live" or "rekordbox"))throw new InvalidDataException("Invalid DJ target");
        return new(op,control,id,x,page,target);
    }
}
