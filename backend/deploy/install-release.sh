#!/usr/bin/env bash
set -euo pipefail
myleafy_environment=${1:?environment}; myleafy_commit=${2:?commit}; myleafy_archive=${3:?archive}; myleafy_hash=${4:?sha256}
[[ "$myleafy_environment" == staging || "$myleafy_environment" == production ]]
[[ "$myleafy_commit" =~ ^[a-f0-9]{40}$ && "$myleafy_hash" =~ ^[a-f0-9]{64}$ ]]
[[ $(sha256sum "$myleafy_archive" | cut -d' ' -f1) == "$myleafy_hash" ]]
exec 9>"/run/lock/myleafy-${myleafy_environment}.lock"; flock -n 9
myleafy_root="/opt/myleafy/${myleafy_environment}"
myleafy_release="${myleafy_root}/releases/${myleafy_commit}"
[[ ! -e "$myleafy_release" ]]
[[ -f "/etc/myleafy/${myleafy_environment}.env" ]]
[[ -f "/var/lib/myleafy/${myleafy_environment}/database.sqlite" ]]
# Prevent archive traversal and links before extraction, including parent symlinks.
python3 - "$myleafy_archive" <<'PY'
import sys,tarfile,pathlib
with tarfile.open(sys.argv[1]) as archive:
 for member in archive.getmembers():
  p=pathlib.PurePosixPath(member.name)
  if p.is_absolute() or '..' in p.parts or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):raise SystemExit('Unsafe release archive')
PY
mkdir "$myleafy_release"
tar -xzf "$myleafy_archive" -C "$myleafy_release" --no-same-owner
/usr/local/bin/node "$myleafy_release/backend/scripts/ecs/verify-release.mjs" "$myleafy_release" "$myleafy_commit"
cd "$myleafy_release/backend"
/usr/local/bin/npm ci --omit=dev --registry=https://registry.npmjs.org --no-audit --no-fund
# All production activations require the workflow's acceptance artifact and gate.
if [[ "$myleafy_environment" == production ]]; then
  [[ "${MYLEAFY_PRODUCTION_ACCEPTED:-}" == "$myleafy_commit" ]]
  [[ -f /etc/myleafy/filing-approved ]]
fi
if systemctl is-active --quiet "myleafy@${myleafy_environment}"; then
  systemctl stop "myleafy@${myleafy_environment}"
  if ! /opt/myleafy/"$myleafy_environment"/current/backend/deploy/backup.sh "$myleafy_environment" --lock-held; then
    systemctl start "myleafy@${myleafy_environment}"; exit 1
  fi
fi
/usr/local/bin/node scripts/ecs/migrate.mjs "/var/lib/myleafy/${myleafy_environment}/database.sqlite"
chown -R myleafy:myleafy "/var/lib/myleafy/${myleafy_environment}"
# Write only the release identity; all live secrets stay in the existing env file.
python3 - "$myleafy_environment" "$myleafy_commit" <<'PY'
from pathlib import Path
import sys,json
p=Path('/etc/myleafy')/(sys.argv[1]+'.env')
s=p.read_text().splitlines();s=[v for v in s if not v.startswith('DEPLOY_COMMIT=')];s.append('DEPLOY_COMMIT='+sys.argv[2]);p.write_text('\n'.join(s)+'\n');p.chmod(0o600)
Path('..','site','dist','release.json').write_text(json.dumps({'environment':sys.argv[1],'commit':sys.argv[2]})+'\n')
PY
myleafy_previous=$(readlink "${myleafy_root}/current" || true)
ln -s "$myleafy_release" "${myleafy_root}/current.new"
mv -Tf "${myleafy_root}/current.new" "${myleafy_root}/current"
install -m 644 deploy/myleafy@.service deploy/myleafy-backup@.service deploy/myleafy-backup@.timer /etc/systemd/system/
systemctl daemon-reload
systemctl start "myleafy@${myleafy_environment}"
myleafy_port=3101; myleafy_host=api-staging.myleafy.space
if [[ "$myleafy_environment" == production ]]; then myleafy_port=3100; myleafy_host=api.myleafy.space; fi
# A restore stays behind maintenance until its own verification is accepted.
for myleafy_attempt in {1..20}; do
  if curl -fsS -H "Host: $myleafy_host" "http://127.0.0.1:${myleafy_port}/health" >"${myleafy_root}/health.json"; then break; fi
  sleep 1
done
/usr/local/bin/node --input-type=module - "$myleafy_root" "$myleafy_environment" "$myleafy_commit" "$myleafy_previous" <<'JS'
import {readFileSync,writeFileSync} from 'node:fs';
const [root,environment,commit,previous]=process.argv.slice(2),health=JSON.parse(readFileSync(root+'/health.json','utf8'));
if(health.status!=='ok'||health.environment!==environment||health.commit!==commit)throw new Error('Release health identity failed; database is not automatically rolled back');
writeFileSync(root+'/deployment.json',JSON.stringify({environment,commit,previous,success:true,checkedAt:new Date().toISOString(),checks:['artifact-sha256','release-files','database-migrations','health-commit']},null,2),{mode:0o600});
JS
