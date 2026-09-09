#!/usr/bin/env bash
# inventory.sh — one row per GitHub Actions job, with the signals the `blacksmith`
# skill classifies on and a suggested verdict it must still judge.
#
#   inventory.sh [repo-path]      # defaults to the current directory
#
# Read-only. Facts and a suggestion per job; the decision is the skill's.
# Requires git and python3 with PyYAML (`pip3 install pyyaml`).
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

cd "${1:-.}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "inventory: not a git repository — run it inside the repo you are migrating." >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"
[ -d .github/workflows ] || { echo "inventory: no .github/workflows here."; exit 0; }

python3 - <<'PY'
import datetime, fnmatch, glob, re, subprocess, sys
try:
    import yaml
except ImportError:
    sys.exit("inventory: python3 needs PyYAML — pip3 install pyyaml")

GH = re.compile(r'^(ubuntu|windows|macos)-')
BS = re.compile(r'^blacksmith-')
DORMANT_DAYS = 60

def sh(*args):
    r = subprocess.run(args, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

SLUG = sh('gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner')

def days_since_last_run(workflow_file):
    """Days since the workflow last ran, None if unknown, -1 if it never ran."""
    if not SLUG:
        return None
    out = sh('gh', 'api', f'/repos/{SLUG}/actions/workflows/{workflow_file}/runs?per_page=1',
             '-q', '.workflow_runs[0].created_at // "never"')
    if out is None:
        return None
    if out == 'never':
        return -1
    then = datetime.datetime.strptime(out, '%Y-%m-%dT%H:%M:%SZ')
    return (datetime.datetime.utcnow() - then).days

def map_label(label):
    m = re.match(r'^ubuntu-(latest|24\.04|22\.04)(?:-(\d+)-cores?)?(-arm)?$', label)
    if not m:
        return None
    ver = '2204' if m.group(1) == '22.04' else '2404'
    return f"blacksmith-{m.group(2) or '2'}vcpu-ubuntu-{ver}{m.group(3) or ''}"

def runs_on_str(v):
    if v is None: return ''
    if isinstance(v, list): return ','.join(str(i) for i in v)
    if isinstance(v, dict): return ','.join(str(i) for i in v.values())
    return str(v)

def hit(patterns, texts):
    return any(re.search(p, t, re.I) for p in patterns for t in texts if t)

files = sorted(glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'))
rows, notes, labels_needed, no_timeout = [], [], set(), []

for f in files:
    try:
        with open(f) as fh:
            wf = yaml.safe_load(fh) or {}
    except yaml.YAMLError as e:
        notes.append(f"{f}: YAML parse error: {e}")
        continue
    on = wf.get(True, wf.get('on')) or {}          # PyYAML reads a bare `on:` key as True
    if isinstance(on, str): on = {on: {}}
    if isinstance(on, list): on = {k: {} for k in on}
    self_trigger = False
    for ev in ('push', 'pull_request', 'pull_request_target'):
        cfg = on.get(ev) or {}
        for pat in (cfg.get('paths') or []) if isinstance(cfg, dict) else []:
            if fnmatch.fnmatch(f, str(pat).lstrip('/')):
                self_trigger = True
    dormant = None
    if self_trigger:
        # Listing itself in `paths:` is normal. It only matters when the workflow has
        # been dormant: the edit runs it for the first time in months, and a
        # pre-existing failure then looks like this PR's.
        d = days_since_last_run(f.split('/')[-1])
        if d is None:
            notes.append(f"{f}: triggers on its own file; dormancy unknown (no `gh` access) — check its last run before editing")
        elif d == -1 or d >= DORMANT_DAYS:
            dormant = 'never' if d == -1 else f'{d}d'
            notes.append(f"{f}: triggers on its own file and last ran {dormant} ago — editing it runs it; a pre-existing failure is not this PR's to fix")

    for jid, job in (wf.get('jobs') or {}).items():
        if not isinstance(job, dict):
            continue
        if 'uses' in job and 'runs-on' not in job:
            rows.append((f, jid, '(caller)', '', '-', '', 'CALLER',
                         f"edit lands in {str(job['uses']).split('@')[0]}"))
            continue
        runs_on = runs_on_str(job.get('runs-on'))
        steps = [s for s in (job.get('steps') or []) if isinstance(s, dict)]
        uses = [str(s.get('uses', '')) for s in steps]
        runs = [str(s.get('run', '')) for s in steps]
        withs = [str(s.get('with', '')) for s in steps]
        envs = [str(job.get('env', ''))] + [str(s.get('env', '')) for s in steps]
        cond = str(job.get('if', ''))
        container = str(job.get('container', ''))

        sig = []
        def flag(name, ok):
            if ok: sig.append(name)
            return ok

        expr = flag('runs-on-expr', '${{' in runs_on)
        self_hosted = flag('self-hosted', 'self-hosted' in runs_on)
        already = flag('blacksmith', bool(BS.match(runs_on)))
        custom = flag('custom-label', bool(runs_on) and not expr and not self_hosted
                      and not already and not GH.match(runs_on))
        docker = flag('docker-build', hit([r'docker/(setup-buildx|build-push|bake)-action',
                                          r'useblacksmith/(setup-docker-builder|build-push)'], uses)
                      or hit([r'docker (buildx )?build', r'docker compose build'], runs))
        if docker:
            flag('gha-cache', hit([r'type=gha'], withs))
            flag('registry-cache', hit([r'cache-from.*type=registry'], withs))
        toolchain = flag('toolchain', hit([r'actions/setup-(node|python|go|java|dotnet)', r'pnpm/action-setup',
                                           r'oven-sh/setup-bun', r'ruby/setup-ruby', r'rust-toolchain'], uses))
        services = flag('services', bool(job.get('services')))
        cont = flag('container', bool(container))
        playwright = flag('playwright', hit([r'playwright'], uses + runs + [container]))
        eas = flag('eas', hit([r'\beas (update|build)\b'], runs))
        flag('self-trigger', self_trigger)
        wif = flag('cloud-federation', hit([r'google-github-actions/auth', r'tremolosecurity/action-generate-oidc-jwt',
                                            r'aws-actions/configure-aws-credentials', r'azure/login'], uses))
        deploy = flag('deploy', hit([r'azure/setup-kubectl', r'azure/k8s-set-context', r'deploy-cloudrun',
                                     r'appleboy/(ssh|scp)-action', r'helm'], uses)
                      or hit([r'\bkubectl\b', r'\bhelm\b', r'gcloud (run|compute|sql|jobs)\b',
                              r'\bssh\b', r'\bscp\b', r'rollout status', r'\bkubectl\b'], runs))
        health = flag('health-check', hit([r'rollout status', r'curl[^\n]*(health|ready)', r'wait-for'], runs))
        local_cred = flag('machine-local-cred', hit([r'KUBECONFIG[\'"]?:\s*[\'"]?/', r'ci-kubeconfig'], envs))
        netcred = flag('network-cred', hit([r'wireguard', r'wg-connect', r'WG_CONFIG', r'openvpn',
                                            r'tailscale', r'headscale', r'TS_AUTHKEY'],
                                           uses + runs + envs + withs))
        gate = flag('always/failure-if', bool(re.search(r'always\(\)|failure\(\)', cond)))
        glue = flag('glue-action', hit([r'slackapi/', r'sticky-pull-request-comment', r'dorny/paths-filter',
                                        r'actions/labeler', r'cancel-workflows', r'bobheadxi/deployments',
                                        r'getsentry/action-release'], uses))
        # A toolchain *invocation* at the start of a line — not the word "test" in an echo.
        tests = any(re.search(r'^\s*(yarn|pnpm|npm|bun|npx|make|cargo|go|pytest|python3?|turbo|nx|mvn|gradle|dotnet)\b',
                              line) for r_ in runs for line in r_.splitlines())
        flag('schedule', 'schedule' in on)
        timeout = job.get('timeout-minutes')

        compute = docker or toolchain or services or cont or playwright
        if already:
            v, why = 'DONE', 'already on Blacksmith'
        elif expr:
            v, why = 'REVIEW', 'runs-on is an expression — resolve by hand'
        elif self_hosted or custom:
            v, why = 'STAY', 'self-hosted / custom label: on that hardware for a reason'
        elif dormant:
            v, why = 'REVIEW', f'self-triggering and dormant ({dormant}) — editing it runs it; expect a pre-existing failure'
        elif local_cred or netcred:
            v, why = 'STAY', 'machine-local or network-scoped credential'
        elif docker and deploy:
            v, why = 'ASK', 'fused build + deploy — split into build workflow + deploy job, or leave'
        elif docker:
            v, why = 'MIGRATE', 'image build → swap to useblacksmith/* actions, drop cache-from/to'
        elif deploy or health:
            v, why = 'STAY', 'waits on an external system; holds deploy credentials'
        elif eas:
            v, why = 'MIGRATE', 'CPU-bound bundle step; sibling deploy jobs stay'
        elif compute:
            v, why = 'MIGRATE', 'builds / runs / tests the app'
            if wif: why += ' — holds cloud-federation creds, list under "ask"'
        elif gate or glue or len(steps) <= 2:
            v, why = 'STAY', 'short glue: neither builds nor runs the app'
        elif tests:
            v, why = 'MIGRATE', "runs the app's toolchain"
        else:
            v, why = 'REVIEW', 'unclassified — read the job'

        mapped = map_label(runs_on) if v == 'MIGRATE' else None
        if v == 'MIGRATE':
            if mapped: labels_needed.add(mapped)
            else: why += f' — no automatic label map for "{runs_on}", see SKILL.md table'
            if timeout is None: no_timeout.append(f"{f}:{jid}")
        rows.append((f, jid, runs_on, mapped or '', str(timeout) if timeout is not None else '-',
                     ' '.join(sig), v, why))

print('| Workflow | Job | runs-on | → | timeout | Signals | Verdict | Reason |')
print('|---|---|---|---|---|---|---|---|')
for f, jid, ro, mapped, t, sig, v, why in rows:
    print(f"| `{f.split('/')[-1]}` | `{jid}` | `{ro}` | {('`'+mapped+'`') if mapped else ''} | {t} | {sig} | **{v}** | {why} |")

counts = {}
for r in rows: counts[r[6]] = counts.get(r[6], 0) + 1
print()
print('Summary: ' + ', '.join(f"{k} {counts[k]}" for k in ('MIGRATE', 'ASK', 'STAY', 'REVIEW', 'CALLER', 'DONE') if k in counts))
if labels_needed:
    print('Labels for .github/actionlint.yaml: ' + ', '.join(sorted(labels_needed)))
if no_timeout:
    print('MIGRATE jobs without timeout-minutes: ' + ', '.join(no_timeout))
for n in notes:
    print('Note: ' + n)
PY
