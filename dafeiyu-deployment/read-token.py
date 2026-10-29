import argparse
import json
import pathlib
import pwd

parser = argparse.ArgumentParser()
parser.add_argument('kind', choices=['webui-token', 'onebot-token'])
parser.add_argument('--runtime-user', default='dafeiyu')
args = parser.parse_args()
root = pathlib.Path(pwd.getpwnam(args.runtime_user).pw_dir) / 'qq-runtime/config'
if args.kind == 'webui-token':
    print(json.loads((root / 'webui.json').read_text())['token'])
else:
    print(json.loads((root / 'onebot11.json').read_text())['network']['websocketServers'][0]['token'])
