#!/usr/bin/env python3
"""bridge_fsm_test.py — exercise np64_bridge.Bridge against the LIVE relay
with a fake SC64 (no console needed). Validates the exact byte contract the
ROM's netpak_sc64.c expects: 'W' on HELLO, 'R' completions for the mailbox
opcodes, 'X' delivery of room DATA, and the 'T' -> relay DATA path.
"""
import socket
import struct
import sys
import time

sys.path.insert(0, "/mnt/micron/jsuppe/netpak")
import np64_bridge as nb

RELAY = ("127.0.0.1", 6465)

class FakeSC64:
    """Stands in for the serial link: captures PC->N64 usb_write frames and
    lets the test inject N64->PC PKT payloads."""
    def __init__(self):
        self.to_n64 = []   # decoded (op, a, payload)
        self.from_n64 = [] # queued PKT payloads

    def usb_write(self, datatype, data):
        assert datatype == nb.NPU_DATATYPE
        off = 0
        while off + 4 <= len(data):
            op, a, ln = struct.unpack(">BBH", data[off:off + 4])
            self.to_n64.append((chr(op), a, data[off + 4:off + 4 + ln]))
            off += 4 + ln

    def poll_pkts(self, timeout=0.0):
        pkts, self.from_n64 = self.from_n64, []
        return pkts

    def inject(self, frame):
        """Queue an N64-origin netpak frame as a PKT 'U' payload."""
        hdr = struct.pack(">I", (nb.NPU_DATATYPE << 24) | len(frame))
        self.from_n64.append((b"U", hdr + frame))

def pump(br, sc, secs=0.6):
    deadline = time.time() + secs
    while time.time() < deadline:
        for fid, payload in sc.poll_pkts():
            if fid == b"U":
                (h,) = struct.unpack(">I", payload[:4])
                br.on_n64_data(payload[4:4 + (h & 0xFFFFFF)])
        for buf in br.relay.recv_raw():
            f = br.parse_relay(buf)
            if f:
                br.on_relay(f)
        now = time.time()
        if br.pending and now >= br.pending[5]:
            br.relay.send(br.pending[1], br.pending[2], seq=br.pending[3])
            br.pending[5] = now + 0.5
        time.sleep(0.01)

def take(sc, op):
    got = [f for f in sc.to_n64 if f[0] == op]
    sc.to_n64 = [f for f in sc.to_n64 if f[0] != op]
    return got

