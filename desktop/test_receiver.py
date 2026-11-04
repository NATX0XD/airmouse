import asyncio, json, socket, unittest
from contextlib import closing
from types import SimpleNamespace

import websockets
import receiver
import receiver_app


class Fake:
    def __init__(self): self.events = []
    def move(self, x, y): self.events.append(("move", x, y))
    def button(self, b, d): self.events.append(("button", b, d))
    def scroll(self, y): self.events.append(("scroll", y))
    def key(self, k): self.events.append(("key", k))
    def center(self, x, y): self.events.append(("center", x, y))


class ReceiverTests(unittest.TestCase):
    def test_app_text_helpers(self):
        self.assertEqual(receiver_app.screen_label({"w": 2560, "h": 1080}), "จอ 2560 x 1080")
        self.assertEqual(receiver_app.connection_label(None), "รอโทรศัพท์เชื่อมต่อ…")
        self.assertEqual(receiver_app.connection_label("192.168.1.4"), "เชื่อมต่อแล้ว: 192.168.1.4")
        self.assertEqual(receiver_app.rate_label(12.4), "12 msg/s")

    def test_messages_bad_input_and_center_math(self):
        out, size = Fake(), lambda: {"w": 1001, "h": 801, "scale": 2}
        self.assertEqual(receiver.handle(out, {"t": "hello"}, size), {"t": "screen", "w": 1001, "h": 801, "scale": 2})
        for msg in ({"t":"move","dx":2,"dy":-3}, {"t":"button","b":"left","down":True}, {"t":"scroll","dy":4}, {"t":"key","k":"right"}, {"t":"center"}): receiver.handle(out, msg, size)
        self.assertEqual(out.events, [("move",2,-3),("button","left",True),("scroll",4),("key","right"),("center",500,400)])
        for bad in (None, [], {}, {"t":"wat"}, {"t":"move"}, "{bad}"):
            try: receiver.handle(out, bad, size)
            except (ValueError, KeyError, TypeError): self.fail(f"bad message raised: {bad!r}")


class EndToEnd(unittest.IsolatedAsyncioTestCase):
    async def test_dry_run_protocol(self):
        with closing(socket.socket()) as s:
            s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]
        task = asyncio.create_task(receiver.run(SimpleNamespace(port=port, dry_run=True, verbose=False)))
        await asyncio.sleep(.1)
        try:
            async with websockets.connect(f"ws://127.0.0.1:{port}") as ws:
                await ws.send(json.dumps({"t":"hello","v":2,"app":"airmouse"}))
                screen = json.loads(await ws.recv())
                self.assertEqual(screen["t"], "screen"); self.assertGreater(screen["w"], 0)
                await ws.send(json.dumps({"t":"center"})); await ws.send(json.dumps({"t":"move","dx":1,"dy":2}))
        finally:
            task.cancel(); await asyncio.gather(task, return_exceptions=True)
