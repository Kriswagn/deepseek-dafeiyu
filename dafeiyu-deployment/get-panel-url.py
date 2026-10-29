import pathlib
import re

log = (pathlib.Path.home() / '.local/state/dafeiyu-deployment/panel.log').read_text()
match = re.search(r'^QQ_CONTROL_URL=(\S+)', log, re.M)
if not match:
    raise SystemExit('Panel address is not ready')
# The Windows launcher captures this locally; do not publish this output.
print(match.group(1))