def main():
    failures = []
    def check(cond, what):
        print(("  PASS " if cond else "  FAIL ") + what)
        if not cond:
            failures.append(what)

    sc = FakeSC64()
    br = nb.Bridge(sc, RELAY, "bench", "")
    print("== relay hello ==")
    check(br.relay_hello(), "relay HELLO/WELCOME")
    check(br.link and br.session, "link+session up after HELLO")

    print("== N64 HELLO -> W ==")
    sc.inject(nb.npu_frame(ord("H"), 1))
    pump(br, sc, 0.2)
    w = take(sc, "W")
    check(len(w) == 1 and len(w[0][2]) == 32, "one 'W' frame, 32 B payload")
    if w:
        status, epoch = struct.unpack(">II", w[0][2][:8])
        check(status & 3 == 3, f"W status LINK|SESSION (0x{status:x})")
        name = w[0][2][16:32].rstrip(b"\x00")
        check(name == b"bench", f"W carries name {name!r}")

    print("== SESSION_CREATE ==")
    body = b"\x00" * 4 + b"\x00" * 16
    sc.inject(nb.npu_frame(ord("C"), nb.OP_CREATE, body))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    check(len(r) >= 1 and r[0][1] == nb.CMD_OK, "'R' OK for CREATE")
    code = b""
    if r:
        code = r[0][2][12:18]
        check(len(code.rstrip(b"\x00")) == 6, f"room code in CMD_DATA: {code!r}")

    print("== second client joins; roster + DATA ==")
    peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    peer.settimeout(2.0)
    hello = b"peer2".ljust(16, b"\x00") + code[:6]
    peer.sendto(struct.pack(">BBBBIHHBBH", 1, nb.FT_HELLO, 0, 0, 0, 1, 0, 0, 0xFF,
                            len(hello)) + hello, RELAY)
    buf, _ = peer.recvfrom(2048)
    ptoken = struct.unpack(">I", buf[4:8])[0]
    pnode = buf[16]
    check(buf[1] == nb.FT_WELCOME, f"peer2 welcomed as node {pnode}")
    pump(br, sc, 0.5)
    check(pnode in br.peers, "bridge roster picked up peer2 via PEER_JOIN")

    print("== LIST_PEERS ==")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_LIST_PEERS, body))
    pump(br, sc, 0.3)
    r = take(sc, "R")
    ok = len(r) == 1 and r[0][1] == nb.CMD_OK
    check(ok, "'R' OK for LIST_PEERS")
    if ok:
        count = struct.unpack(">I", r[0][2][4:8])[0]
        entry = r[0][2][12:36]
        check(count == 1 and entry[0] == pnode and
              entry[8:24].rstrip(b"\x00") == b"peer2",
              f"peer entry: id={entry[0]} name={entry[8:24].rstrip(b'\\x00')!r}")

    print("== peer2 DATA -> 'X' to N64 ==")
    payload = b"lockstep-frame-7"
    peer.sendto(struct.pack(">BBBBIHHBBH", 1, nb.FT_DATA, 0, 0, ptoken, 2, 0, 0,
                            0xFF, len(payload)) + payload, RELAY)
    pump(br, sc, 0.5)
    x = take(sc, "X")
    check(len(x) == 1 and x[0][1] == pnode and x[0][2] == b"\x00" + payload,
          "'X' carries src/ch/payload")

    print("== N64 'T' -> peer2 receives DATA ==")
    sc.inject(nb.npu_frame(ord("T"), 0xFF, b"\x01" + b"input-tick-42"))
    pump(br, sc, 0.3)
    try:
        buf, _ = peer.recvfrom(2048)
        got = None
        for _ in range(4):
            if buf[1] == nb.FT_DATA:
                got = buf
                break
            buf, _ = peer.recvfrom(2048)
        check(got is not None and got[16:16 + 13] == b"input-tick-42"
              and got[3] == 1, "peer2 got ch1 DATA from console")
    except socket.timeout:
        check(False, "peer2 got ch1 DATA from console (timeout)")

    print("== PING / GET_TIME ==")
    br.ping_seq = br._next_seq()
    br.ping_sent = time.time()
    br.relay.send(nb.FT_PING, seq=br.ping_seq)
    pump(br, sc, 0.5)
    check(br.rtt_us > 0, f"RTT sampled: {br.rtt_us} us")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_PING, body))
    pump(br, sc, 0.3)
    r = take(sc, "R")
    check(len(r) == 1 and r[0][1] == nb.CMD_OK, "'R' OK for PING")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_GET_TIME, body))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    check(len(r) == 1 and r[0][1] == nb.CMD_OK, "'R' OK for GET_TIME")

    print("== SET_IDENTITY ==")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_SET_IDENTITY,
                           b"\x00" * 4 + b"jonracer".ljust(16, b"\x00")))
    pump(br, sc, 0.3)
    r = take(sc, "R")
    w = take(sc, "W")
    check(len(r) == 1 and r[0][1] == nb.CMD_OK, "'R' OK for SET_IDENTITY")
    check(len(w) == 1 and w[0][2][16:32].rstrip(b"\x00") == b"jonracer",
          "fresh 'W' carries the new name")

    print("== FIND GAME: public room is listed, private is not ==")
    # current room was created PRIVATE (arg0=0) -> LIST must NOT show it
    sc.inject(nb.npu_frame(ord("C"), nb.OP_LIST_GAMES, body))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    ok = len(r) == 1 and r[0][1] == nb.CMD_OK
    check(ok, "'R' OK for LIST_GAMES (private era)")
    if ok:
        count = struct.unpack(">I", r[0][2][4:8])[0]
        check(count == 0, f"private room not listed (count={count})")
    # re-create PUBLIC (ARG0 bit0) -> LIST must show it with our host name
    pubbody = b"\x00\x00\x00\x01" + b"\x00" * 16
    sc.inject(nb.npu_frame(ord("C"), nb.OP_CREATE, pubbody))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    check(len(r) >= 1 and r[0][1] == nb.CMD_OK, "'R' OK for PUBLIC create")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_LIST_GAMES, body))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    ok = len(r) == 1 and r[0][1] == nb.CMD_OK
    check(ok, "'R' OK for LIST_GAMES (public era)")
    if ok:
        count = struct.unpack(">I", r[0][2][4:8])[0]
        e = r[0][2][12:40]  # 28B entry: code8, players, pad3, host16
        host = e[12:28].rstrip(b"\x00")
        check(count == 1 and e[8] == 1 and host == b"jonracer",
              f"listed: count={count} players={e[8] if len(e)>8 else '?'} host={host!r}")

    print("== SESSION_LEAVE ==")
    sc.inject(nb.npu_frame(ord("C"), nb.OP_LEAVE, body))
    pump(br, sc, 1.0)
    r = take(sc, "R")
    check(len(r) == 1 and r[0][1] == nb.CMD_OK, "'R' OK for LEAVE")
    check(not br.session, "session bit dropped")

    print()
    if failures:
        print(f"FSM TEST: {len(failures)} FAILURE(S)")
        return 1
    print("FSM TEST: ALL PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
