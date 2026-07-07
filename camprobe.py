#!/usr/bin/env python3
"""Cross-instance state probe: reads game state from two ares GDB stubs
(alice=host :9124, bob=joiner :9125) during a lockstep race and checks
render-side camera invariants that the in-ROM sim-hash detector cannot see:

  A. SIM-CAMERA IDENTITY  bob's sCamSim1 (the sim camera it restores each
     frame) should track alice's camera1 (host has no swap, camera1 IS the
     sim camera). Divergence here would eventually desync visibility gating.
  B. LOCAL TRACKING       bob's sCamLoc1 yaw should track BOB's kart yaw,
     not the host's. Pre-v41 the smoothing bleed made it mirror kart 0.
  C. SIM IDENTITY (loose) kart 0 position from both instances should agree
     within the input-delay window's worth of movement.

Addresses are for test ROM bcc0f661 (v41+anchors). Instances are sampled
live (no halt); tolerance covers the frame skew between consoles.
"""
import socket, struct, sys, time

GPLAYERS   = 0x80100fb0
CAMERA1    = 0x800e7b60
ANCHORS    = 0x8041afa0
PLAYER_SZ  = 0xDD8
P_POS, P_ROT = 0x14, 0x2C
C_POS, C_ROT, C_PID = 0x00, 0x24, 0xAE

class Stub:
    def __init__(self, port):
        self.s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        self.s.settimeout(5)
        self.s.connect(('::1', port))
        self.s.sendall(b'+')
        self.cmd(b'qSupported:swbreak+')
        self.cmd(b'?')
    def cmd(self, c):
        self.s.sendall(b'$' + c + b'#' + b'%02x' % (sum(c) & 0xff))
        buf = b''
        t0 = time.time()
        while time.time() - t0 < 5:
            try: r = self.s.recv(4096)
            except socket.timeout: break
            if not r: break
            buf += r
            if b'#' in buf[1:]: break
        if buf: self.s.sendall(b'+')
        return buf.split(b'$')[-1].split(b'#')[0]
    def cont(self):
        # resume; no ack expected until next stop
        c = b'c'
        self.s.sendall(b'$' + c + b'#' + b'%02x' % (sum(c) & 0xff))
    def interrupt(self):
        self.s.sendall(b'\x03')  # raw break
        buf = b''
        t0 = time.time()
        while time.time() - t0 < 4:
            try: r = self.s.recv(4096)
            except socket.timeout: break
            if not r: break
            buf += r
            if b'#' in buf[1:]: break
        if buf: self.s.sendall(b'+')
    def mem(self, a, n):
        h = self.cmd(('m%x,%x' % (a, n)).encode())
        try: return bytes.fromhex(h.decode())
        except Exception: return b''
    def u32(self, a):
        d = self.mem(a, 4)
        return struct.unpack('>I', d)[0] if len(d) == 4 else 0
    def s16at(self, a):
        d = self.mem(a, 2)
        return struct.unpack('>h', d)[0] if len(d) == 2 else 0
    def vec3f(self, a):
        d = self.mem(a, 12)
        return struct.unpack('>3f', d) if len(d) == 12 else (0.0, 0.0, 0.0)

def adiff(a, b):  # shortest s16 angle distance, in degrees
    d = (a - b) & 0xFFFF
    if d > 0x8000: d -= 0x10000
    return abs(d) * 360.0 / 65536.0

def main():
    alice, bob = Stub(9124), Stub(9125)
    anc = [bob.u32(ANCHORS + i * 4) for i in range(4)]
    if not (0x80400000 <= anc[0] < 0x80800000):
        print("anchors not filled yet (race not started?) ->", [hex(x) for x in anc])
        sys.exit(1)
    cam_loc, cam_sim, _, cam_act = anc
    # wait until bob is actually IN a race (sCamActive nonzero = joiner render
    # swap ran this frame; it goes 0 outside RACING). Bails after ~4 min.
    ls = 0
    for w in range(80):
        ls = bob.u32(cam_act)
        if ls != 0:
            break
        alice.cont(); bob.cont()
        time.sleep(3.0)
        alice.interrupt(); bob.interrupt()
    if ls == 0:
        print("never saw an active joiner render swap — not in a race; aborting")
        sys.exit(1)
    print("bob local slot =", ls)
    worstA = worstB_own = 0.0
    bestB_host = 180.0
    worstC = 0.0
    n = 12
    for i in range(n):
        # let both instances run, then stop both for an (approximately)
        # coherent sample pair
        alice.cont(); bob.cont()
        time.sleep(3.0)
        alice.interrupt(); bob.interrupt()
        a_cam_yaw = alice.s16at(CAMERA1 + C_ROT + 2)
        b_sim_yaw = bob.s16at(cam_sim + C_ROT + 2)
        b_loc_yaw = bob.s16at(cam_loc + C_ROT + 2)
        b_own_yaw = bob.s16at(GPLAYERS + ls * PLAYER_SZ + P_ROT + 2)
        b_k0_yaw  = bob.s16at(GPLAYERS + 0 * PLAYER_SZ + P_ROT + 2)
        a_k0 = alice.vec3f(GPLAYERS + P_POS)
        b_k0 = bob.vec3f(GPLAYERS + P_POS)
        dA = adiff(a_cam_yaw, b_sim_yaw)
        dB_own  = adiff(b_loc_yaw, b_own_yaw)
        dB_host = adiff(b_loc_yaw, b_k0_yaw)
        dC = max(abs(a_k0[j] - b_k0[j]) for j in range(3))
        worstA = max(worstA, dA)
        worstB_own = max(worstB_own, dB_own)
        bestB_host = min(bestB_host, dB_host)
        worstC = max(worstC, dC)
        print(f"[{i:2}] A simcam d={dA:6.1f}deg  B loccam-vs-OWN={dB_own:6.1f} "
              f"vs-HOST={dB_host:6.1f}  C kart0 dpos={dC:8.1f}")
    print()
    print(f"A sim-camera identity : worst {worstA:.1f} deg  "
          f"({'OK' if worstA < 25 else 'SUSPECT'} — frame-skew tolerance 25)")
    print(f"B local cam tracks own: worst {worstB_own:.1f} deg vs own kart "
          f"({'OK' if worstB_own < 60 else 'SUSPECT'} — chase lag tolerance 60)")
    print(f"C kart0 position agree: worst {worstC:.1f} units "
          f"({'OK' if worstC < 400 else 'SUSPECT'} — delay-window tolerance)")

if __name__ == '__main__':
    main()
