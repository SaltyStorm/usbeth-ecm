"""Read-only: list the USB Ethernet ID tables inside an Android ROM's kernel.

Usage: python -I kernel_usb_ids.py <rom.zip> <empty work dir>
Pulls boot.img out of the ROM zip, unpacks the kernel, and walks the
usb_device_id tables (arm64 layout, 32 bytes per entry).
"""
import struct
import sys
import zipfile
import zlib
from pathlib import Path

rom, work = Path(sys.argv[1]), Path(sys.argv[2])
work.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(rom) as z:
    names = z.namelist()
    print("zip entries:", [n for n in names if "/" not in n][:20])
    boot = z.read("boot.img")
print("boot.img bytes:", len(boot), "magic:", boot[:8])

ksize, = struct.unpack_from("<I", boot, 8)
page, = struct.unpack_from("<I", boot, 36)
kern = boot[page:page + ksize]
print("kernel bytes:", len(kern), "first bytes:", kern[:16].hex())

gz = kern.find(b"\x1f\x8b\x08")
if 0 <= gz < 4096:
    d = zlib.decompressobj(31)
    image = d.decompress(kern[gz:])
    print("gunzipped from offset", gz, "->", len(image), "bytes")
else:
    image = kern
    print("not gzip; using as is")

import re
m = re.search(rb"Linux version [^\n]{0,160}", image)
print("version string:", m.group(0).decode("latin1") if m else "not found")

ENTRY = 32


def parse(off):
    (flags, vid, pid, lo, hi, dc, dsc, dp, ic, isc, ip, inum) = struct.unpack_from("<HHHHHBBBBBBB", image, off)
    info, = struct.unpack_from("<Q", image, off + 24)
    return dict(flags=flags, vid=vid, pid=pid, dc=dc, ic=ic, isc=isc, ip=ip, info=info, raw=image[off:off + ENTRY])


def plausible(e):
    if e["raw"] == bytes(ENTRY):
        return False
    if e["flags"] == 0 or e["flags"] > 0x07ff:
        return False
    # driver_info is 0 or a kernel pointer
    return e["info"] == 0 or (e["info"] >> 40) == 0xFFFFFF


def table_around(off):
    start = off
    while start - ENTRY >= 0 and plausible(parse(start - ENTRY)):
        start -= ENTRY
    out = []
    cur = start
    while plausible(parse(cur)):
        out.append(parse(cur))
        cur += ENTRY
    return start, out


def find_all(needle):
    res, i = [], image.find(needle)
    while i != -1:
        res.append(i)
        i = image.find(needle, i + 1)
    return res


def show(title, needle):
    print()
    print("=====", title, "=====")
    seen = set()
    for hit in find_all(needle):
        start, rows = table_around(hit)
        if start in seen or len(rows) < 2:
            continue
        seen.add(start)
        infos = sorted({r["info"] for r in rows})
        label = {v: ("0(blocked/none)" if v == 0 else "info%d" % i) for i, v in enumerate(infos)}
        print("table at 0x%x, %d entries, %d distinct driver_info values" % (start, len(rows), len(infos)))
        for r in rows:
            cls = ""
            if r["flags"] & 0x0380:
                cls = " if=%02x/%02x/%02x" % (r["ic"], r["isc"], r["ip"])
            if r["flags"] & 0x0003:
                ident = "%04x:%04x" % (r["vid"], r["pid"])
            elif r["flags"] & 0x0001:
                ident = "%04x:*" % r["vid"]
            else:
                ident = "any device"
            print("  %-10s flags=%04x%s  -> %s" % (ident, r["flags"], cls, label[r["info"]]))


# asix: AX88772 0b95:7720 with plain device match
show("asix (AX88772 family, 10/100)", struct.pack("<HHH", 0x0003, 0x0B95, 0x7720))
# ax88179_178a: 0b95:1790
show("ax88179_178a (gigabit ASIX)", struct.pack("<HHH", 0x0003, 0x0B95, 0x1790))
# r8152 and cdc_ether both carry the Realtek 8153 ECM entry
show("tables holding Realtek 0bda:8153 ECM entry (r8152 + cdc_ether block list)", struct.pack("<HHH", 0x0383, 0x0BDA, 0x8153))
# dm9601
show("dm9601", struct.pack("<HHH", 0x0003, 0x0A46, 0x9601))
