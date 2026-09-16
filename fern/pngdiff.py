"""Minimal PNG reader: enough to diff two renders. No dependencies."""
import zlib, struct

def read(path):
    d = open(path,'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, w=h=None, b'', None
    pos = 8; idat = b''
    while pos < len(d):
        ln, typ = struct.unpack('>I4s', d[pos:pos+8])
        body = d[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and ctype in (2, 6), (depth, ctype)
            nch = 3 if ctype == 2 else 4
        elif typ == b'IDAT': idat += body
        elif typ == b'IEND': break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(h * stride); prev = bytearray(stride); i = 0
    for y in range(h):
        ft = raw[i]; i += 1
        line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-nch] if x >= nch else 0
            b = prev[x]
            c = prev[x-nch] if x >= nch else 0
            if ft == 1: line[x] = (line[x] + a) & 255
            elif ft == 2: line[x] = (line[x] + b) & 255
            elif ft == 3: line[x] = (line[x] + (a + b)//2) & 255
            elif ft == 4:
                p = a + b - c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out[y*stride:(y+1)*stride] = line; prev = line
    return w, h, nch, bytes(out)

def changed_pixels(p1, p2, threshold=24):
    w, h, n, a = read(p1); w2, h2, n2, b = read(p2)
    assert (w,h,n) == (w2,h2,n2)
    count = 0
    for i in range(0, len(a), n):
        if (abs(a[i]-b[i]) + abs(a[i+1]-b[i+1]) + abs(a[i+2]-b[i+2])) > threshold:
            count += 1
    return count, w*h
