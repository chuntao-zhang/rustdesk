#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RENDEZVOUS_SERVER:-}" ]]; then
  echo "RENDEZVOUS_SERVER not set, skipping custom server config"
  exit 0
fi

CONFIG_RS="libs/hbb_common/src/config.rs"
COMMON_RS="src/common.rs"

if [[ ! -f "$CONFIG_RS" ]]; then
  echo "Missing $CONFIG_RS (submodule not initialized?)"
  exit 1
fi

if [[ ! -f "$COMMON_RS" ]]; then
  echo "Missing $COMMON_RS"
  exit 1
fi

python3 <<'PY'
import os
import re
import sys

rs = os.environ["RENDEZVOUS_SERVER"]
key = os.environ.get("RS_PUB_KEY", "")
api = os.environ.get("API_SERVER", "")

config_path = "libs/hbb_common/src/config.rs"
with open(config_path, encoding="utf-8") as f:
    cfg = f.read()

cfg = re.sub(
    r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[.*?\];',
    f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{rs}"];',
    cfg,
    count=1,
)
if key:
    cfg = re.sub(
        r'pub const RS_PUB_KEY: &str = ".*?";',
        f'pub const RS_PUB_KEY: &str = "{key}";',
        cfg,
        count=1,
    )
with open(config_path, "w", encoding="utf-8") as f:
    f.write(cfg)

common_path = "src/common.rs"
with open(common_path, encoding="utf-8") as f:
    common = f.read()

if "Custom server build defaults" in common:
    print("common.rs already patched")
    sys.exit(0)

marker = "pub fn load_custom_client() {"
if marker not in common:
    print("load_custom_client() not found in common.rs", file=sys.stderr)
    sys.exit(1)

api_block = ""
if api:
    api_block = f'''
    {{
        let mut d = hbb_common::config::DEFAULT_SETTINGS.write().unwrap();
        d.insert("api-server".into(), "{api}".into());
    }}'''

insert = f'''{marker}
    // Custom server build defaults
    {{
        let mut o = hbb_common::config::OVERWRITE_SETTINGS.write().unwrap();
        o.insert("allow-auto-update".into(), "N".into());
        o.insert("enable-check-update".into(), "N".into());
    }}{api_block}'''

common = common.replace(marker, insert, 1)
with open(common_path, "w", encoding="utf-8") as f:
    f.write(common)

print(f"Applied custom server: rendezvous={rs}")
if key:
    print("Applied custom public key")
if api:
    print(f"Applied API server: {api}")
PY
