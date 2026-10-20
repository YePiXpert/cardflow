"""列出目录里每张 PNG 的像素尺寸（读 IHDR，不依赖第三方库）。用法：python3 -I png_size.py <目录>"""
import pathlib
import struct
import sys

for path in sorted(pathlib.Path(sys.argv[1]).glob('*.png')):
    head = path.read_bytes()[:24]
    width, height = struct.unpack('>II', head[16:24])
    print(f'{path.name}  {width}x{height}  {path.stat().st_size} bytes')
