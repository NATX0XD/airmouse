#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import json
from pathlib import Path
files={'apk':'downloads/AirMouse.apk','mac':'downloads/AirMouse-Receiver-mac.dmg','mac_zip':'downloads/AirMouse-Receiver-mac.zip','windows':'downloads/AirMouse-Receiver-windows.zip'}
out={}
for key,name in files.items():
    p=Path(name); exists=p.is_file(); n=p.stat().st_size if exists else 0
    out[key]={'path':name,'exists':exists,'size':(f'{n/1024/1024:.1f} MB' if n>1024*1024 else f'{n/1024:.0f} KB') if exists else ''}
Path('downloads/manifest.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
PY
