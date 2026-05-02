#!/usr/bin/env python3
"""Extract or inject wallet key material from/into user_config.yaml.

Cross-version safe: only the listed key paths are extracted/written; every
other config field (peers, ports, monitoring, etc) is left alone. This lets
operators back up keys on one node version and restore them onto another
without dragging unrelated host-specific or version-specific config along.

Usage (from cmd_keys.sh):
    keys_io.py extract <config.yaml>                  -> stdout
    keys_io.py inject  <keys.yaml> <config.yaml> <out.yaml>
"""

import sys
import yaml


# The kms section uses YAML tags: !Zk <hex>, !Ed25519 <hex>. PyYAML doesn't
# know these by default. Round-trip them through a transparent wrapper so we
# never lose the tag.
class _Tagged:
    __slots__ = ("tag", "value")

    def __init__(self, tag, value):
        self.tag = tag
        self.value = value


def _tag_constructor(loader, tag_suffix, node):
    return _Tagged(tag_suffix, loader.construct_scalar(node))


def _tag_representer(dumper, data):
    return dumper.represent_scalar(f"!{data.tag}", str(data.value))


yaml.SafeLoader.add_multi_constructor("!", _tag_constructor)
yaml.SafeDumper.add_representer(_Tagged, _tag_representer)


# Every YAML path that holds wallet identity / signing material. Anything not
# on this list is operator-specific config (peers, ports, log levels, etc) and
# is NOT carried across by backup/restore.
#
# When upstream node releases add or rename key fields, update this list and
# the change will apply uniformly to backup and restore.
KEY_PATHS = [
    # libp2p node identity (host private key for peer auth)
    ("network", "backend", "swarm", "node_key"),
    # blend mixnet keys (KMS key id references)
    ("blend", "non_ephemeral_signing_key_id"),
    ("blend", "core", "zk", "secret_key_kms_id"),
    # cryptarchia leader / sdp wallet funding key references
    ("cryptarchia", "leader", "wallet", "funding_pk"),
    ("sdp", "wallet", "funding_pk"),
    # wallet's voucher master KMS key id
    ("wallet", "voucher_master_key_id"),
    # wallet's known keys (KeyId -> ZkPublicKey map)
    ("wallet", "known_keys"),
    # KMS — holds the actual !Zk / !Ed25519 secret material for every KeyId
    # referenced above. THIS is the section where the signing power lives.
    ("kms", "backend", "keys"),
]


def _deep_get(node, path):
    for p in path:
        if not isinstance(node, dict) or p not in node:
            return None
        node = node[p]
    return node


def _deep_set(node, path, value):
    *parents, last = path
    for p in parents:
        if p not in node or not isinstance(node[p], dict):
            node[p] = {}
        node = node[p]
    node[last] = value


def extract(config_path):
    with open(config_path) as f:
        full = yaml.safe_load(f)
    keys = {}
    for path in KEY_PATHS:
        v = _deep_get(full, path)
        if v is not None:
            _deep_set(keys, path, v)
    yaml.safe_dump(keys, sys.stdout, default_flow_style=False, sort_keys=False)


def inject(keys_path, config_path, out_path):
    with open(keys_path) as f:
        keys = yaml.safe_load(f) or {}
    with open(config_path) as f:
        full = yaml.safe_load(f)
    if full is None:
        raise SystemExit("error: current config is empty")
    for path in KEY_PATHS:
        v = _deep_get(keys, path)
        if v is not None:
            _deep_set(full, path, v)
    with open(out_path, "w") as f:
        yaml.safe_dump(full, f, default_flow_style=False, sort_keys=False)


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "extract" and len(sys.argv) == 3:
        extract(sys.argv[2])
    elif cmd == "inject" and len(sys.argv) == 5:
        inject(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
