#!/usr/bin/env python3
import io
import tarfile
from pathlib import Path
import sys

out = Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(out, "w:gz") as tf:
    data = b"bad"
    info = tarfile.TarInfo("../escape")
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))
print(out)
