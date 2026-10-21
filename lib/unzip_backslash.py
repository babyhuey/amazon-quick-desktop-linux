"""Extract a zip whose entry names use Windows backslash separators.

Usage: unzip_backslash.py ZIP DEST
"""
import os
import sys
import zipfile


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with zipfile.ZipFile(src) as z:
        for info in z.infolist():
            name = info.filename.replace("\\", "/")
            if name.startswith("/") or ".." in name.split("/"):
                raise SystemExit(f"refusing unsafe path in zip: {info.filename!r}")
            out = os.path.join(dst, name)
            if name.endswith("/"):
                os.makedirs(out, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(info) as r, open(out, "wb") as w:
                while chunk := r.read(1 << 20):
                    w.write(chunk)


if __name__ == "__main__":
    main()
