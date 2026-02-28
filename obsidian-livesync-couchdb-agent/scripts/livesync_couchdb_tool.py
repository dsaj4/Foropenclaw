#!/usr/bin/env python3
import argparse
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request
from hashlib import sha256


def _auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def _request(url: str, user: str, password: str, method: str = "GET", payload=None):
    headers = {"Authorization": _auth_header(user, password), "Content-Type": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url=url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read().decode("utf-8")
            if not raw:
                return {}
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {e.reason}: {body}") from e


def _url(base: str, db: str, doc_id: str | None = None, suffix: str | None = None):
    out = f"{base.rstrip('/')}/{urllib.parse.quote(db, safe='')}"
    if doc_id is not None:
        out += f"/{urllib.parse.quote(doc_id, safe='')}"
    if suffix:
        out += suffix
    return out


def _hash_string(key: str) -> str:
    buff = key.encode("utf-8")
    digest = sha256(buff).digest()
    for _ in range(len(key)):
        digest = sha256(buff).digest()
    return digest.hex()


def path2id(path: str, case_insensitive: bool, obfuscate_passphrase: str | None):
    normalized = path.lower() if case_insensitive else path
    source = f"/{normalized}" if normalized.startswith("_") else normalized
    if not obfuscate_passphrase:
        return source
    if source.startswith("f:"):
        return source
    pref = ""
    body = source
    if ":" in source:
        maybe_prefix, body_tmp = source.split(":", 1)
        pref = f"{maybe_prefix}:"
        body = body_tmp
    if body.startswith("f:"):
        return source
    hashed_passphrase = _hash_string(obfuscate_passphrase)
    out = _hash_string(f"{hashed_passphrase}:{normalized}")
    return f"{pref}f:{out}"


def cmd_list(args):
    q = {
        "selector": {},
        "limit": args.limit,
        "fields": ["_id", "_rev", "type", "path", "mtime", "deleted"],
    }
    if args.type:
        q["selector"]["type"] = args.type
    result = _request(_url(args.url, args.db, suffix="/_find"), args.user, args.password, "POST", q)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_get(args):
    result = _request(_url(args.url, args.db, args.id), args.user, args.password)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_backup_all(args):
    result = _request(_url(args.url, args.db, suffix="/_all_docs?include_docs=true"), args.user, args.password)
    out_path = pathlib.Path(args.out)
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Backup written: {out_path}")


def _coerce_value(value: str):
    if value == "null":
        return None
    if value == "true":
        return True
    if value == "false":
        return False
    try:
        if value.isdigit() or (value.startswith("-") and value[1:].isdigit()):
            return int(value)
        return float(value)
    except ValueError:
        return value


def _set_path(obj: dict, key: str, value):
    parts = key.split(".")
    cur = obj
    for p in parts[:-1]:
        if p not in cur or not isinstance(cur[p], dict):
            cur[p] = {}
        cur = cur[p]
    cur[parts[-1]] = value


def cmd_patch(args):
    doc = _request(_url(args.url, args.db, args.id), args.user, args.password)
    for kv in args.set:
        if "=" not in kv:
            raise RuntimeError(f"Invalid --set value: {kv}; expected key=value")
        k, v = kv.split("=", 1)
        _set_path(doc, k, _coerce_value(v))
    put_result = _request(_url(args.url, args.db, args.id), args.user, args.password, "PUT", doc)
    print(json.dumps(put_result, ensure_ascii=False, indent=2))


def cmd_delete(args):
    doc = _request(_url(args.url, args.db, args.id), args.user, args.password)
    target = _url(args.url, args.db, args.id) + f"?rev={urllib.parse.quote(doc['_rev'], safe='')}"
    result = _request(target, args.user, args.password, "DELETE")
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_path2id(args):
    result = path2id(args.path, args.case_insensitive, args.obfuscate_passphrase)
    print(result)


def build_parser():
    p = argparse.ArgumentParser(description="Operate Obsidian LiveSync CouchDB docs safely.")
    sub = p.add_subparsers(dest="cmd", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--url", required=True, help="CouchDB base URL, e.g. http://127.0.0.1:5984")
    common.add_argument("--user", required=True)
    common.add_argument("--password", required=True)
    common.add_argument("--db", required=True)

    p_list = sub.add_parser("list", parents=[common], help="List docs via _find.")
    p_list.add_argument("--type", help="Filter by type (plain/newnote/leaf/...).")
    p_list.add_argument("--limit", type=int, default=20)
    p_list.set_defaults(func=cmd_list)

    p_get = sub.add_parser("get", parents=[common], help="Get one doc by id.")
    p_get.add_argument("--id", required=True)
    p_get.set_defaults(func=cmd_get)

    p_bak = sub.add_parser("backup-all", parents=[common], help="Backup all docs with include_docs=true.")
    p_bak.add_argument("--out", required=True, help="Output JSON file path.")
    p_bak.set_defaults(func=cmd_backup_all)

    p_patch = sub.add_parser("patch", parents=[common], help="Patch a doc with key=value fields.")
    p_patch.add_argument("--id", required=True)
    p_patch.add_argument("--set", action="append", required=True, help="Dot path key=value; repeatable.")
    p_patch.set_defaults(func=cmd_patch)

    p_del = sub.add_parser("delete", parents=[common], help="Delete by id with latest _rev.")
    p_del.add_argument("--id", required=True)
    p_del.set_defaults(func=cmd_delete)

    p_id = sub.add_parser("path2id", help="Compute LiveSync _id from Obsidian path.")
    p_id.add_argument("--path", required=True)
    p_id.add_argument("--case-insensitive", action="store_true")
    p_id.add_argument("--obfuscate-passphrase", help="Set when path obfuscation is enabled.")
    p_id.set_defaults(func=cmd_path2id)
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
