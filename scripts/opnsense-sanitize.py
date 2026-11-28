#!/usr/bin/env python3
"""Sanitize an OPNsense config.xml for committing to the repo.

- Secrets (password hashes, private keys, API secrets, pre-shared keys, SSH keys) -> REDACTED.
- Certificates are replaced too: they are long, regenerated per install and not reviewable.
- Volatile metadata (uuid / persisted_at attributes, <revision>, certificate reference ids,
  references to uuids) is dropped or normalised, so two exports of the same intent produce the
  same file - even across a rebuild - and a diff shows only real changes.

Usage: opnsense-sanitize.py <running config.xml> <output.xml>
"""
import re
import sys
import xml.etree.ElementTree as ET

SECRET_TAGS = {
    "password", "authorizedkeys", "prv", "crt", "csr", "key", "secret", "apikeys",
    "privkey", "privatekey", "psk", "pre-shared-key", "presharedkey", "ldap_bindpw",
    "radius_secret", "md5sigkey", "pass", "tls", "shared_key",
}
VOLATILE_ATTRS = ("uuid", "persisted_at")
VOLATILE_TAGS = {"revision"}
# Generated per install: certificate reference ids, and references to (stripped) uuids.
CERTREF_TAGS = {"refid", "certref", "ssl-certref", "caref"}
UUID_LIST = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(,[0-9a-f-]{36})*$")


def sanitize(elem: ET.Element) -> int:
    redacted = 0
    for attr in VOLATILE_ATTRS:
        elem.attrib.pop(attr, None)
    for child in list(elem):
        if child.tag in VOLATILE_TAGS:
            elem.remove(child)
            continue
        text = (child.text or "").strip()
        if len(child) == 0 and text:
            if child.tag.lower() in SECRET_TAGS:
                child.text = "REDACTED"
                redacted += 1
            elif child.tag.lower() in CERTREF_TAGS:
                child.text = "CERTREF"
            elif UUID_LIST.match(text):
                child.text = f"UUID-REF x{text.count(',') + 1}"
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
