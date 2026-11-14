#!/usr/bin/env python3
"""Set the image digests in a merlion-bank-infra values file, changing nothing else.

Usage: update-digests.py <values file> <digests.json>
digests.json maps image name -> sha256 digest, e.g. {"frontend": "sha256:…", "accounts-db": "sha256:…"}.

The values file keeps the digest of each image on one line, within that image's section, e.g.
    frontend:
      image: { digest: "sha256:…" }
Only the quoted digest on those lines is replaced, so the diff is exactly the changed digests (what the
infra repo's "staging promotion only" check verifies). Fails if any image isn't found exactly once.
"""
import json
import re
import sys

# image name -> the key that introduces its digest line in the values file
SECTIONS = {
    "frontend": "frontend", "userservice": "userservice", "contacts": "contacts",
    "ledgerwriter": "ledgerwriter", "balancereader": "balancereader",
    "transactionhistory": "transactionhistory",
    "accounts-db": "accounts", "ledger-db": "ledger",  # under dbInit
    "loadgenerator": "loadgenerator",
}
DIGEST = re.compile(r'(digest:\s*")(sha256:[0-9a-f]{64})(")')

values_path, digests_path = sys.argv[1], sys.argv[2]
lines = open(values_path).read().split("\n")
digests = json.load(open(digests_path))

changed = 0
for image, digest in digests.items():
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        sys.exit(f"{image}: not a sha256 digest: {digest!r}")
    key = SECTIONS[image]
    # The digest line is the key's own line (inline map) or the line right after it
    hits = [i for i, l in enumerate(lines) if re.match(rf"\s*{re.escape(key)}:", l)]
    if len(hits) != 1:
        sys.exit(f"{image}: expected exactly one '{key}:' line, found {len(hits)}")
    i = hits[0]
    # The digest is on the key's own line (inline map) or further down in the same section, which
    # ends at the next line indented no deeper than the key
    indent = len(lines[i]) - len(lines[i].lstrip())
    section = [i]
    for j in range(i + 1, len(lines)):
        if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip()) <= indent:
            break
        section.append(j)
    found = [j for j in section if DIGEST.search(lines[j])]
    if len(found) != 1:
        sys.exit(f"{image}: expected one digest in the '{key}:' section, found {len(found)}")
    target = found[0]
    new = DIGEST.sub(rf"\g<1>{digest}\g<3>", lines[target])
    if new != lines[target]:
        lines[target] = new
        changed += 1

open(values_path, "w").write("\n".join(lines))
print(f"{changed} digest(s) changed in {values_path}")
