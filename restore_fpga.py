"""Sequential, RAM-only v8-to-v13 restoration with fresh identity and watchdog."""
import argparse,fcntl,hashlib,json,os,pathlib,re,subprocess,sys,time,uuid,tempfile
from datetime import datetime,timezone
HERE=pathlib.Path(__file__).resolve().parent
SHA='b33569b289fe3c8feaa09e40f41076862e1297c46dd1f85972305593bc646b59'
NODES={'es':('192.168.9.9','1044737ac3180015f0ff3300fb12e035cb'),'ed1':('192.168.5.5','104473f4a313000a160009001da4d39b96'),'ed2':('192.168.7.7','104473308d1600121c001c00c8d02cc615'),'ed3':('192.168.6.6','104473308d160004ebff1e000bfe2c7b36'),'ed4':('192.168.4.4','10447318ac0f0011fcff34002b8c17c89d')}
SNAPSHOT=r'''set -e
printf 'SERIAL='; cat /etc/serial
printf 'BOOT='; cat /proc/sys/kernel/random/boot_id
printf 'MANAGER='; cat /sys/class/fpga_manager/fpga0/state
printf 'FLAGS='; cat /sys/class/fpga_manager/fpga0/flags
test "$(readlink -f /sys/bus/platform/devices/7c480000.aircomp/driver)" = /sys/bus/platform/drivers/uio_pdrv_genirq
printf 'VERSION='; devmem 0x7c480000 32
printf 'FCLK3='; devmem 0xF80001A0 32
printf 'IO_PLL='; devmem 0xF8000108 32
for proc in /proc/[0-9]*; do
 test "${proc##*/}" != "$$" || continue
 name=$(cat "$proc/comm" 2>/dev/null) || continue
 case "$name" in aircomp_*|ring_probe|arc3_*prepare*) printf 'ACTIVE=%s\n' "$name";; esac
 cmd=$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null) || continue
 case "$cmd" in *lab_v13_*|*rx12_v13_*load*) printf 'ACTIVE=fpga_loader\n';; esac
done
for pair in '7c480000.aircomp uio_pdrv_genirq' '79024000.cf-ad9361-dds-core-lpc cf_axi_dds' '79020000.cf-ad9361-lpc cf_axi_adc' '7c400000.dma dma-axi-dmac' '7c420000.dma dma-axi-dmac'; do
 set -- $pair; printf 'BINDING=%s:%s\n' "$1" "$(readlink -f /sys/bus/platform/devices/$1/driver)"
done
printf 'IIOD='; cat /var/run/iiod.pid
printf 'UDC='; cat /sys/kernel/config/usb_gadget/composite_gadget/UDC
printf 'UDC_STATE='; cat /sys/class/udc/ci_hdrc.0/state
printf 'COMPLETE=1\n'
'''
def digest(data):return hashlib.sha256(data).hexdigest()
def save(path,value):
 with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,prefix='.restore-',delete=False) as stream:
  stream.write(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n');stream.flush();os.fsync(stream.fileno());temporary=stream.name
 os.replace(temporary,path)
def kv(text):
 result={}
 for line in text.splitlines():
  if '=' in line:
   key,value=line.split('=',1);result.setdefault(key,[]).append(value)
 return result
def single(values,key):
 if len(values.get(key,[]))!=1:raise RuntimeError('Missing/duplicate '+key)
 return values[key][0]
def validate(text,node,quiet=True):
 v=kv(text)
 if single(v,'SERIAL')!=NODES[node][1]:raise RuntimeError(node+': wrong Pluto serial')
 boot=single(v,'BOOT');uuid.UUID(boot)
 if single(v,'MANAGER')!='operating' or single(v,'FLAGS')!='0' or single(v,'COMPLETE')!='1':raise RuntimeError(node+': FPGA manager not ready')
 version=single(v,'VERSION').upper()
 if version not in ('0X0008DFFF','0X000DDFFF'):raise RuntimeError(node+': unsupported FPGA version '+version)
 if quiet and v.get('ACTIVE'):raise RuntimeError(node+': active application/loader; stop and inspect existing run')
 return dict(node=node,serial=NODES[node][1],boot=boot,version=version,raw=text)
def assets(root):
 manifest=json.loads((root/'fpga/manifest.json').read_text())
 for name,expected in manifest['files'].items():
  if digest((root/'fpga'/name).read_bytes())!=expected:raise RuntimeError('FPGA asset changed: '+name)
 p=root/'fpga/system_top_major13.bit.bin'
 if digest(p.read_bytes())!=SHA or p.stat().st_size!=2083744:raise RuntimeError('Incorrect manager payload')
 return manifest
class Transport:
 def __init__(self,root,logs):
  self.pty=root/'.runtime/mnt/c/Users/Jayden Le/Desktop/af-wt/consol/firmware/tools/pty_ssh.py';self.logs=logs;self.count=0
  if digest(self.pty.read_bytes())!='740dcb5c273df051ca4498f084c5bfcbdd3ce79cfebf13c82cf707237f9c1a80':raise RuntimeError('PTY helper differs from qualified loader')
 def call(self,node,mode,*args,seconds=30,required=True):
  self.count+=1;pw=os.environ.get('ROUND_PW','analog')
  command=[sys.executable,str(self.pty),mode,NODES[node][0],pw,*map(str,args),str(seconds)]
  try:
   r=subprocess.run(command,capture_output=True,text=True,timeout=seconds+20);rc=r.returncode;out=r.stdout;err=r.stderr
  except subprocess.TimeoutExpired:rc=124;out='';err='Transport timeout; no automatic redispatch'
  record=dict(node=node,mode=mode,returncode=rc,stdout=out.replace(pw,'[REDACTED]'),stderr=err.replace(pw,'[REDACTED]'))
  save(self.logs/f'{self.count:03d}_{node}_{mode}.json',record)
  if required and rc:raise RuntimeError(node+': '+mode+' failed: '+record['stderr'][-1000:]+' '+record['stdout'][-1000:]+'; see '+str(self.logs))
  return record
 def ssh(self,node,command,**kwargs):return self.call(node,'ssh',command,**kwargs)
def render(root,node,snapshot,inventory_hash,token,output):
 ns='lab_v13_'+node+'_load'
 texts=[]
 for suffix in ('load.sh','load_watchdog.sh'):
  text=(root/'fpga'/f'{node}_{suffix}').read_text()
  oldboot=re.search(r'^EXPECTED_BOOT_ID=(.+)$',text,re.M).group(1)
  text=text.replace(oldboot,snapshot['boot']).replace('0x000CDFFF','0x0008DFFF').replace('rx12_major12_to_major13_volatile_fpga_load_no_rf','lab_v8_to_v13_volatile_no_rf').replace('rx12_v13_'+node+'_load',ns)
  for key in ('PL_BINDINGS_SHA','SERVICES_SHA','BIND_ATTRS_SHA','TRANSITION_INVENTORY_SHA','TRANSITION_SNAPSHOT_SHA'):
   value=inventory_hash if key=='TRANSITION_INVENTORY_SHA' else digest(snapshot['raw'].encode())
   text=re.sub(r'^'+key+r'=.+$',key+'='+value,text,flags=re.M)
  path=output/(ns+('_watchdog' if suffix=='load_watchdog.sh' else '')+'.sh');path.write_text(text);texts.append(path)
 helper,watchdog=texts
 constants=dict(re.findall(r'^([A-Z_]+)=([^\n]+)$',helper.read_text(),re.M))
 mapping={'schema':'rx12.major13-volatile-load-input.v1','node':node,'scope':'lab_v8_to_v13_volatile_no_rf','operator_reviewed':'YES','volatile_fpga_load':'YES','candidate_payload':'YES','payload_name':constants['PAYLOAD_NAME'],'payload_sha256':SHA,'payload_bytes':'2083744','load_token':token,'device_serial':snapshot['serial'],'device_boot_id':snapshot['boot'],'helper_sha256':digest(helper.read_bytes()),'watchdog_sha256':digest(watchdog.read_bytes()),'watchdog_seconds':'180','backup_manifest_sha256':digest(b'Watchdog reboots existing persistent firmware; no flash backup or persistent write is performed.')}
 for field,key in {'candidate_review_manifest_sha256':'CANDIDATE_REVIEW_MANIFEST_SHA','candidate_source_manifest_sha256':'CANDIDATE_SOURCE_MANIFEST_SHA','candidate_xdc_sha256':'CANDIDATE_XDC_SHA','candidate_routed_dcp_sha256':'CANDIDATE_ROUTED_DCP_SHA','candidate_signoff_manifest_sha256':'CANDIDATE_SIGNOFF_MANIFEST_SHA','candidate_bit_sha256':'CANDIDATE_BIT_SHA','transition_inventory_manifest_sha256':'TRANSITION_INVENTORY_SHA','transition_inventory_snapshot_sha256':'TRANSITION_SNAPSHOT_SHA','pl_bindings_inventory_sha256':'PL_BINDINGS_SHA','services_inventory_sha256':'SERVICES_SHA','bind_attrs_inventory_sha256':'BIND_ATTRS_SHA'}.items():mapping[field]=constants[key]
 inp=output/(token+'.input');inp.write_text(''.join(k+'='+v+'\n' for k,v in mapping.items()))
 for path in texts:subprocess.run(['sh','-n',str(path)],check=True)
 ack='/tmp/'+ns+'_recovery_'+token+'.ack'
 launcher=output/(token+'.launch.sh')
 launcher.write_text('set -e\n'+f'test "$(cat /etc/serial)" = {snapshot["serial"]}\ntest "$(cat /proc/sys/kernel/random/boot_id)" = {snapshot["boot"]}\n'+f'nohup setsid /bin/sh /tmp/{watchdog.name} --execute --token {token} --seconds 180 --helper-sha256 {mapping["helper_sha256"]} > /tmp/{token}.watchdog.log 2>&1 < /dev/null &\n'+f'n=0; while [ ! -r {ack} ]; do n=$((n+1)); test "$n" -le 10; sleep 1; done\nexec /bin/sh /tmp/{helper.name} --execute --input /tmp/{inp.name} --watchdog /tmp/{watchdog.name} --recovery-ack {ack}\n')
 return helper,watchdog,inp,launcher,ns
def restore_all(root=HERE,transport=None,timeout=240):
 assets(root);logs=root/'fpga_restore'/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'_'+uuid.uuid4().hex[:8]);logs.mkdir(parents=True,exist_ok=False)
 t=transport or Transport(root,logs)
 state_path=root/'.fpga_restore_state.json';state=json.loads(state_path.read_text()) if state_path.exists() else {}
 snapshots={node:validate(t.ssh(node,SNAPSHOT)['stdout'],node,quiet=node not in state) for node in NODES}
 save(logs/'inventory.json',snapshots);inventory_hash=digest((logs/'inventory.json').read_bytes())
 for node,snapshot in snapshots.items():
  if node in state:
   pending=state[node]
   if pending['boot']==snapshot['boot']:raise RuntimeError(node+': previous dispatch is unresolved on this boot. Inspect '+pending['logs']+'; do not redispatch.')
   if kv(snapshot['raw']).get('ACTIVE'):raise RuntimeError(node+': active loader on new boot')
   del state[node];save(state_path,state)
  if snapshot['version']=='0X000DDFFF':print(node+': v13 already loaded; skip',flush=True);continue
  print(node+': restoring v8 → v13 (volatile)',flush=True)
  token='lab13_'+node+'_'+uuid.uuid4().hex[:16];directory=logs/node;directory.mkdir()
  helper,watchdog,inp,launcher,ns=render(root,node,snapshot,inventory_hash,token,directory)
  files=[(root/'fpga/system_top_major13.bit.bin','/lib/firmware/system_top_major13.bit.bin')]+[(p,'/tmp/'+p.name) for p in (helper,watchdog,inp,launcher)]
  for source,destination in files:t.call(node,'scp',source,destination,seconds=60)
  checks='set -e\n'+''.join(f'test "$(sha256sum {dest} | awk \'{{print $1}}\')" = {digest(src.read_bytes())}\n' for src,dest in files)
  t.ssh(node,checks)
  pre=t.ssh(node,f'/bin/sh /tmp/{helper.name} --preflight --input /tmp/{inp.name} --watchdog /tmp/{watchdog.name}',seconds=45)
  if 'ARC3_REBIND_PREFLIGHT_PASS' not in pre['stdout']:raise RuntimeError(node+': no helper preflight PASS')
  state[node]=dict(boot=snapshot['boot'],token=token,logs=str(logs),namespace=ns);save(state_path,state)
  # Record intent BEFORE dispatch. Never repeat dispatch after a transport timeout.
  save(directory/'dispatch_intent.json',state[node])
  t.ssh(node,checks+f'nohup setsid /bin/sh /tmp/{launcher.name} > /tmp/{token}.launch.log 2>&1 < /dev/null &\n',required=False)
  deadline=time.monotonic()+timeout;success=False
  while time.monotonic()<deadline:
   status=t.ssh(node,f'cat /tmp/{ns}_{token}/terminal_result; printf "WATCHDOG_BOUNDARY\\n"; cat /tmp/{ns}_recovery_{token}.result',seconds=8,required=False)
   if status['returncode']==0:
    terminal,sep,recovery=status['stdout'].partition('WATCHDOG_BOUNDARY\n');v=kv(terminal);w=kv(recovery)
    expected={'result':'PASS','token':token,'device_serial':snapshot['serial'],'device_boot_id':snapshot['boot'],'payload_sha256':SHA,'helper_sha256':digest(helper.read_bytes()),'pre_version':'0x0008DFFF','post_version':'0x000DDFFF','firmware_attr_write_completed':'1','manager_operating_after_load':'1','bind_writes_started':'1','no_rf':'YES'}
    if sep and all(v.get(k)==[val] for k,val in expected.items()) and w.get('result')==['DISARMED_ON_EXACT_PASS'] and w.get('token')==[token]:
     post=validate(t.ssh(node,SNAPSHOT)['stdout'],node,quiet=False)
     if kv(post['raw']).get('ACTIVE'):time.sleep(2);continue
     if post['boot']!=snapshot['boot'] or post['version']!='0X000DDFFF':raise RuntimeError(node+': post-load boot/version mismatch')
     save(directory/'verified_result.json',dict(post=post,terminal=terminal,watchdog=recovery));del state[node];save(state_path,state);success=True;break
   time.sleep(2)
  if not success:raise RuntimeError(node+': restore not verified; state retained, no retry. Evidence: '+str(logs))
  print(node+': v13 verified; drivers/USB restored, watchdog disarmed',flush=True)
 for node in NODES:
  post=validate(t.ssh(node,SNAPSHOT)['stdout'],node)
  if post['version']!='0X000DDFFF':raise RuntimeError(node+': fleet final version mismatch')
 print('All five Plutos verified at v13. Persistent firmware unchanged.',flush=True)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--execute',action='store_true');a=p.parse_args();assets(HERE)
 if not a.execute:print('Dry plan: verify all five serials, restore idle v8 nodes sequentially to v13 using FPGA manager and reboot watchdog, skip v13 nodes. No contact/flash/RF.');return
 lock=(HERE/'.collection.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);restore_all()
if __name__=='__main__':main()
