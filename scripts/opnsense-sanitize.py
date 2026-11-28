#!/usr/bin/env python3
"""Sanitize an OPNsense config.xml for committing to the repo.

- Secrets (password hashes, private keys, API secrets, pre-shared keys, SSH keys) -> REDACTED.
- Certificates are replaced too: they are long, regenerated per install and not reviewable.
- Volatile metadata (uuid / persisted_at attributes, <revision>) is dropped, so two exports of
  the same intent produce the same file and a diff shows only real changes.

Usage: opnsense-sanitize.py <running config.xml> <output.xml>
"""
import sys
import xml.etree.ElementTree as ET

SECRET_TAGS = {
    "password", "authorizedkeys", "prv", "crt", "csr", "key", "secret", "apikeys",
    "privkey", "privatekey", "psk", "pre-shared-key", "presharedkey", "ldap_bindpw",
    "radius_secret", "md5sigkey", "pass", "tls", "shared_key",
}
VOLATILE_ATTRS = ("uuid", "persisted_at")
VOLATILE_TAGS = {"revision"}


def sanitize(elem: ET.Element) -> int:
    redacted = 0
    for attr in VOLATILE_ATTRS:
        elem.attrib.pop(attr, None)
    for child in list(elem):
        if child.tag in VOLATILE_TAGS:
            elem.remove(child)
            continue
        if child.tag.lower() in SECRET_TAGS and len(child) == 0 and (child.text or "").strip():
            child.text = "REDACTED"
            redacted += 1
        redacted += sanitize(child)
    return redacted


def main(src: str, dst: str) -> int:
    tree = ET.parse(src)
    count = sanitize(tree.getroot())
    ET.indent(tree, space="  ")
    with open(dst, "wb") as fh:
        fh.write(b"<?xml version=\"1.0\"?>\n")
        fh.write(b"<!-- Sanitized export of the running config (scripts/opnsense-sanitize.py). Not for restore. -->\n")
        tree.write(fh, encoding="utf-8", xml_declaration=False)
        fh.write(b"\n")
    print(f"{dst}: {count} values redacted")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
