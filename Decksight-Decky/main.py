# This file is based on code from decksight-brightness-fix by Billy Dalton "Xnopyt", https://github.com/Xnopyt/decksight-brightness-fix
# originally licensed under the BSD 3-Clause License. See THIRD_PARTY_NOTICES.md for the full license text.

import decky, os, struct, ctypes, ctypes.util, asyncio, json, aiohttp
class Plugin:
    async def _main(self):
        self.libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        self.libc.inotify_init1.argtypes = [ctypes.c_int]
        self.libc.inotify_init1.restype = ctypes.c_int
        self.libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self.libc.inotify_add_watch.restype = ctypes.c_int

        self.EVENT_STRUCT_FORMAT = "iIII"
        self.EVENT_SIZE = struct.calcsize(self.EVENT_STRUCT_FORMAT)
        self.IN_MODIFY = 0x00000002
        
        self.fd = False
        self.path = '/sys/class/backlight/amdgpu_bl0/brightness'
        self.max_path = '/sys/class/backlight/amdgpu_bl0/max_brightness'
        self.max_brightness = False
        self.brightness = False
        
        self.loop = asyncio.get_event_loop()
        self.tabsTask = None
        
        self.session = aiohttp.ClientSession()
        self.ws = None
        self.cur_id = 0
        self.enabled = True
        self.monitor_started = False
                
        self.blacklistedTabs = ["SharedJSContext", "Steam Shared Context presented by Valve™", "Steam", "SP", "Steam Big Picture Mode"]
        self.sessions = []
             
    async def _unload(self):
        await self.stop_monitor()
        await self.session.close()

    async def start_monitor(self):
        if not self.enabled or self.monitor_started:
            return
        self.monitor_started = True
        while True:
            try:
                await self.send_brightness()
                break
            except Exception:
                pass
        
        self.tabsTask = self.loop.create_task(self.monitor_tabs())
        
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK)
        if self.fd < 0:
            errno = ctypes.get_errno()
            raise OSError(errno, os.strerror(errno))

        wd = self.libc.inotify_add_watch(self.fd, self.path.encode("utf-8"), self.IN_MODIFY)
        if wd < 0:
            errno = ctypes.get_errno()
            raise OSError(errno, os.strerror(errno))
        
        self.loop.add_reader(self.fd, self.brightness_change)

    async def stop_monitor(self):
        if self.fd:
            self.loop.remove_reader(self.fd)
            os.close(self.fd)
            self.fd = False

        if self.tabsTask:
            self.tabsTask.cancel()
            self.tabsTask = None

        if self.ws:
            for session in self.sessions:
                await self.ws.send_json({
                    "id": self.get_msg_id(),
                    "method": "runtime.Evaluate",
                    "sessionId": session,
                    "params": {
                        "expression": "document.children[0].style.filter = null"
                    }
                })
            await self.ws.close()
            self.ws = None

        self.sessions = []
        self.monitor_started = False
        
    def brightness_change(self):
        try:
            data = os.read(self.fd, 4096)
            offset = 0
            while offset < len(data):
                wd, mask, _, _ = struct.unpack_from(self.EVENT_STRUCT_FORMAT, data, offset)
                offset += self.EVENT_SIZE

                if mask & self.IN_MODIFY:
                    self.loop.create_task(self.send_brightness())
        except BlockingIOError:
            pass
                        
    async def send_brightness(self):
        if not self.max_brightness:
            with open(self.max_path, "r") as file:
                self.max_brightness = int(file.read())
        
        with open(self.path, "r") as file:
            ratio = max(0, min(1, int(file.read()) / self.max_brightness))
            self.brightness = pow(ratio, 0.7)
            
            for session in self.sessions:
                await self.update_tab_brightness(session)
            
            await decky.emit('brightness_change', self.brightness, [])
            
    def get_msg_id(self):
        self.cur_id += 1
        if self.cur_id > 2000000:
            self.cur_id = 1
        return self.cur_id
    
    async def update_tab_brightness(self, session):
        if not self.ws or self.ws.closed:
            return
        await self.ws.send_json({
            "id": self.get_msg_id(),
            "method": "Runtime.evaluate",
            "sessionId": session,
            "params": {
                "expression": "document.children[0].style.filter = 'brightness(" + str(self.brightness) + ")'"
            }
        })
    
    async def monitor_tabs(self):
        r = await self.session.get("http://localhost:8080/json/version")
        data = await r.json()
        
        self.ws = await self.session.ws_connect(data['webSocketDebuggerUrl'])
        await self.ws.send_json({
            "id": self.get_msg_id(),
            "method": "Target.setDiscoverTargets",
            "params": {"discover": True, "filter": [{"type": "page"}]},
        })
        
        pendingSessions = []
        
        async for msg in self.ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            data = json.loads(msg.data)
            
            if "method" in data:
                if data["method"] == "Target.targetCreated":
                    if data['params']['targetInfo']['title'] not in self.blacklistedTabs:
                        msgId = self.get_msg_id()
                        pendingSessions.append(msgId)
                        await self.ws.send_json({
                            "id": msgId,
                            "method": "Target.attachToTarget",
                            "params": {
                                "targetId": data['params']['targetInfo']['targetId'],
                                "flatten": True
                            }
                        })
                elif data['method'] == "Target.detachedFromTarget":
                    self.sessions.remove(data['params']['sessionId'])
                elif data['method'] == "Page.frameNavigated":
                    #In some cases, when a frame navigates we stop getting events for it.
                    #This forces us to detach from all sessions and rediscover and attach them.
                    await self.ws.send_json({
                        "id": self.get_msg_id(),
                        "method": "Target.setDiscoverTargets",
                        "params": {"discover": False},
                    })
                    for session in self.sessions:
                        await self.ws.send_json({
                            "id": self.get_msg_id(),
                            "method": "Target.detachFromTarget",
                            "params": {"sessionId": session},
                        })
                    await self.ws.send_json({
                        "id": self.get_msg_id(),
                        "method": "Target.setDiscoverTargets",
                        "params": {"discover": True, "filter": [{"type": "page"}]},
                    })
                    
            elif "id" in data:
                if data["id"] in pendingSessions:
                    pendingSessions.remove(data['id'])
                    self.sessions.append(data['result']['sessionId'])
                    await self.ws.send_json({
                        "id": self.get_msg_id(),
                        "method": "Page.enable",
                        "sessionId": data['result']['sessionId']
                    })
                    await self.update_tab_brightness(data['result']['sessionId'])

    async def get_enabled(self):
        return self.enabled

    async def set_enabled(self, enabled):
        self.enabled = bool(enabled)
        if self.enabled:
            await self.start_monitor()
        else:
            await self.stop_monitor()
            await decky.emit('brightness_change', 1.0, [])
        return self.enabled
