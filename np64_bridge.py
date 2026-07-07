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
            wait = deadline - time.time()
            if wait <= 0:
                return False
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
        """PC -> N64: SC64 USB_WRITE command."""
        ok, _, _ = self.cmd(b"U", datatype, len(data), data)
        return ok

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
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest(args))
    print("bridge run mode: implemented in the next increment")

if __name__ == "__main__":
    main()
