#!/usr/bin/env python3
"""Summarise the usage-tracking log (see scripts/ux.gd and nginx.conf).

    python3 tools/ux_report.py /workspace/data/gridiron-career-ux/ux.log [--since 2026-10-28]

Prints what gets tapped, which panels are opened and how long they stay open, and the
patterns that usually point at a UI problem: panels closed within two seconds (opened by
mistake, or not what was wanted), the same button tapped again within 1.5 seconds (it did
not seem to respond), and panels that are only ever left by closing them.
"""
import json
import statistics
import sys
from collections import Counter, defaultdict


def load(path, since=""):
    visits = defaultdict(list)
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            rec = json.loads(line)
            if since and rec.get("t", "") < since:
                continue
            body = json.loads(rec["body"])
        except (ValueError, KeyError):
            continue
        for e in body.get("ev", []):
            e["_ua"] = rec.get("ua", "")
            visits[(body.get("cid", "?"), body.get("sid", "?"))].append(e)
    for v in visits.values():
        v.sort(key=lambda e: e.get("s", 0))
    return visits


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    since = ""
    if "--since" in sys.argv:
        since = sys.argv[sys.argv.index("--since") + 1]
        args = [a for a in args if a != since]
    visits = load(args[0] if args else "/workspace/data/gridiron-career-ux/ux.log", since)
    if not visits:
        print("no events yet")
        return
    taps = Counter()
    tap_panel = Counter()
    stays = defaultdict(list)
    bounces = Counter()
    retaps = Counter()
    exits = defaultdict(Counter)
    versions = Counter()
    screens = Counter()
    finals = Counter()
    total = 0.0
    for (cid, sid), evs in visits.items():
        total += max((e.get("s", 0) for e in evs), default=0)
        last_tap = None
        for i, e in enumerate(evs):
            k = e.get("k")
            if k == "start":
                versions[e.get("v", "?")] += 1
                screens["%sx%s%s" % (e.get("w"), e.get("h"), " touch" if e.get("touch") else "")] += 1
            elif k == "tap":
                b = e.get("b") or "(unlabelled)"
                taps[b] += 1
                tap_panel[(e.get("p", "?"), b)] += 1
                if last_tap and last_tap[0] == b and e.get("s", 0) - last_tap[1] < 1.5:
                    retaps[(e.get("p", "?"), b)] += 1
                last_tap = (b, e.get("s", 0))
            elif k == "panel":
                frm, stayed = e.get("from", "?"), float(e.get("stayed", 0))
                if frm != "field":
                    stays[frm].append(stayed)
                    if stayed < 2.0:
                        bounces[frm] += 1
                    # how it was left: the last tap before this change
                    prev = next((p for p in reversed(evs[:i]) if p.get("k") == "tap"), None)
                    exits[frm][(prev or {}).get("b", "?")] += 1
            elif k == "final":
                finals[e.get("mode", "?")] += 1
    print("visits %d (browsers %d), %.0f minutes in all, games finished %s" % (
        len(visits), len({c for c, _ in visits}), total / 60, dict(finals)))
    print("versions %s" % dict(versions.most_common(5)))
    print("screens %s" % dict(screens.most_common(5)))
    print("\nmost tapped:")
    for b, n in taps.most_common(30):
        print("  %5d  %s" % (n, b))
    print("\npanels: opened, median / longest stay (s), closed within 2 s:")
    for p, xs in sorted(stays.items(), key=lambda kv: -len(kv[1])):
        print("  %4d  %6.1f %7.1f  %3d  %s" % (len(xs), statistics.median(xs), max(xs), bounces[p], p))
    if retaps:
        print("\ntapped again within 1.5 s (did it respond?):")
        for (p, b), n in retaps.most_common(15):
            print("  %4d  %s  [%s]" % (n, b, p))
    print("\nhow each panel is left (top 3):")
    for p, c in sorted(exits.items(), key=lambda kv: -sum(kv[1].values()))[:20]:
        print("  %s: %s" % (p, ", ".join("%s x%d" % (b, n) for b, n in c.most_common(3))))


if __name__ == "__main__":
    main()
