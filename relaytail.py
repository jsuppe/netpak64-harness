#!/usr/bin/env python3
"""relaytail.py — human view of the relay's diagnostic JSONL.

Usage:
  relaytail.py                    # summarize today's rooms
  relaytail.py <room>             # full timeline for a room (today)
  relaytail.py -f [<room>]        # follow live (all rooms or one)

Reads /mnt/micron/jsuppe/netpak/diag/<YYYYMMDD>/<room>.jsonl
"""
import json, os, sys, time, glob, datetime

DIAG = "/mnt/micron/jsuppe/netpak/diag"

def day_dir():
    return os.path.join(DIAG, datetime.datetime.utcnow().strftime("%Y%m%d"))

def fmt(e):
    t = datetime.datetime.fromtimestamp(e["ts"]).strftime("%H:%M:%S")
    ev = e.get("ev", "?")
    room = e.get("room", "")
    body = {k: v for k, v in e.items() if k not in ("ts", "room", "ev")}
    if ev == "race_summary":
        nodes = " ".join(
            f"{n.get('name') or n['node']}:df{n['df_max']}"
            + (f",blk{n['block_ack_ms']}ms" if n.get("block_ack_ms") is not None else "")
            for n in body.pop("nodes", []))
        return (f"{t} {room} == RACE SUMMARY == course={body.get('course')} "
                f"dur={body.get('duration_s')}s hashes={body.get('hashes_checked')} "
                f"desync={body.get('desync')} drops={body.get('drops')} | {nodes}")
    if ev == "desync":
        return f"{t} {room} !! DESYNC frame={body['frame']} {body['node_a']}:{body['hash_a']} vs {body['node_b']}:{body['hash_b']}"
    if ev == "simrate":
        return f"{t} {room} simrate node{body['node']} df={body['df']} {body['rate']}/s"
    return f"{t} {room} {ev} " + " ".join(f"{k}={v}" for k, v in body.items())

def read_all(pattern):
    events = []
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            for line in f:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return sorted(events, key=lambda e: e.get("ts", 0))

def main():
    args = sys.argv[1:]
    follow = "-f" in args
    args = [a for a in args if a != "-f"]
    room = args[0].upper() if args else None
    pattern = os.path.join(day_dir(), f"{room or '*'}.jsonl")

    if not follow:
        events = read_all(pattern)
        if not events:
            print(f"no diag events today ({pattern})")
            return
        if room:
            for e in events:
                print(fmt(e))
        else:
            rooms = {}
            for e in events:
                rooms.setdefault(e.get("room"), []).append(e)
            for r, evs in rooms.items():
                summ = [e for e in evs if e.get("ev") == "race_summary"]
                des = any(e.get("ev") == "desync" for e in evs)
                print(f"{r}: {len(evs)} events, {len(summ)} races"
                      + (" DESYNC" if des else ""))
                for e in summ:
                    print("  " + fmt(e))
        return

    seen = {}
    print(f"following {pattern} ...")
    while True:
        for path in glob.glob(os.path.join(day_dir(), f"{room or '*'}.jsonl")):
            pos = seen.get(path, 0)
            try:
                with open(path) as f:
                    f.seek(pos)
                    for line in f:
                        try:
                            print(fmt(json.loads(line)))
                        except json.JSONDecodeError:
                            pass
                    seen[path] = f.tell()
            except OSError:
                pass
        time.sleep(1)

if __name__ == "__main__":
    main()
