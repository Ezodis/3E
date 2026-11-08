using ThreeFingerDragOnWindows.threefingerdrag;

int checks = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); Console.WriteLine("PASS: " + name); checks++; }
bool acceptDown = false, acceptUp = true;
var events = new List<string>();
var drag = new DragButtonState(() => { events.Add("down"); return acceptDown; }, () => { events.Add("up"); return acceptUp; });
Check(!drag.Begin(0, 500) && !drag.Held, "Rejected mouse-down never creates a phantom drag");
acceptDown = true;
Check(drag.Begin(10, 500) && drag.Held, "A gesture retries successfully after input becomes available");
Check(drag.Begin(20, 500) && events.Count == 2, "An active gesture does not press the button twice");
drag.Refresh(400, 500);
Check(!drag.Expire(510) && drag.Held, "An old queued timer cannot release a refreshed gesture");
Check(drag.Expire(900) && !drag.Held && events.Last() == "up", "The current release deadline releases the button");
Check(drag.Begin(1000, 500) && !drag.Expire(1100) && drag.Held, "A previous gesture's timer cannot release a new hold");
acceptUp = false;
Check(!drag.End() && !drag.Held && drag.ReleasePending, "Rejected release is retained for recovery");
int beforeRetry = events.Count;
Check(!drag.Begin(1200, 500) && events.Count == beforeRetry + 1 && events.Last() == "up", "A pending release blocks a new press until it succeeds");
acceptUp = true;
Check(drag.Begin(1300, 500) && events.TakeLast(2).SequenceEqual(new[]{"up","down"}), "Recovery releases the old button before starting a new drag");
Check(drag.Expire(1800) && !drag.Held, "A press without further contacts still expires");
int completedEvents = events.Count;
Check(drag.End() && events.Count == completedEvents, "Ending an already released gesture injects no extra input");
Console.WriteLine($"{checks} drag recovery checks passed.");
