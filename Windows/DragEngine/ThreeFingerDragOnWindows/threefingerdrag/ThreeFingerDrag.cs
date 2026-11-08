using System;
using System.Collections.Generic;
using System.Linq;
using System.Timers;
using ThreeFingerDragEngine.utils;
using ThreeFingerDragOnWindows.settings;
using ThreeFingerDragOnWindows.utils;

namespace ThreeFingerDragOnWindows.threefingerdrag;

public class ThreeFingerDrag{
    public const int RELEASE_FINGERS_THRESHOLD_MS = 40; // Windows Precision Touchpad sends contacts about every 10ms

    private readonly DistanceManager _distanceManager = new();
    private readonly FingerCounter _fingerCounter = new();
    private readonly Timer _dragEndTimer = new();
    private readonly object _gate = new();
    private readonly DragButtonState _button = new(MouseOperations.ThreeFingersDragMouseDown, MouseOperations.ThreeFingersDragMouseUp);

    public ThreeFingerDrag(){
        _dragEndTimer.AutoReset = false;
        _dragEndTimer.Elapsed += OnTimerElapsed;
    }

    private float _averagingX = 0;
    private float _averagingY = 0;
    private int _averagingCount = 0;

    public void OnTouchpadContact(IntPtr currentDevice, TouchpadContact[] oldContacts, TouchpadContact[] contacts, long elapsed){
        lock (_gate) OnTouchpadContactLocked(currentDevice, oldContacts, contacts, elapsed);
    }

    private void OnTouchpadContactLocked(IntPtr currentDevice, TouchpadContact[] oldContacts, TouchpadContact[] contacts, long elapsed){
        DragDiagnostics.Contacts(contacts.Length);
        if (_button.ReleasePending && !_button.End()) return;
        var deviceInfo = TouchpadHelper.GetDeivceInfo(currentDevice);
        bool hasFingersReleased = elapsed > RELEASE_FINGERS_THRESHOLD_MS;
        Logger.Log("TFD: " + string.Join(", ", oldContacts.Select(c => c.ToString())) + " | " +
                   string.Join(", ", contacts.Select(c => c.ToString())) + " | " + elapsed);
        bool areContactsIdsCommons = FingerCounter.AreContactsIdsCommons(oldContacts, contacts);

        (_, Point longestDistDelta, float longestDist2D) =
            _distanceManager.GetLongestDist2D(oldContacts, contacts, hasFingersReleased);
        (int fingersCount, int shortDelayMovingFingersCount, int longDelayMovingFingersCount,
                int originalFingersCount) =
            _fingerCounter.CountMovingFingers(currentDevice, contacts, areContactsIdsCommons, longestDist2D, hasFingersReleased);

        Logger.Log("    fingers: " + fingersCount + ", original: " + originalFingersCount + ", moving: " +
                   shortDelayMovingFingersCount + "/" + longDelayMovingFingersCount + ", dist: " + longestDist2D);

        if(fingersCount >= 3 && areContactsIdsCommons && longDelayMovingFingersCount == 3 &&
           originalFingersCount == 3 && !_button.Held){
            // Start dragging
            Logger.Log("    START DRAG, click down");
            if (_button.Begin(Environment.TickCount64, GetReleaseDelay())) ArmTimer();
        } else if(_button.Held &&
                  (shortDelayMovingFingersCount < 2 || (originalFingersCount != 3 && originalFingersCount >= 2))){
            // Stop dragging
            // Condition over originalFingersCount to catch cases where the drag has continued with only two or four fingers
            Logger.Log("    STOP DRAG, click up");
            StopDrag();
        } else if(fingersCount >= 2 && originalFingersCount == 3 && areContactsIdsCommons && _button.Held){
            // Dragging
            // The Store UI normally creates this per-device entry. The bundled
            // headless build intentionally has no settings UI, so fall back to
            // ThreeFingerDragConfig's upstream defaults for a newly seen device.
            if(App.SettingsData.ThreeFingerDeviceDragCursorConfigs
                .GetValueOrDefault(deviceInfo.deviceId, new SettingsData.ThreeFingerDragConfig())
                .ThreeFingerDragCursorMove){
                if(App.SettingsData.ThreeFingerDragMaxFingerMoveDistance != 0 && longestDist2D > App.SettingsData.ThreeFingerDragMaxFingerMoveDistance){
                    Logger.Log("    DISCARDING MOVE, (x, y) = (" + longestDistDelta.x + ", " + longestDistDelta.y + ")");
                } else if(!longestDistDelta.IsNull()){
                    Point delta = DistanceManager.ApplySpeedAndAcc(currentDevice, longestDistDelta, (int)elapsed);
                    Logger.Log("    MOVING (avg), (x, y) = (" + longestDistDelta.x + ", " + longestDistDelta.y + ")");
                    if(App.SettingsData.ThreeFingerDragCursorAveraging > 1){
                        _averagingX += delta.x;
                        _averagingY += delta.y;
                        _averagingCount++;
                        if(_averagingCount >= App.SettingsData.ThreeFingerDragCursorAveraging){
                            Logger.Log("    MOVING (avg effectively), (x, y) = (" + longestDistDelta.x + ", " + longestDistDelta.y + ")");
                            if (!MouseOperations.ShiftCursorPosition(_averagingX, _averagingY)) { StopDrag(); return; }
                            _averagingX = 0;
                            _averagingY = 0;
                            _averagingCount = 0;
                        }
                    } else{
                        Logger.Log("    MOVING, (x, y) = (" + longestDistDelta.x + ", " + longestDistDelta.y + ")");
                        if (!MouseOperations.ShiftCursorPosition(delta.x, delta.y)) { StopDrag(); return; }
                    }
                }

            }
            _button.Refresh(Environment.TickCount64, GetReleaseDelay());
            ArmTimer();
        }
        Logger.Log("");
    }

    private void OnTimerElapsed(object source, ElapsedEventArgs e){
        lock (_gate) {
            // A callback already queued before Stop/Start must not release a
            // newer drag. The monotonic deadline belongs to the current hold.
            if (!_button.Held) return;
            if (!_button.Expire(Environment.TickCount64)) { ArmTimer(); return; }
            _dragEndTimer.Stop();
            ResetAveraging();
        }
    }

    private void ArmTimer(){
        _dragEndTimer.Stop();
        _dragEndTimer.Interval = Math.Max(1, _button.ReleaseAt - Environment.TickCount64);
        _dragEndTimer.Start();
    }

    private void StopDrag(){
        _dragEndTimer.Stop();
        _button.End();
        ResetAveraging();
    }

    private void ResetAveraging(){
        _averagingX = _averagingY = 0;
        _averagingCount = 0;
    }

    private int GetReleaseDelay(){
        // Delay after which the click is released if no input is detected
        return App.SettingsData.ThreeFingerDragAllowReleaseAndRestart
            ? Math.Max(App.SettingsData.ThreeFingerDragReleaseDelay, RELEASE_FINGERS_THRESHOLD_MS)
            : RELEASE_FINGERS_THRESHOLD_MS;
    }
}
