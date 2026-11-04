"""Native macOS window for the AirMouse receiver.

The WebSocket protocol and input handling stay in :mod:`receiver`; this file
only owns the AppKit window and the lifecycle of the background server.
"""

from __future__ import annotations

import argparse
import asyncio
import ctypes
import json
import logging
import subprocess
import threading
import time
from dataclasses import dataclass, field
from typing import Callable

from websockets.asyncio.server import serve

from receiver import DryOutput, RealOutput, handle, local_ips, screen_info

LOG = logging.getLogger("airmouse.app")


def screen_label(size: dict) -> str:
    return f"จอ {size.get('w', 0)} x {size.get('h', 0)}"


def connection_label(peer: str | None) -> str:
    return f"เชื่อมต่อแล้ว: {peer}" if peer else "รอโทรศัพท์เชื่อมต่อ…"


def rate_label(rate: float) -> str:
    return f"{rate:.0f} msg/s" if rate else "0 msg/s"


@dataclass
class ServerState:
    lock: threading.Lock = field(default_factory=threading.Lock)
    peer: str | None = None
    message_rate: float = 0.0
    error: str | None = None
    started: threading.Event = field(default_factory=threading.Event)
    stop: threading.Event = field(default_factory=threading.Event)
    hello: threading.Event = field(default_factory=threading.Event)


async def _serve(state: ServerState, port: int, dry_run: bool, stop_on_hello: bool = False) -> None:
    output = DryOutput() if dry_run else RealOutput()

    async def on_phone(ws):
        peer = ws.remote_address[0] if ws.remote_address else "?"
        with state.lock:
            state.peer = peer
        count, since = 0, time.monotonic()
        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                    response = handle(output, msg, screen_info)
                    if response:
                        await ws.send(json.dumps(response, separators=(",", ":")))
                    if msg.get("t") == "hello":
                        state.hello.set()
                except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                    LOG.debug("invalid client message", exc_info=True)
                count += 1
                now = time.monotonic()
                if now - since >= 1:
                    with state.lock:
                        state.message_rate = count / (now - since)
                    count, since = 0, now
                if stop_on_hello and state.hello.is_set():
                    break
        finally:
            with state.lock:
                if state.peer == peer:
                    state.peer = None

    try:
        async with serve(on_phone, "0.0.0.0", port):
            state.started.set()
            if stop_on_hello:
                await asyncio.to_thread(state.hello.wait, 20)
            else:
                await asyncio.to_thread(state.stop.wait)
    except OSError as exc:
        with state.lock:
            state.error = f"เปิดพอร์ต {port} ไม่ได้: พอร์ตอาจถูกใช้งานอยู่"
        state.started.set()
        LOG.debug("server failed", exc_info=exc)


def start_server(state: ServerState, port: int, dry_run: bool, stop_on_hello: bool = False) -> threading.Thread:
    thread = threading.Thread(
        target=lambda: asyncio.run(_serve(state, port, dry_run, stop_on_hello)),
        name="airmouse-websocket",
        daemon=True,
    )
    thread.start()
    return thread


def run_selftest(port: int) -> int:
    state = ServerState()
    thread = start_server(state, port, dry_run=True, stop_on_hello=True)
    state.started.wait(3)
    thread.join(22)
    if state.error:
        print(state.error)
        return 2
    if not state.hello.is_set():
        print("selftest timed out waiting for hello")
        return 1
    print("selftest OK: hello handled in dry-run mode")
    return 0


def accessibility_trusted() -> bool:
    try:
        framework = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        framework.AXIsProcessTrusted.restype = ctypes.c_bool
        return bool(framework.AXIsProcessTrusted())
    except (AttributeError, OSError):
        return False


