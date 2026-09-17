"""Print the latest retained collection failure; never contacts radios."""
import json,pathlib
root=pathlib.Path(__file__).resolve().parent
base=root/'.runtime/mnt/c/Users/Jayden Le/Desktop/aircomp-regret-pluto/.probe/rx12/fixed_pure_environments'
runs=[p for p in base.glob('*') if p.is_dir()]
if not runs:raise SystemExit('No retained fixed-mu attempts found in this clone.')
run=max(runs,key=lambda p:p.stat().st_mtime_ns)
print('Latest attempt:',run.name)
identity=run/'initial_identity/result.json'
if identity.exists():
 result=json.loads(identity.read_text())
 print('All identities verified:',result.get('all_identities_verified'))
 for node in result.get('nodes',[]):
  print('\n'+str(node.get('node'))+' @ '+str(node.get('ip')))
  for k in ['identity_verified','returncode','serial','boot_id','manager','version','active_programs','error']:
   if k in node:print('  '+k+': '+str(node[k]))
  if not node.get('identity_verified'):
   for k in ('stderr','stdout'):
    if node.get(k):print('  '+k+':\n'+node[k][-5000:])
else:
 print('No initial identity result exists.')
 for p in sorted(run.glob('*initial_identity.stderr')):
  print(p.name+':\n'+p.read_text(errors='replace')[-5000:])
failure=run/'ORCHESTRATION_FAILURE.json'
if failure.exists():print('\nFailure:',json.loads(failure.read_text()).get('failure'))
print('\nRead-only log inspection; no radio contact, allocation or RF transmission.')
