#!/usr/bin/env python3

import re
import argparse
import math
import os.path
from PIL import Image

description = """
Create a sprite sheet and corresponding CSS classes from a collection of icons.
"""

parser = argparse.ArgumentParser(description=description, conflict_handler="resolve")
parser.add_argument("manifest", type=str, nargs=1, help="manifest file")
parser.add_argument("-o", "--output_dir", metavar="PATH", default=".",
                    help="directory for output files")
parser.add_argument("-b", "--base_name", metavar="BASE", default="icons",
                    help="base name for output files")
parser.add_argument("-s", "--size", default=24, type=int,
                    help="size of each icon sprite")

def read_manifest(s):
    icons = {}
    aliases = {}
    for line in s:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        elif line.startswith("$"):
            alias, value = line[1:].split(None, 1)
            aliases[alias] = value
        else:
            name, path = line.split(None, 1)
            path = re.sub(r"\$(\w+)", lambda m: aliases[m.group(1)], path)
            icons[name] = path
    return icons

if __name__ == "__main__":
    args = parser.parse_args()
    with open(args.manifest[0]) as f:
        icons = read_manifest(f)

    sheet = Image.new("RGBA", (args.size, len(icons) * args.size))
    offsets = {}
    for i, (name, path) in enumerate(icons.items()):
        with Image.open(path) as image:
            icon = image.resize((args.size, args.size))
        sheet.paste(icon, (0, i * args.size))
        offsets[name] = (0, i * args.size)

    base = os.path.join(args.output_dir, args.base_name)
    sheet.save(base + ".png", "PNG")

    with open(base + ".css", "w") as f:
        f.write(f".icon {{ background-image: url('images/{args.base_name}.png'); background-repeat: no-repeat; }}\n")
        for name, (x, y) in offsets.items():
            f.write(f".{name} {{ background-position: -{x}px -{y}px; }}\n")