def request_accessibility() -> None:
    # The URL is reliable across recent macOS releases; the app itself also
    # rechecks the process trust bit, so the banner changes without relaunch.
    try:
        subprocess.Popen(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
    except OSError:
        LOG.debug("could not open Accessibility settings", exc_info=True)


def _label(text: str, frame, size: float = 14):
    from AppKit import NSTextField, NSFont

    item = NSTextField.alloc().initWithFrame_(frame)
    item.setStringValue_(text)
    item.setFont_(NSFont.systemFontOfSize_(size))
    item.setBezeled_(False)
    item.setDrawsBackground_(False)
    item.setEditable_(False)
    item.setSelectable_(False)
    return item


class ReceiverWindow:
    def __init__(self, port: int, dry_run: bool):
        import objc
        from AppKit import (
            NSApplication, NSBackingStoreBuffered, NSButton, NSColor, NSFont,
            NSMakeRect, NSRunningApplication, NSStackView, NSTextField, NSView,
            NSWindow, NSWindowStyleMaskClosable, NSWindowStyleMaskMiniaturizable,
            NSWindowStyleMaskTitled, NSWindowStyleMaskResizable,
            NSApplicationActivateIgnoringOtherApps,
        )

        self._objc = objc
        self.port = port
        self.dry_run = dry_run
        self.state = ServerState()
        self.thread: threading.Thread | None = None
        self._trusted = False
        self._last_trust_check = 0.0
        self._ips = local_ips()
        self.app = NSApplication.sharedApplication()
        self.app.setActivationPolicy_(0)  # regular application
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 420, 520),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered, False,
        )
        self.window.setTitle_("AirMouse Receiver")
        self.window.setMinSize_(NSMakeRect(0, 0, 420, 500).size)
        self.window.setDelegate_(self)
        self._build_view(NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 420, 520)), NSMakeRect, NSButton, NSColor, NSFont, NSTextField)
        self.window.center()
        self.window.makeKeyAndOrderFront_(None)
        NSRunningApplication.currentApplication().activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
        self.thread = start_server(self.state, self.port, self.dry_run)
        from AppKit import NSTimer
        self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.5, self, "poll:", None, True
        )

    def _build_view(self, view, NSMakeRect, NSButton, NSColor, NSFont, NSTextField):
        from AppKit import NSBox, NSPasteboard

        view.setWantsLayer_(True)
        view.layer().setBackgroundColor_(NSColor.colorWithCalibratedWhite_alpha_(0.97, 1).CGColor())
        self.title = _label("AirMouse Receiver", NSMakeRect(28, 456, 364, 34), 26)
        self.title.setFont_(NSFont.boldSystemFontOfSize_(26))
        view.addSubview_(self.title)
        view.addSubview_(_label("ใส่ IP นี้ในแอปบนโทรศัพท์", NSMakeRect(30, 420, 300, 22), 14))
        self.ip = _label(f"{self._ips[0]}:{self.port}", NSMakeRect(28, 365, 280, 50), 30)
        self.ip.setFont_(NSFont.boldSystemFontOfSize_(30))
        view.addSubview_(self.ip)
        copy = NSButton.alloc().initWithFrame_(NSMakeRect(304, 378, 88, 34))
        copy.setTitle_("คัดลอก")
        copy.setBezelStyle_(1)
        copy.setTarget_(self); copy.setAction_("copyIP:")
        view.addSubview_(copy)
        self.other = _label("  อื่น ๆ: " + ", ".join(self._ips[1:]) if len(self._ips) > 1 else "", NSMakeRect(30, 348, 360, 18), 11)
        view.addSubview_(self.other)

        self.dot = _label("●", NSMakeRect(30, 298, 20, 22), 16)
        self.status = _label(connection_label(None), NSMakeRect(53, 298, 330, 22), 15)
        view.addSubview_(self.dot); view.addSubview_(self.status)
        self.rate = _label("0 msg/s", NSMakeRect(30, 278, 180, 18), 11)
        view.addSubview_(self.rate)
        self.screen = _label(screen_label(screen_info()), NSMakeRect(30, 242, 360, 24), 14)
        view.addSubview_(self.screen)

        self.access = _label("ยังไม่ได้อนุญาต Accessibility — เคอร์เซอร์จะไม่ขยับ", NSMakeRect(28, 194, 364, 34), 12)
        self.access.setTextColor_(NSColor.systemRedColor())
        view.addSubview_(self.access)
        access_button = NSButton.alloc().initWithFrame_(NSMakeRect(28, 155, 150, 30))
        access_button.setTitle_("เปิดการตั้งค่า")
        access_button.setBezelStyle_(1)
        access_button.setTarget_(self); access_button.setAction_("openAccessibility:")
        view.addSubview_(access_button)

        view.addSubview_(_label("Port", NSMakeRect(30, 108, 50, 24), 13))
        self.port_field = NSTextField.alloc().initWithFrame_(NSMakeRect(78, 104, 76, 28))
        self.port_field.setStringValue_(str(self.port)); view.addSubview_(self.port_field)
        restart = NSButton.alloc().initWithFrame_(NSMakeRect(164, 104, 100, 28))
        restart.setTitle_("เริ่มใหม่"); restart.setBezelStyle_(1)
        restart.setTarget_(self); restart.setAction_("restartServer:"); view.addSubview_(restart)
        self.error = _label("", NSMakeRect(30, 60, 360, 34), 12)
        self.error.setTextColor_(NSColor.systemRedColor()); view.addSubview_(self.error)
        self.view = view
        self.window.setContentView_(view)

    def copyIP_(self, _):
        from AppKit import NSPasteboard
        board = NSPasteboard.generalPasteboard(); board.clearContents(); board.setString_forType_(self.ip.stringValue(), "public.utf8-plain-text")

    def openAccessibility_(self, _):
        request_accessibility()

    def restartServer_(self, _):
        try:
            port = int(self.port_field.stringValue())
            if not 1 <= port <= 65535: raise ValueError
        except ValueError:
            self.error.setStringValue_("ใส่ port เป็นตัวเลข 1–65535")
            return
        self.state.stop.set()
        self.state = ServerState()
        self.port = port
        self.ip.setStringValue_(f"{self._ips[0]}:{port}")
        self.thread = start_server(self.state, port, self.dry_run)

    def poll_(self, _):
        with self.state.lock:
            peer, rate, error = self.state.peer, self.state.message_rate, self.state.error
        self.status.setStringValue_(connection_label(peer))
        self.rate.setStringValue_(rate_label(rate))
        self.dot.setTextColor_(self._color("green" if peer else "gray"))
        if error: self.error.setStringValue_(error)
        now = time.monotonic()
        if now - self._last_trust_check >= 2:
            self._last_trust_check = now
            self._trusted = accessibility_trusted()
            self.access.setStringValue_("Accessibility พร้อมใช้งาน" if self._trusted else "ยังไม่ได้อนุญาต Accessibility — เคอร์เซอร์จะไม่ขยับ")
            self.access.setTextColor_(self._color("green" if self._trusted else "red"))

    @staticmethod
    def _color(name):
        from AppKit import NSColor
        return {"green": NSColor.systemGreenColor(), "red": NSColor.systemRedColor(), "gray": NSColor.secondaryLabelColor()}[name]

    def windowShouldClose_(self, _):
        self.state.stop.set()
        return True

    def applicationShouldTerminateAfterLastWindowClosed_(self, _):
        return True


def run_gui(port: int, dry_run: bool) -> int:
    from AppKit import NSApplication
    app = NSApplication.sharedApplication()
    ReceiverWindow(port, dry_run)
    app.run()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--dry-run", action="store_true", help="do not move the mouse")
    parser.add_argument("--selftest", action="store_true", help="headless protocol check")
    args = parser.parse_args()
    if args.selftest:
        return run_selftest(args.port)
    return run_gui(args.port, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
