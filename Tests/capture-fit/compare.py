"""TEST ONLY. Compares the patterned window's frames two runs of Tests/capture-fit saved (CAPTURE_FIT_FRAMES=DIR,
a PGM of each frame's luma): per frame, the mean and largest difference of a pixel's luma, and the share
of pixels more than 8 apart. Run it on two runs of the same build too: a downscale differs by a level or
two between runs of one build (the GPU's scaler), a frame at the window's own pixels by nothing.
usage: python3 -I compare.py DIR-A DIR-B"""
import os, sys

def load(path):
    data = open(path, "rb").read()
    head, rest = data.split(b"\n", 1)
    size, rest = rest.split(b"\n", 1)
    _, luma = rest.split(b"\n", 1)
    w, h = map(int, size.split())
    return w, h, luma

a, b = sys.argv[1], sys.argv[2]
worst = 0
for name in sorted(n for n in os.listdir(a) if n.endswith(".pgm")):
    if not os.path.exists(os.path.join(b, name)):
        print(f"{name}: only in {a}"); worst = max(worst, 255); continue
    wa, ha, x = load(os.path.join(a, name))
    wb, hb, y = load(os.path.join(b, name))
    if (wa, ha) != (wb, hb):
        print(f"{name}: {wa}×{ha} against {wb}×{hb}"); worst = max(worst, 255); continue
    diffs = [abs(p - q) for p, q in zip(x, y)]
    biggest = max(diffs)
    worst = max(worst, biggest)
    print(f"{name}: mean |difference| {sum(diffs) / len(diffs):.4f}, largest {biggest}, more than 8 apart {sum(d > 8 for d in diffs) / len(diffs):.4%}")
print(f"largest difference anywhere: {worst}")
