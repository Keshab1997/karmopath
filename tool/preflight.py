#!/usr/bin/env python3
"""Cheap structural gate, NOT a replacement for Dart analysis/tests."""
from pathlib import Path
import subprocess,sys,re
r=Path(__file__).resolve().parents[1]
errors=[]
for p in ['pubspec.yaml','lib/main.dart','lib/contracts/job.dart','lib/contracts/job_feed.dart','lib/contracts/job_repository.dart','lib/contracts/user_preferences.dart','lib/contracts/app_actions.dart','lib/design_system/karmopath_theme.dart']:
 if not (r/p).is_file():errors.append('Missing '+p)
for name in subprocess.check_output(['git','ls-files'],cwd=r,text=True).splitlines():
 if re.search(r'(?:^|/)(?:secrets|drafts)/|\.(?:jks|keystore|pem|p12)$|(?:^|/)(?:key.properties|google-services.json)$',name):errors.append('Sensitive path tracked: '+name)
for p in (r/'.github/workflows').glob('*.yml'):
 if re.search(r'^  (push|pull_request|pull_request_target|schedule|delete):',p.read_text(),re.M):errors.append('Nonmanual workflow: '+p.name)
if errors:print('\n'.join(errors));sys.exit(1)
print('PASS: structural preflight only; run targeted Flutter tests separately.')
