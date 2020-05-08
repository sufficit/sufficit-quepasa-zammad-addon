#!/usr/bin/env python3
import os
import base64
import json
import datetime
import platform
import glob
import re
from collections import OrderedDict

# files matching this pattern are not included in the package
ignored_patterns = [
    "\.gitkeep"
]


def encode(fname):
    data = open(fname, "r", encoding='utf-8').read().encode('utf-8')
    return base64.b64encode(data).decode('utf-8')


def read_perm(fname):
    return int(oct(os.stat(fname).st_mode & 0o777)[-3:])


def format_file(content, pkg_path, permission):
    return OrderedDict(
            location=pkg_path,
            permission=permission,
            encode="base64",
            content=content)


def pkg_file(actual_path):
    print("  Packaging: {}".format(actual_path))
    pkg_path = actual_path[6:]
    contents = encode(actual_path)
    res = format_file(contents, pkg_path, read_perm(actual_path))
    return res


def pkg_files():
    pkged_files = []
    for root, dirs, files in os.walk("./src/"):
        for f in files:
            if any(re.search(r, f) for r in ignored_patterns):
                continue
            actual_path = os.path.join(root, f)
            pkged_files.append(pkg_file(actual_path))
    return pkged_files


def load_skeleton():
    t = glob.glob('*.szpm.template')
    if len(t) != 1:
        raise Exception("Cannot find szpm template")
    with open(t[0], 'r', encoding='utf-8') as f:
        skeleton = json.load(f, object_pairs_hook=OrderedDict)
        return skeleton


def main():
    files = pkg_files()
    skeleton = load_skeleton()
    skeleton["files"] = files
    skeleton["builddate"] = datetime.datetime.utcnow().isoformat()
    skeleton["buildhost"] = platform.node()
    name = skeleton["name"].lower()
    version = skeleton["version"]
    pkg = json.dumps(skeleton, indent=2)
    with open("dist/{}-v{}.szpm".format(name, version), "w", encoding='utf-8') as f:
        f.write(pkg)


main()
