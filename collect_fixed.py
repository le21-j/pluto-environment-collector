"""Linux orchestration adapter for the unchanged fixed-mu regret learner."""
import argparse,hashlib,importlib.util,json,pathlib,sys,uuid,zipfile,math,subprocess
from datetime import datetime,timezone
ROOT=pathlib.Path('/mnt/c/Users/Jayden Le/Desktop/aircomp-regret-pluto')
SUP=ROOT/'candidate/rx_dma_v12/rf_live_support'
sys.path.insert(0,str(SUP))
import run_fixed_pure_environment_v1 as workflow
workflow.PTY=pathlib.Path('/mnt/c/Users/Jayden Le/Desktop/af-wt/consol/firmware/tools/pty_ssh.py')
workflow.wsl_command=lambda script,*args:[sys.executable,str(script),*map(str,args)]
workflow.reviewer_command=lambda raw,stage,work:[sys.executable,str(workflow.DOC/'verify_fixed_pure_environment_v1.py'),'--stage',stage,'--work',str(work),'--orchestrator',str(pathlib.Path(workflow.__file__))]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--name',default='Corridor',choices=['Corridor','Outside','corridor','outside'])
p.add_argument('--execute',action='store_true');p.add_argument('--check',action='store_true')
a=p.parse_args();environment=a.name.lower();cfg=workflow.config(environment,50.,40)
if a.check:
 workflow.frozen_precheck()
 spec=importlib.util.spec_from_file_location('fixed_pure_verifier_check',workflow.DOC/'verify_fixed_pure_environment_v1.py')
 verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
 verifier.frozen()
 verifier.rt.load(verifier.rt.LEGACY,'portable_fixed_retained_engine_check')
 subprocess.run(['wsl','-d','Ubuntu-22.04','--cd','/tmp','--exec','/home/jayden/armv7-eabihf--glibc--stable/bin/arm-buildroot-linux-gnueabihf-gcc','--version'],check=True,stdout=subprocess.DEVNULL)
 print('Fixed-mu frozen firmware, verifier and transport checks passed.',flush=True)
if not a.execute:
 print(json.dumps(dict(status='OFFLINE_FIXED_MU_REGRET_RECIPE',**cfg,learner_updates_enabled=True,device_contact=False,allocation=False,rf_tx=False),indent=2));raise SystemExit(0)
work=ROOT/'.probe/rx12/fixed_pure_environments'/(environment+'_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'_'+uuid.uuid4().hex[:8])
work.mkdir(parents=True,exist_ok=False)
args=argparse.Namespace(environment=environment,mu=50.,epochs=40,reviewer_command=None)
workflow.write(work/'ORCHESTRATION_INTENT.json',dict(**cfg,started_utc=workflow.now(),orchestrator_ref=workflow.ref(pathlib.Path(workflow.__file__)),portable_adapter_ref=workflow.ref(pathlib.Path(__file__)),user_requested_execute=True),True)
try:rc=workflow.execute_pipeline(args,work,workflow.Commands(work))
except Exception as exc:
 workflow.write(work/'ORCHESTRATION_FAILURE.json',dict(failure=str(exc),ended_utc=workflow.now(),automatic_retry=False),True)
 print('Evidence retained: '+str(work),file=sys.stderr);raise
out=pathlib.Path('/collector/results')/work.name;out.mkdir(parents=True,exist_ok=False)
analysis=workflow.read(work/'plots/analysis.json')
rows=[r for r in analysis['table'] if r['aired']==4 and r['updated']==4 and all(isinstance(r.get(k),(int,float)) and math.isfinite(r[k]) for k in ('eq4_mse','avg_utility','avg_power'))]
values={'MSE':sum(r['eq4_mse'] for r in rows)/len(rows) if rows else None,
 'Utility':sum(4*r['avg_utility'] for r in rows)/len(rows) if rows else None,
 'Power':sum(4*r['avg_power'] for r in rows)/len(rows) if rows else None}
workflow.write(work/'plots/environment_summary.json',dict(environment=environment,mu=50,epochs=40,valid_paired_epochs=len(rows),complete_horizon=analysis['complete_horizon'],means=values,utility_units='sum of four device utilities',power_units='sum of four amplitude squares',accepted=False),True)
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig,axes=plt.subplots(1,3,figsize=(11,4))
for ax,(metric,value) in zip(axes,values.items()):
 if value is not None:ax.bar([a.name],[value],color='#22833c')
 else:ax.text(.5,.5,'No valid measured epochs',transform=ax.transAxes,ha='center')
 ax.set_title(metric);ax.grid(axis='y',alpha=.2);ax.set_axisbelow(True)
fig.suptitle(f'Fixed μ = 50 · {a.name} · {len(rows)}/40 valid paired epochs')
fig.tight_layout()
for suffix in ('png','svg'):fig.savefig(work/'plots'/('environment_bars.'+suffix),dpi=180)
plt.close(fig)
archive=out/('Results_'+a.name+'.zip')
with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(work.rglob('*')):
  rel=f.relative_to(work)
  if f.is_file() and not f.is_symlink() and not any(x in rel.parts for x in ('firmware','evidence.files','__pycache__')):z.write(f,str(rel))
 z.writestr('README.txt','Fixed-mu regret learning: mu=50, 40 epochs. Full raw archives and analysis retained.\n')
print('Result ZIP: '+str(archive),flush=True)
raise SystemExit(rc)
