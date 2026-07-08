#!/usr/bin/env python3
"""np64-bridge: SC64 USB <-> np64-relay bridge daemon (task #46).

Presents NetPak64 device semantics to a ROM running on a real N64 with a
SummerCart64, over the cart's USB link. The N64 side batches netpak messages
into UNFLoader-style USB writes (datatype NETPAK); this daemon terminates the
command mailbox (sessions, identity, peers, ping, time), owns the UDP
connection to np64-relay, and shuttles ch0/ch1 packets both ways.

Modes:
  --selftest          serial link probe (IDENTIFIER/VERSION) + relay HELLO
  --run ROOM NAME     bridge a console into ROOM as NAME (default mode)

Serial protocol: SC64 CMD/CMP/ERR/PKT framing (docs/03_usb_interface.md).
Relay protocol:  netpak-spec.md §8 frames (16-byte header, big-endian).
"""
import argparse
import os
import select
import socket
import struct
import sys
import termios
import time

SERIAL_DEV = "/dev/ttyUSB0"
RELAY_ADDR = ("127.0.0.1", 6465)

# ---------- SC64 serial link ------------------------------------------------

class SC64:
    def __init__(self, dev=SERIAL_DEV):
        self.fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
        attrs = termios.tcgetattr(self.fd)
        # raw mode
        attrs[0] = 0            # iflag
        attrs[1] = 0            # oflag
        attrs[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0            # lflag
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 1
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        self.buf = b""
        self._reset_comms()

    def _reset_comms(self):
        """SC64 protocol reset (docs §resetting-communication): raise DTR,
        wait for DSR high, purge, drop DTR, wait for DSR low."""
        import fcntl
        DTR = termios.TIOCM_DTR
        def dsr():
            b = struct.pack("I", 0)
            r = fcntl.ioctl(self.fd, termios.TIOCMGET, b)
            return bool(struct.unpack("I", r)[0] & termios.TIOCM_DSR)
        fcntl.ioctl(self.fd, termios.TIOCMBIS, struct.pack("I", DTR))
        t0 = time.time()
        while not dsr() and time.time() - t0 < 2.0:
            time.sleep(0.01)
        termios.tcflush(self.fd, termios.TCIOFLUSH)
        self.buf = b""
        fcntl.ioctl(self.fd, termios.TIOCMBIC, struct.pack("I", DTR))
        t0 = time.time()
        while dsr() and time.time() - t0 < 2.0:
            time.sleep(0.01)

    def cmd(self, cid, arg0=0, arg1=0, data=b"", timeout=2.0):
        """Send CMD, collect until the matching CMP/ERR arrives.
        Returns (ok, response_data, pkts) where pkts are async PKTs seen."""
        pkt = b"CMD" + cid + struct.pack(">II", arg0, arg1) + data
        os.write(self.fd, pkt)
        pkts = []
        t0 = time.time()
        while time.time() - t0 < timeout:
            frame = self._read_frame(timeout - (time.time() - t0))
            if frame is None:
                continue
            magic, fid, payload = frame
            if magic == b"PKT":
                pkts.append((fid, payload))
                continue
            if fid == cid:
                return (magic == b"CMP", payload, pkts)
        return (False, b"", pkts)

    def poll_pkts(self, timeout=0.0):
        """Drain any pending async PKT frames."""
        pkts = []
        while True:
            frame = self._read_frame(timeout)
            if frame is None:
                break
            magic, fid, payload = frame
            if magic == b"PKT":
                pkts.append((fid, payload))
            timeout = 0.0
        return pkts

    def _fill(self, need, deadline):
        while len(self.buf) < need:
            # Clamp to a zero-timeout select rather than bailing when the
            # deadline has passed: timeout=0 polls must still consume data
            # already buffered by the OS (the v45 "bridge went deaf" bug —
            # poll_pkts(0.0) returned before ever reading the console's HELLO).
            wait = deadline - time.time()
            if wait < 0:
                wait = 0.0
            r, _, _ = select.select([self.fd], [], [], wait)
            if not r:
                return False
            chunk = os.read(self.fd, 4096)
            if not chunk:
                return False
            self.buf += chunk
        return True

    def _read_frame(self, timeout):
        deadline = time.time() + max(timeout, 0.0)
        if not self._fill(8, deadline):
            return None
        # resync to a known magic if the stream is misaligned
        while self.buf[:3] not in (b"CMP", b"ERR", b"PKT"):
            self.buf = self.buf[1:]
            if not self._fill(8, deadline):
                return None
        magic = self.buf[:3]
        fid = self.buf[3:4]
        (length,) = struct.unpack(">I", self.buf[4:8])
        if length > 8 * 1024 * 1024:
            self.buf = self.buf[1:]  # implausible; resync
            return None
        if not self._fill(8 + length, deadline):
            return None
        payload = self.buf[8 : 8 + length]
        self.buf = self.buf[8 + length :]
        return (magic, fid, payload)

    def usb_write(self, datatype, data):
        """PC -> N64: SC64 USB_WRITE command. Fire-and-forget: the SC64
        sends NO CMP for 'U' (docs §supported-commands); if the N64 doesn't
        usb_read within 1 s a 'G' DATA_FLUSHED PKT arrives instead."""
        pkt = b"CMDU" + struct.pack(">II", datatype, len(data)) + data
        os.write(self.fd, pkt)

# ---------- Relay client ----------------------------------------------------

FT_HELLO, FT_WELCOME, FT_CREATE, FT_JOIN, FT_JOINED = 0x00, 0x01, 0x02, 0x03, 0x04
FT_PEER_JOIN, FT_PEER_LEAVE, FT_DATA, FT_PING, FT_PONG = 0x05, 0x06, 0x07, 0x08, 0x09
FT_TIME, FT_LEAVE, FT_KEEPALIVE, FT_ERROR, FT_SETNAME = 0x0A, 0x0B, 0x0D, 0x0E, 0x0F

class Relay:
    def __init__(self, addr=RELAY_ADDR):
        self.addr = addr
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setblocking(False)
        self.token = 0
        self.node_id = None
        self.room = None
        self.peers = {}  # id -> name

    def send(self, ftype, payload=b"", channel=0, src=0, dst=0xFF, seq=0):
        hdr = struct.pack(
            ">BBBBIHHBBH", 1, ftype, 0, channel, self.token, seq, 0, src, dst, len(payload)
        )
        self.sock.sendto(hdr + payload, self.addr)

    def recv_raw(self):
        """Drain pending datagrams, undecoded."""
        bufs = []
        while True:
            try:
                buf, _ = self.sock.recvfrom(2048)
            except BlockingIOError:
                break
            bufs.append(buf)
        return bufs

    def recv(self):
        frames = []
        while True:
            try:
                buf, _ = self.sock.recvfrom(2048)
            except BlockingIOError:
                break
            if len(buf) < 16:
                continue
            ver, ftype, flags, ch, token, seq, ack, src, dst, ln = struct.unpack(
                ">BBBBIHHBBH", buf[:16]
            )
            frames.append((ftype, ch, src, dst, buf[16 : 16 + ln]))
        return frames

    def wait_for(self, ftype, timeout=2.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            for f in self.recv():
                if f[0] == ftype:
                    return f
            time.sleep(0.01)
        return None

    def hello(self):
        self.send(FT_HELLO)
        f = self.wait_for(FT_WELCOME)
        if f is None:
            return False
        # token rides in the WELCOME header; reread it from raw recv is
        # awkward here, so re-request: relay pins token by addr, and puts it
        # in the WELCOME header token field. Simplest: parse payload roster.
        # WELCOME payload: [node_id, code6, count, {id, name16} x count]
        return True

def relay_hello_with_token(addr):
    """HELLO exchange returning (token, node_id). Standalone helper so the
    token (header field) can be captured from the raw datagram."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(2.0)
    payload = b"bridge-selftest".ljust(16, b"\x00")[:16] + b"\x00" * 6  # no-room connect
    hdr = struct.pack(">BBBBIHHBBH", 1, FT_HELLO, 0, 0, 0, 0, 0, 0, 0xFF, len(payload))
    s.sendto(hdr + payload, addr)
    buf, _ = s.recvfrom(2048)
    ver, ftype, flags, ch, token, seq, ack, src, dst, ln = struct.unpack(">BBBBIHHBBH", buf[:16])
    payload = buf[16 : 16 + ln]
    node_id = payload[0] if payload else None
    s.close()
    return token, node_id, ftype

# ---------- Bridge run mode ---------------------------------------------------
#
# Terminates the NetPak64 device FSM for a real console: the ROM's register
# shadow (src/netpak_sc64.c) ships 'H'/'C'/'T' frames over USB; this side owns
# the relay UDP session and answers 'W'/'R'/'X'/'S'. Command semantics mirror
# ares' np64::DeviceCore (thirdparty/netpak-core/src/device.cpp) exactly:
#   SESSION_CREATE/JOIN -> relay CREATE/JOIN, complete on JOINED
#                          (RES0=node_id, CMD_DATA[0..7]=code6+NUL)
#   SESSION_LEAVE       -> relay LEAVE, complete on LEAVE ack (ERR 3 if idle)
#   SET_IDENTITY        -> complete locally, SETNAME to relay async
#   LIST_PEERS          -> local peer table (24 B entries: id,rtt=0,name16)
#   PING                -> RES0 = relay RTT us (periodic PING/PONG sampling)
#   GET_TIME            -> relay TIME, RES0/RES1 = hi/lo of relay us
#
# USB frame format (datatype 0x40): {u8 op; u8 a; u16 len(BE); payload}.

NPU_DATATYPE = 0x40

OP_NOP, OP_SET_IDENTITY, OP_CREATE, OP_JOIN, OP_LEAVE = 0, 1, 2, 3, 4
OP_LIST_PEERS, OP_PING, OP_GET_TIME = 5, 6, 7

CMD_OK, CMD_ERR = 0x02, 0x03
ERR_INVAL, ERR_NOTJOINED, ERR_TIMEOUT, ERR_RELAY = 1, 3, 6, 8

STATUS_LINK_UP, STATUS_SESSION = 1 << 0, 1 << 1

def npu_frame(op, a, payload=b""):
    return struct.pack(">BBH", op, a, len(payload)) + payload

class Bridge:
    def __init__(self, sc, relay_addr, name, room):
        self.sc = sc
        self.relay = Relay(relay_addr)
        self.name = name.encode()[:15]
        self.room_prefill = room.encode()[:6]
        self.node_id = 0
        self.link = False
        self.session = False
        self.epoch = 0
        self.peers = {}          # node_id -> name bytes[16]
        self.rtt_us = 0
        self.seq = 1
        self.pending = None      # (opcode, ftype_wanted, relay_ftype, payload, seq, deadline, next_resend)
        self.ping_seq = 0
        self.ping_sent = 0.0
        self.last_ping = 0.0
        self.last_status = 0.0
        self.tx_n64 = self.rx_n64 = 0
        self.console_up = False  # set on the first 'H'; gates periodic 'S'

    # -- relay side ----------------------------------------------------------
    def _next_seq(self):
        self.seq = (self.seq + 1) & 0xFFFF or 1
        return self.seq

    def relay_hello(self):
        payload = bytes(self.name).ljust(16, b"\x00")[:16] + \
                  bytes(self.room_prefill).ljust(6, b"\x00")[:6]
        deadline = time.time() + 10.0
        while time.time() < deadline:
            self.relay.send(FT_HELLO, payload, seq=self._next_seq())
            t0 = time.time()
            while time.time() - t0 < 1.0:
                for buf in self.relay.recv_raw():
                    f = self.parse_relay(buf)
                    if f and f[0] == FT_WELCOME:
                        self.on_welcome(f[4], f[5])
                        return True
                time.sleep(0.02)
        return False

    def parse_relay(self, buf):
        if len(buf) < 16:
            return None
        ver, ftype, flags, ch, token, seq, ack, src, dst, ln = struct.unpack(
            ">BBBBIHHBBH", buf[:16])
        if token and not self.relay.token:
            self.relay.token = token
        return (ftype, ch, src, dst, buf[16:16 + ln], token, ack)

    def ingest_roster(self, payload):
        # [node_id, code6, count, {id, name16} x count]
        self.peers = {}
        if len(payload) < 8:
            return
        count = payload[7]
        off = 8
        for _ in range(count):
            if off + 17 > len(payload):
                break
            self.peers[payload[off]] = payload[off + 1:off + 17]
            off += 17

    def on_welcome(self, payload, token):
        self.relay.token = token
        if payload:
            self.node_id = payload[0]
        self.link = True
        self.session = True   # relay HELLO always lands in a room (spec §8.4)
        self.epoch += 1
        self.ingest_roster(payload)

    def status_word(self):
        s = 0
        if self.link:
            s |= STATUS_LINK_UP
        if self.session:
            s |= STATUS_SESSION
        return s

    # -- N64 side --------------------------------------------------------------
    def send_n64(self, op, a, payload=b""):
        self.sc.usb_write(NPU_DATATYPE, npu_frame(op, a, payload))

    def send_welcome(self):
        body = struct.pack(">II", self.status_word(), self.epoch)
        body += bytes(self.room_prefill).ljust(8, b"\x00")[:8]
        body += bytes(self.name).ljust(16, b"\x00")[:16]
        self.send_n64(ord("W"), self.node_id, body)

    def send_status(self):
        self.send_n64(ord("S"), 0,
                      struct.pack(">II", self.status_word(), self.epoch))
        self.last_status = time.time()

    def send_cmdres(self, code, err=0, res0=0, res1=0, data=b""):
        body = struct.pack(">BBBBII", err, 0, 0, 0, res0, res1) + data
        self.send_n64(ord("R"), code, body)

    # -- command mailbox -------------------------------------------------------
    def start_ctl(self, opcode, relay_ftype, payload=b""):
        seq = self._next_seq()
        self.relay.send(relay_ftype, payload, seq=seq)
        now = time.time()
        self.pending = [opcode, relay_ftype, payload, seq, now + 8.0, now + 0.5]

    def on_cmd(self, opcode, body):
        # body: arg0(4) + cmd_data[16]
        cd = body[4:20] if len(body) >= 20 else b"\x00" * 16
        if self.pending:
            self.send_cmdres(CMD_ERR, err=2)  # err::BUSY
            return
        if opcode == OP_NOP:
            self.send_cmdres(CMD_OK)
        elif opcode == OP_SET_IDENTITY:
            nm = cd.split(b"\x00")[0][:15]
            if nm:
                self.name = nm
            # local completion; relay rename is async (mirrors DeviceCore)
            self.send_cmdres(CMD_OK)
            self.relay.send(FT_SETNAME, bytes(self.name).ljust(16, b"\x00"),
                            seq=self._next_seq())
            self.send_welcome()  # refresh the 0x6C name registers
        elif opcode == OP_CREATE:
            self.start_ctl(opcode, FT_CREATE)
        elif opcode == OP_JOIN:
            self.start_ctl(opcode, FT_JOIN, cd[:6])
        elif opcode == OP_LEAVE:
            if not self.session:
                self.send_cmdres(CMD_ERR, err=ERR_NOTJOINED)
            else:
                self.start_ctl(opcode, FT_LEAVE)
        elif opcode == OP_LIST_PEERS:
            if not self.session:
                self.send_cmdres(CMD_ERR, err=ERR_NOTJOINED)
                return
            data = b""
            for nid, nm in sorted(self.peers.items()):
                data += bytes([nid, 0, 0, 0]) + b"\x00" * 4 + nm[:16].ljust(16, b"\x00")
            self.send_cmdres(CMD_OK, res0=len(self.peers), data=data)
        elif opcode == OP_PING:
            self.send_cmdres(CMD_OK, res0=self.rtt_us)
        elif opcode == OP_GET_TIME:
            self.start_ctl(opcode, FT_TIME)
        else:
            self.send_cmdres(CMD_ERR, err=ERR_INVAL)

    # -- inbound relay traffic ---------------------------------------------------
    def on_relay(self, f):
        ftype, ch, src, dst, payload, token, ack = f
        if ftype == FT_DATA:
            self.rx_n64 += 1
            self.send_n64(ord("X"), src, bytes([ch]) + payload)
        elif ftype == FT_JOINED:
            if len(payload) >= 7:
                self.node_id = payload[0]
                self.session = True
                self.ingest_roster(payload)
                if self.pending and self.pending[0] in (OP_CREATE, OP_JOIN):
                    code = payload[1:7] + b"\x00\x00"
                    self.pending = None
                    self.send_cmdres(CMD_OK, res0=self.node_id, data=code)
                self.send_status()
        elif ftype == FT_WELCOME:
            self.on_welcome(payload, token)
            self.send_status()
        elif ftype == FT_LEAVE:
            self.session = False
            self.peers = {}
            if self.pending and self.pending[0] == OP_LEAVE:
                self.pending = None
                self.send_cmdres(CMD_OK)
            self.send_status()
        elif ftype == FT_TIME:
            if self.pending and self.pending[0] == OP_GET_TIME and len(payload) >= 8:
                hi, lo = struct.unpack(">II", payload[:8])
                self.pending = None
                self.send_cmdres(CMD_OK, res0=hi, res1=lo)
        elif ftype == FT_PONG:
            if self.ping_seq and ack == self.ping_seq:
                self.rtt_us = int((time.time() - self.ping_sent) * 1e6)
                self.ping_seq = 0
        elif ftype == FT_PEER_JOIN:
            if len(payload) >= 17:
                self.peers[payload[0]] = payload[1:17]
            elif payload:
                self.peers[payload[0]] = b"\x00" * 16
        elif ftype == FT_PEER_LEAVE:
            if payload:
                self.peers.pop(payload[0], None)
        elif ftype == FT_ERROR:
            if self.pending:
                self.pending = None
                self.send_cmdres(CMD_ERR, err=ERR_RELAY)

    # -- inbound N64 traffic ------------------------------------------------------
    def on_n64_data(self, data):
        off = 0
        while off + 4 <= len(data):
            op, a, ln = struct.unpack(">BBH", data[off:off + 4])
            payload = data[off + 4:off + 4 + ln]
            off += 4 + ln
            if op == ord("H"):
                print(f"[bridge] N64 HELLO (proto {a})")
                self.console_up = True
                self.send_welcome()
                self.send_status()
            elif op == ord("C"):
                self.on_cmd(a, payload)
            elif op == ord("T"):
                self.tx_n64 += 1
                if payload:
                    ch, body = payload[0], payload[1:]
                    self.relay.send(FT_DATA, body, channel=ch,
                                    src=self.node_id, dst=a)

    # -- main loop ----------------------------------------------------------------
    def run(self):
        print(f"[bridge] relay HELLO as '{self.name.decode()}' "
              f"room '{self.room_prefill.decode() or '(new)'}'...")
        if not self.relay_hello():
            print("[bridge] FATAL: relay unreachable")
            return 1
        print(f"[bridge] relay up: node={self.node_id} "
              f"token=0x{self.relay.token:08x} peers={len(self.peers)}")
        print("[bridge] waiting for console (power on the N64 now)")
        last_report = time.time()
        while True:
            # Wake the instant EITHER side has data (was a 20 ms serial-poll
            # tick, which put up to 20 ms of pure loop latency on every
            # relay->console packet and inflated the measured RTT to match).
            select.select([self.sc.fd, self.relay.sock], [], [], 0.005)
            # serial: async PKTs from the cart
            for fid, payload in self.sc.poll_pkts(0.0):
                if fid == b"U" and len(payload) >= 4:
                    (hdr,) = struct.unpack(">I", payload[:4])
                    dt, ln = hdr >> 24, hdr & 0xFFFFFF
                    if dt == NPU_DATATYPE:
                        self.on_n64_data(payload[4:4 + ln])
                elif fid == b"G":
                    print("[bridge] WARN: PC->N64 data flushed (ROM not reading)")
            # relay: drain UDP
            for buf in self.relay.recv_raw():
                f = self.parse_relay(buf)
                if f:
                    self.on_relay(f)
            now = time.time()
            # pending ctl op: resend / timeout
            if self.pending:
                opcode, rft, payload, seq, deadline, nxt = self.pending
                if now >= deadline:
                    self.pending = None
                    self.send_cmdres(CMD_ERR, err=ERR_TIMEOUT)
                elif now >= nxt:
                    self.relay.send(rft, payload, seq=seq)
                    self.pending[5] = now + 0.5
            # periodic PING -> RTT + keepalive
            if self.link and now - self.last_ping >= 2.0 and not self.ping_seq:
                self.ping_seq = self._next_seq()
                self.ping_sent = now
                self.last_ping = now
                self.relay.send(FT_PING, seq=self.ping_seq)
            # periodic status to the ROM (only once a console has said hello)
            if self.console_up and now - self.last_status >= 1.0:
                self.send_status()
            if now - last_report >= 30.0:
                last_report = now
                print(f"[bridge] alive: tx(N64->relay)={self.tx_n64} "
                      f"rx(relay->N64)={self.rx_n64} peers={len(self.peers)} "
                      f"rtt={self.rtt_us}us session={self.session}")

def run_bridge(args):
    sc = SC64(args.dev)
    ok, ident, _ = sc.cmd(b"v")
    if not ok or ident[:4] != b"SCv2":
        print(f"[bridge] FATAL: SC64 not responding ({ident!r})")
        return 1
    br = Bridge(sc, (args.relay_host, args.relay_port), args.name, args.room)
    try:
        return br.run()
    except KeyboardInterrupt:
        print("\n[bridge] stopped")
        return 0

# ---------- Self-test -------------------------------------------------------

def selftest(args):
    print("== SC64 serial link ==")
    sc = SC64(args.dev)
    ok, ident, _ = sc.cmd(b"v")
    print(f"  IDENTIFIER_GET: ok={ok} -> {ident!r}")
    ok2, ver, _ = sc.cmd(b"V")
    if ok2 and len(ver) >= 4:
        major, minor = struct.unpack(">HH", ver[:4])
        print(f"  VERSION_GET:    ok={ok2} -> {major}.{minor}")
    else:
        print(f"  VERSION_GET:    ok={ok2} -> {ver!r}")
    print("== relay ==")
    try:
        token, node, ftype = relay_hello_with_token((args.relay_host, args.relay_port))
        print(f"  HELLO -> ftype=0x{ftype:02x} token=0x{token:08x} node={node}")
    except socket.timeout:
        print("  HELLO -> TIMEOUT (relay down?)")
        return 1
    if ok and ident[:4] == b"SCv2" and ftype == FT_WELCOME:
        print("SELFTEST PASS: both sides of the bridge are alive")
        return 0
    print("SELFTEST FAIL")
    return 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dev", default=SERIAL_DEV)
    ap.add_argument("--relay-host", default="127.0.0.1")
    ap.add_argument("--relay-port", type=int, default=6465)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--name", default="console")
    ap.add_argument("--room", default="", help="room code pre-fill (like NP64_ROOM)")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest(args))
    sys.exit(run_bridge(args))

if __name__ == "__main__":
    main()
