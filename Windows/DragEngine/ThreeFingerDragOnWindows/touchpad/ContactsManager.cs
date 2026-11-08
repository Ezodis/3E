using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using ThreeFingerDragEngine.utils;
using ThreeFingerDragOnWindows.utils;
using WinRT.Interop;
using WinUICommunity;

namespace ThreeFingerDragOnWindows.touchpad;

public class ContactsManager{
    private readonly HandlerWindow _source;

    private readonly IntPtr _hwnd;
    private IntPtr _oldWndProc;

    public ContactsManager(HandlerWindow source){
        _source = source;

        _hwnd = WindowNative.GetWindowHandle(_source);
        _oldWndProc = Interop.SetWndProc(_hwnd, WindowProcess);
    }

    public void InitializeSource(){
        var touchpadExists = TouchpadHelper.Exists();
        var inputReceiverInstalled = TouchpadHelper.RegisterInput(_hwnd);

        _source.OnTouchpadInitialized(touchpadExists, inputReceiverInstalled);
    }

    // WindowProc Listener
    private IntPtr WindowProcess(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam){
        switch(message){
            case TouchpadHelper.WM_INPUT:
                var (currentDevice, contacts, count) = TouchpadHelper.ParseInput(lParam);
                ReceiveTouchpadContacts(currentDevice, contacts, count);
                break;
            case TouchpadHelper.WM_INPUT_DEVICE_CHANGE:
                _source.OnTouchpadInitialized(TouchpadHelper.Exists(lParam), true);
                break;
        }

        return Interop.CallWindowProc(_oldWndProc, hwnd, message, wParam, lParam);
    }


    // Contacts managements
    private List<TouchpadContact> _lastContacts = new();
    private uint _targetContactCount;
    private IntPtr _lastDevice;

    internal void ReceiveTouchpadContacts(IntPtr currentDevice, List<TouchpadContact> contacts, uint count){
        if(currentDevice!=_lastDevice){_lastContacts.Clear();_targetContactCount=0;_lastDevice=currentDevice;}
        if(contacts == null || contacts.Count == 0){
            Logger.Log("Receiving empty contacts with cC=" + count);
            if(contacts!=null && count==0) { _lastContacts.Clear();_targetContactCount=0;_source.OnTouchpadContact(currentDevice,contacts); }
            return;
        }

        if(count==0 && _lastContacts.Count==0 && contacts.All(c=>!c.IsActive)) {
            _targetContactCount=0;_source.OnTouchpadContact(currentDevice,new List<TouchpadContact>());return;
        }

        // Regular contact list
        if(count == contacts.Count){
            Logger.Log("+ Receiving regular contact list: " +  string.Join(", ", contacts.Select(c => c.ToString())));
            _source.OnTouchpadContact(currentDevice, contacts);
            _lastContacts.Clear();
            return;
        }

        // Partial contact list (always sent after an incomplete contact list)
        if(count == 0){
            Logger.Log("Receiving partial contact list: " + string.Join(", ", contacts.Select(c => c.ToString())));
            _lastContacts.AddRange(contacts);
            _lastContacts = RemoveDuplicates(_lastContacts);

            if(_targetContactCount == 0){
                Logger.Log("[WARNING] Target contact count not received yet through an invalid contact list.");
                return;
            }

            if(_lastContacts.Count > _targetContactCount){
                Logger.Log("[WARNING] LastContact list has more contacts than expected: " + string.Join(", ", _lastContacts.Select(c => c.ToString())));
                _lastContacts = _lastContacts.Take((int) _targetContactCount).ToList();
                _source.OnTouchpadContact(currentDevice, _lastContacts);
                _lastContacts.Clear();

            }
            if(_lastContacts.Count == _targetContactCount){
                Logger.Log("+ LastContact list has correct length: " + string.Join(", ", _lastContacts.Select(c => c.ToString())));
                _source.OnTouchpadContact(currentDevice, _lastContacts);
                _lastContacts.Clear();
            }
            return;
        }

        // Never invent fingers to complete a partial frame: that could fire
        // a copy/paste or phantom drag. Wait for the next complete frame.
        if(_lastContacts.Count != 0){
            Logger.Log("Discarding incomplete touchpad frame.");
            _lastContacts.Clear();
        }

        // Regular contact list with more contacts than expected (unlikely to happen)
        if(count <= contacts.Count){
            Logger.Log("[WARNING] Received contact list with more contacts than expected: " + string.Join(", ", contacts.Select(c => c.ToString())));
            contacts = contacts.Take((int) count).ToList();
            Logger.Log("+ Contact list has been clamped: " + string.Join(", ", contacts.Select(c => c.ToString())));
            _source.OnTouchpadContact(currentDevice, contacts);
            _lastContacts.Clear();
            return;
        }

        // Here, 0 < contacts.Length < count and lastContacts is empty: incomplete contact list
        _targetContactCount = count;
        _lastContacts = contacts;
        Logger.Log("Receiving incomplete contact count, waiting for partial contacts: " + string.Join(", ", contacts.Select(c => c.ToString())));
    }

    private List<TouchpadContact> RemoveDuplicates(List<TouchpadContact> contacts){
        var uniqueContacts = new List<TouchpadContact>();
        foreach(var contact in contacts){
            if(!uniqueContacts.Any(c => c.ContactId == contact.ContactId)){
                uniqueContacts.Add(contact);
            }
        }
        if(uniqueContacts.Count != contacts.Count){
            Logger.Log("[WARNING] Duplicate contacts ID in list. Removing duplicates: " + string.Join(", ", uniqueContacts.Select(c => c.ToString())));
        }
        return uniqueContacts;
    }
}
