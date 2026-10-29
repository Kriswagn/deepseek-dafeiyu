import hashlib
import json
import os
import pwd
from pathlib import Path
import urllib.request

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
runtime_home = Path(pwd.getpwnam(os.environ.get('DAFEIYU_RUNTIME_USER', 'dafeiyu')).pw_dir)
token = json.loads((runtime_home / 'qq-runtime/config/webui.json').read_text())['token']

def request(path, body, credential=None):
    headers = {'Content-Type': 'application/json'}
    if credential:
        headers['Authorization'] = 'Bearer ' + credential
    req = urllib.request.Request('http://127.0.0.1:6099/api/' + path,
                                 headers=headers, data=json.dumps(body).encode())
    with opener.open(req, timeout=8) as response:
        return json.load(response)

auth = request('auth/login', {'hash': hashlib.sha256((token + '.napcat').encode()).hexdigest()})
if auth.get('code') != 0:
    raise RuntimeError('Local management authentication failed')
result = request('QQLogin/CheckLoginStatus', {}, auth['data']['Credential'])
if result.get('code') != 0:
    raise RuntimeError('Login status query failed')
status = result['data']
print(json.dumps({k: status.get(k) for k in ['isLogin', 'isOffline', 'loginPhase', 'coreReady']}, ensure_ascii=False))
