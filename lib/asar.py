"""Read single files out of an Electron .asar archive without Node.

Usage:
    asar.py ARCHIVE cat PATH          print a file to stdout
    asar.py ARCHIVE extract GLOB OUT  write the largest file matching GLOB to OUT
"""
import fnmatch
import json
import struct
import sys


def read_index(f):
    # Chromium Pickle framing: [4][header_pickle_size][payload_size][json_len] + json
    _, header_size, _, json_len = struct.unpack("<4I", f.read(16))
    index = json.loads(f.read(json_len))
    return index, 8 + header_size


def walk(node, prefix=""):
    for name, entry in node.get("files", {}).items():
        path = f"{prefix}{name}"
        if "files" in entry:
            yield from walk(entry, path + "/")
        else:
            yield path, entry


def read_file(f, base, entry):
    if entry.get("unpacked"):
        raise SystemExit("file is in app.asar.unpacked, read it from disk instead")
    f.seek(base + int(entry["offset"]))
    return f.read(entry["size"])


def main():
    archive, cmd, pattern = sys.argv[1:4]
    with open(archive, "rb") as f:
        index, base = read_index(f)
        matches = [(p, e) for p, e in walk(index) if fnmatch.fnmatch(p, pattern)]
        if not matches:
            raise SystemExit(f"no file matching {pattern!r} in {archive}")
        path, entry = max(matches, key=lambda m: m[1].get("size", 0))
        data = read_file(f, base, entry)
    if cmd == "cat":
        sys.stdout.buffer.write(data)
    elif cmd == "extract":
        with open(sys.argv[4], "wb") as out:
            out.write(data)
    else:
        raise SystemExit(f"unknown command {cmd!r}")


if __name__ == "__main__":
    main()
