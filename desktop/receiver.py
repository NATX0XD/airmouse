"""AirMouse Wi-Fi receiver (protocol v2)."""

import argparse
import asyncio
import json
import socket
import time
import platform
import logging
from typing import Callable

from websockets.asyncio.server import serve

LOG = logging.getLogger("airmouse")


def _prepare_windows_dpi() -> None:
    if platform.system() == "Windows":
        try:
            import ctypes
            try:
                ctypes.windll.shcore.SetProcessDpiAwareness(2)
            except Exception:
                ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            LOG.debug("Could not set Windows DPI awareness", exc_info=True)


def screen_info() -> dict:
    _prepare_windows_dpi()
    system = platform.system()
    if system == "Darwin":
        try:
            import Quartz
            display = Quartz.CGMainDisplayID()
            rect = Quartz.CGDisplayBounds(display)
            w, h = int(rect.size.width), int(rect.size.height)
            px = Quartz.CGDisplayPixelsWide(display)
            return {"w": w, "h": h, "scale": round(px / w, 2) if w else 1}
        except Exception:
            LOG.debug("Quartz screen query unavailable", exc_info=True)
    if system == "Windows":
        import ctypes
        return {"w": ctypes.windll.user32.GetSystemMetrics(0), "h": ctypes.windll.user32.GetSystemMetrics(1), "scale": 1}
    try:
        import tkinter
        root = tkinter.Tk(); root.withdraw()
        result = {"w": root.winfo_screenwidth(), "h": root.winfo_screenheight(), "scale": 1}
        root.destroy(); return result
    except Exception:
        return {"w": 1920, "h": 1080, "scale": 1}


def local_ips() -> list[str]:
    """Non-loopback IPv4s; the one the default route uses comes first."""
    routed = []
    for target in (("8.8.8.8", 80), ("1.1.1.1", 80)):
        # No packet is sent: connecting a UDP socket only picks the outgoing interface.
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(target)
            ip = s.getsockname()[0]
            if not ip.startswith("127.") and ip not in routed:
                routed.append(ip)
        except OSError:
            pass
        finally:
            s.close()
    others = set()
    try:
        for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = item[4][0]
            if not ip.startswith("127.") and ip not in routed:
                others.add(ip)
    except OSError:
        pass
    return routed + sorted(others) or ["127.0.0.1"]


class RealOutput:
    def __init__(self):
        from pynput.keyboard import Controller as Keyboard, Key
        from pynput.mouse import Button, Controller as Mouse

        self.mouse = Mouse()
        self.keyboard = Keyboard()
        self.buttons = {"left": Button.left, "right": Button.right}
        self.keys = {"left": Key.left, "right": Key.right}

    def move(self, dx, dy):
        self.mouse.move(dx, dy)

    def button(self, b, down):
        (self.mouse.press if down else self.mouse.release)(self.buttons[b])

    def scroll(self, dy):
        # Phone sends positive = scroll down; pynput uses positive = up.
        self.mouse.scroll(0, -dy)

    def key(self, k):
        self.keyboard.tap(self.keys[k])

    def center(self, x, y):
        self.mouse.position = (x, y)


class DryOutput:
    def move(self, dx, dy):
        print(f"move {dx:+d} {dy:+d}")

    def button(self, b, down):
        print(f"button {b} {'down' if down else 'up'}")

    def scroll(self, dy):
        print(f"scroll {dy:+d}")

    def key(self, k):
        print(f"key {k}")

    def center(self, x, y):
        print(f"center -> ({x}, {y})")


def handle(out, msg: dict, get_screen: Callable[[], dict] = screen_info) -> dict | None:
    if not isinstance(msg, dict): return None
    t = msg.get("t")
    if t == "hello":
        return {"t": "screen", **get_screen()}
    if t == "move" and "dx" in msg and "dy" in msg:
        out.move(int(msg["dx"]), int(msg["dy"]))
    elif t == "button" and msg.get("b") in ("left", "right") and "down" in msg:
        out.button(msg["b"], bool(msg["down"]))
    elif t == "scroll" and "dy" in msg:
        out.scroll(int(msg["dy"]))
    elif t == "key" and msg.get("k") in ("left", "right"):
        out.key(msg["k"])
    elif t == "center":
        size = get_screen(); out.center(size["w"] // 2, size["h"] // 2)
    return None


async def run(args) -> None:
    out = DryOutput() if args.dry_run else RealOutput()
    warned = set()

    async def on_phone(ws):
        peer = ws.remote_address[0] if ws.remote_address else "?"
        print(f"phone connected: {peer}")
        count, since, last_screen = 0, time.monotonic(), None
        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                    response = handle(out, msg)
                    if response: await ws.send(json.dumps(response, separators=(",", ":")))
                    if msg.get("t") not in {"hello", "move", "button", "scroll", "key", "center"} and args.verbose and msg.get("t") not in warned:
                        LOG.info("ignored unknown message type: %r", msg.get("t")); warned.add(msg.get("t"))
                    if msg.get("t") == "hello": last_screen = response
                except (ValueError, KeyError, TypeError, json.JSONDecodeError) as e:
                    if args.verbose: LOG.info("bad message %r: %s", raw, e)
                count += 1
                now = time.monotonic()
                if now - since >= 5:
                    if args.verbose: print(f"  {count / (now - since):.0f} msg/s")
                    count, since = 0, now
                if last_screen is not None and now - getattr(ws, "_airmouse_poll", 0) >= 3:
                    ws._airmouse_poll = now
                    current = {"t": "screen", **screen_info()}
                    if current != last_screen:
                        await ws.send(json.dumps(current, separators=(",", ":"))); last_screen = current
        finally:
            print(f"phone disconnected: {peer}")

    async with serve(on_phone, "0.0.0.0", args.port):
        ips = local_ips(); print("AirMouse Receiver พร้อมใช้งาน / ready")
        print("ใส่ IP เหล่านี้ในแอป / Type one of these IPs in the app:")
        for i, ip in enumerate(ips): print(f"  {ip}{'  <- น่าจะเป็น Wi-Fi / likely Wi-Fi' if i == 0 else ''}")
        print(f"Port: {args.port}")
        print("macOS: อนุญาต Accessibility ให้ Terminal ที่ใช้รันโปรแกรม")
        print("      System Settings > Privacy & Security > Accessibility")
        if args.dry_run:
            print("(dry run: mouse will not move)")
        await asyncio.get_running_loop().create_future()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO if args.verbose else logging.WARNING, format="%(message)s")
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt: pass


if __name__ == "__main__": main()
