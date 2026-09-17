"""Portable launcher retaining the exact reviewed source and provenance paths."""
import argparse,fcntl,hashlib,json,os,pathlib,shutil,subprocess,sys
HERE=pathlib.Path(__file__).resolve().parent
ROOT='/mnt/c/Users/Jayden Le/Desktop/aircomp-regret-pluto'
CODEX='/mnt/c/Users/Jayden Le/.codex/visualizations/2026/09/09/01a083fa-a885-7563-aacc-5fbfb33e1679'
p=argparse.ArgumentParser()
p.add_argument('--name',default='Lab');p.add_argument('--execute',action='store_true');p.add_argument('--check',action='store_true')
a=p.parse_args()
if a.check and a.execute:p.error('--check cannot be combined with --execute')
runtime=HERE/'.runtime'
if not runtime.is_dir():raise SystemExit('Run bash setup.sh first.')
if not shutil.which('proot'):raise SystemExit('Install proot (setup.sh).')
if a.check:
 bad=[]
 for row in json.loads((HERE/'runtime-index.json').read_text()):
  # Registry evolves only during live collection; immutable source still verifies.
  if row['path'].endswith('sahin_312ms_alias_registry.json'):continue
  f=runtime/row['path'].lstrip('/')
  if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest()!=row['sha256']:bad.append(row['path'])
 if bad:raise SystemExit('Missing/changed assets: '+json.dumps(bad))
 print('Immutable assets verified; no devices contacted.',flush=True)
lock=(HERE/'.collection.lock').open('a')
try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:raise SystemExit('Another collection is active in this checkout.')
argv=['proot','-b',str(runtime/'mnt/c')+':/mnt/c','-b',str(HERE)+':/collector']
for path in ['home/jayden/armv7-eabihf--glibc--stable','home/jayden/.cache/aircomp_pluto_link']:
 argv+=['-b',str(runtime/path)+':/'+path]
argv+=['-w','/collector']
env=dict(os.environ,MPLBACKEND='Agg',PYTHONNOUSERSITE='1')
if a.check:
 for script in ['run_objective_fixed_loop_v1.py','run_objective_fixed_loop_batch_v1.py']:
  subprocess.run(argv+['/collector/.venv/bin/python',ROOT+'/candidate/rx_dma_v12/rf_live_support/'+script,'--help'],env=env,check=True,stdout=subprocess.DEVNULL)
 print('Collector and batch imports passed.',flush=True)
 subprocess.run(argv+['/collector/.venv/bin/python','/collector/offline_check.py'],env=env,check=True)
argv+=['/collector/.venv/bin/python',ROOT+'/candidate/rx_dma_v12/rf_live_support/run_objective_fixed_loop_named_v1.py','--name',a.name,'--output-root','/collector/results']
if a.execute:argv+=['--execute']
rc=subprocess.run(argv,env=env).returncode
if a.execute:
 results=HERE/'results';results.mkdir(exist_ok=True)
 shutil.copy2(runtime/(CODEX+'/arc3_campaign/sahin_312ms_alias_registry.json').lstrip('/'),results/'session-registry-after-collection.json')
print('Result ZIPs: '+str(HERE/'results'),flush=True)
raise SystemExit(rc)
