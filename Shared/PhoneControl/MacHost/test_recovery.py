"""Exercise the real Mac host command loop with a null input sink, never OS input."""
import json
import platform
from pathlib import Path
import select
import subprocess
import sys
import urllib.request

app = Path(sys.argv[1])
arch = "arm64" if platform.machine() == "arm64" else "x64"
host = app / "Contents/Resources/PhoneControl" / arch / "ThreeE.PhoneHost"

def launch():
    return subprocess.Popen([str(host), "--recovery-self-test"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def link(process):
    if not select.select([process.stdout], [], [], 10)[0]:
        raise AssertionError("Host did not announce its link")
    value = json.loads(process.stdout.readline())
    assert value.get("url"), value.get("error")
    return value["url"]

def command(process, value):
    process.stdin.write(value + "\n")
    process.stdin.flush()

def alive(url):
    with urllib.request.urlopen(url.split("#")[0] + "alive", timeout=3) as response:
        assert response.status in (200, 204)

subprocess.run([str(host), "--bonjour-self-test"], check=True, timeout=30)

original = None
for attempt in range(2):
    process = launch()
    try:
        url = link(process)
        if original is None: original = url
        assert url == original, "A host process restart changed the saved link"
        alive(url)
        for _ in range(3):
            command(process, "SLEEP")
            command(process, "WAKE")
            assert link(process) == original, "Sleep/wake changed the saved link"
            alive(original)
        command(process, "STOP")
        assert process.wait(timeout=5) == 0
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stdin.close()
        process.stdout.close()
        process.stderr.close()
print("PASS: repeated Mac host sleep/wake and process restarts serve the same saved link; no native input posted.")
