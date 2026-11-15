"""Tap/hold scheduling, independent of Windows hooks so timing can be tested safely."""
from dataclasses import dataclass
from threading import RLock, Thread
from time import monotonic


@dataclass
class Press:
    started_at: float
    scheduled: bool = False
    started: bool = False


class HoldController:
    def __init__(self, bindings, enqueue, enabled, hold_time=0.18, clock=monotonic):
        self.bindings, self.enqueue, self.enabled = bindings, enqueue, enabled
        self.hold_time, self.clock = hold_time, clock
        self.down = {}
        self.epoch = 0
        self.lock = RLock()

    def press(self, key):
        with self.lock:
            if key not in self.down and self.enabled():
                self.down[key] = Press(self.clock())

    def _held(self, key, press):
        with self.lock:
            return self.down.get(key) is press and self.enabled()

    def poll(self):
        with self.lock:
            if not self.enabled():
                self.cancel()
                return
            for key, press in list(self.down.items()):
                if not press.scheduled and self.clock() - press.started_at >= self.hold_time:
                    press.scheduled = True
                    self.enqueue(lambda k=key, p=press: self._start(k, p))

    def _start(self, key, press):
        if self._held(key, press):
            press.started = True
            start = self.bindings[key][1]
            if start:
                start(lambda: self._held(key, press))

    def release(self, key):
        with self.lock:
            press = self.down.pop(key, None)
            if press is None:
                return
            # Measure physical duration even if the worker has not serviced its timer yet.
            # In particular, a long MB5 press must never fall through to Flash.
            if press.scheduled or self.clock() - press.started_at >= self.hold_time:
                self._finish(key, press)
            else:
                click = self.bindings[key][0]
                epoch = self.epoch
                if click:
                    self.enqueue(lambda: click() if epoch == self.epoch and self.enabled() else None)

    def _finish(self, key, press):
        end = self.bindings[key][2]
        if end:
            # Run at once on its own thread: releasing must never wait behind queued taps.
            Thread(target=lambda: end() if press.started else None, daemon=True).start()

    def cancel(self):
        with self.lock:
            self.epoch += 1
            for key, press in self.down.items():
                self._finish(key, press)
            self.down.clear()
