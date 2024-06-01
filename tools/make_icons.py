#!/usr/bin/env python3

import re
import argparse
import math
import os.path
from PIL import Image

description = """
Create a sprite sheet and corresponding CSS classes from a set of icons.
"""

parser = argparse.ArgumentParser(description=description, conflict_handler="resolve")
parser.add_argument("manifest", type=str, nargs=1,
                    help="manifest file describing icons")
parser.add_argument("-g", metavar="GROUP", action="append", dest="groups",
                    help="an icon group to include")
parser.add_argument("-o", metavar="PATH", default=".", dest="output",
                    help="directory for output files")
parser.add_argument("-n", metavar="NAME", default="icons", dest="name",
                    help="base name for output files and CSS classes")
parser.add_argument("-s", metavar="SIZE", default=24, type=int, dest="size",
                    help="size of each icon sprite")

def read_manifest(s, groups):
    icons = {}
    aliases = {}
    keep = False
    for line in s:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        elif line.startswith("!!"):
            keep = line.split()[1].lower() in groups
        elif line.startswith("$"):
            alias, value = line[1:].split(None, 1)
            aliases[alias] = value
        elif keep:
            name, path = line.split(None, 1)
            path = re.sub(r"\$(\w+)", lambda m: aliases[m.group(1)], path)
            icons[name] = path
    return icons

if __name__ == "__main__":
    args = parser.parse_args()

    with open(args.manifest[0]) as f:
        icons = read_manifest(f, [g.lower() for g in args.groups])

    n = math.ceil(math.sqrt(len(icons)))
    dim = n * args.size

    images = [Image.new("RGBA", (dim, dim)),
              Image.new("RGBA", (dim * 2, dim * 2))]
    offsets = {}

    for i, (name, path) in enumerate(icons.items()):
        x = (i % n) * args.size
        y = (i // n) * args.size
        with Image.open(path) as icon:
            images[0].paste(icon.resize((args.size, args.size)), (x, y))
            images[1].paste(icon.resize((args.size * 2, args.size * 2)), (2 * x, 2 * y))
        offsets[name] = (x, y)

    base = os.path.join(args.output, args.name)
    images[0].save(base + "_icons.png", "PNG")
    images[1].save(base + "_icons@2x.png", "PNG")

    with open(base + "_icons.css", "w") as f:
        f.write(f".{args.name}_icons {{\n")
        f.write(f"  background-image: image-set(url('images/{args.name}_icons.png') 1x")
        f.write(f", url('images/{args.name}_icons@2x.png') 2x);\n")
        f.write(f"  background-size: {dim}px {dim}px;\n")
        f.write(f"  background-repeat: no-repeat;\n")
        f.write("}\n")
        for icon, (x, y) in offsets.items():
            f.write(f".{args.name}_{icon} {{ background-position: -{x}px -{y}px; }}\n")
