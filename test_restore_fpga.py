"""Offline transport/state tests; never connect to radios."""
import contextlib,io,json,pathlib,shutil,tempfile,unittest,uuid,subprocess
from unittest.mock import patch
import restore_fpga as f
class Fake:
 def __init__(self,versions=None):
  self.versions={n:(versions or {}).get(n,'0x000DDFFF') for n in f.NODES};self.calls=[];self.inputs={};self.wrong=None;self.fail_pre=False;self.bad_token=False;self.dispatches=[]
 def snapshot(self,node):
  return f'SERIAL={"foreign" if node==self.wrong else f.NODES[node][1]}\nBOOT=00000000-0000-4000-8000-000000000001\nMANAGER=operating\nFLAGS=0\nVERSION={self.versions[node]}\nCOMPLETE=1\n'
 def call(self,node,mode,*args,**kw):
  self.calls.append((node,mode,args))
  if mode=='scp' and str(args[0]).endswith('.input'):
   self.inputs[node]=dict(line.split('=',1) for line in pathlib.Path(args[0]).read_text().splitlines())
  return {'returncode':0,'stdout':'','stderr':''}
 def ssh(self,node,command,**kw):
  self.calls.append((node,'ssh',command))
  if command==f.SNAPSHOT:return {'returncode':0,'stdout':self.snapshot(node),'stderr':''}
  if '--preflight' in command:
   if self.fail_pre:raise RuntimeError('preflight fixture failure')
   return {'returncode':0,'stdout':'ARC3_REBIND_PREFLIGHT_PASS','stderr':''}
  if 'nohup setsid /bin/sh /tmp/lab13_' in command:
   self.dispatches.append(node);self.versions[node]='0x000DDFFF'
   return {'returncode':124,'stdout':'','stderr':'simulated disconnect after dispatch'}
  if 'WATCHDOG_BOUNDARY' in command:
   d=self.inputs[node];fields={'result':'PASS','token':d['load_token'],'device_serial':d['device_serial'],'device_boot_id':d['device_boot_id'],'payload_sha256':f.SHA,'helper_sha256':d['helper_sha256'],'pre_version':'0x0008DFFF','post_version':'0x000DDFFF','firmware_attr_write_completed':'1','manager_operating_after_load':'1','bind_writes_started':'1','no_rf':'YES'}
   if self.bad_token:fields['token']='foreign'
   text=''.join(k+'='+v+'\n' for k,v in fields.items())+'WATCHDOG_BOUNDARY\nresult=DISARMED_ON_EXACT_PASS\ntoken='+d['load_token']+'\n'
   return {'returncode':0,'stdout':text,'stderr':''}
  return {'returncode':0,'stdout':'','stderr':''}
class Tests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name);shutil.copytree(f.HERE/'fpga',self.root/'fpga')
 def tearDown(self):self.temp.cleanup()
 def run_restore(self,t,**kw):
  with contextlib.redirect_stdout(io.StringIO()):f.restore_all(self.root,t,**kw)
 def test_skip_all_v13_without_mutation(self):
  t=Fake();self.run_restore(t);self.assertFalse(t.dispatches);self.assertFalse(any(c[1]=='scp' for c in t.calls))
 def test_disconnect_after_dispatch_does_not_repeat(self):
  t=Fake({'es':'0x0008DFFF'});self.run_restore(t);self.assertEqual(t.dispatches,['es']);self.assertEqual(json.loads((self.root/'.fpga_restore_state.json').read_text()),{})
 def test_wrong_serial_on_last_node_blocks_all_staging(self):
  t=Fake({'es':'0x0008DFFF'});t.wrong='ed4'
  with self.assertRaises(RuntimeError):self.run_restore(t)
  self.assertFalse(any(c[1]=='scp' for c in t.calls))
 def test_unrecognized_image_blocks_staging(self):
  t=Fake({'ed1':'0x000CDFFF'})
  with self.assertRaises(RuntimeError):self.run_restore(t)
  self.assertFalse(t.dispatches)
 def test_corrupt_payload_blocks_any_contact(self):
  (self.root/'fpga/system_top_major13.bit.bin').write_bytes(b'bad');t=Fake()
  with self.assertRaises(RuntimeError):self.run_restore(t)
  self.assertFalse(t.calls)
 def test_failed_preflight_does_not_dispatch(self):
  t=Fake({'es':'0x0008DFFF'});t.fail_pre=True
  with self.assertRaises(RuntimeError):self.run_restore(t)
  self.assertFalse(t.dispatches);self.assertFalse((self.root/'.fpga_restore_state.json').exists())
 def test_unresolved_same_boot_does_not_redispatch(self):
  state={'es':dict(boot='00000000-0000-4000-8000-000000000001',logs='fixture')};f.save(self.root/'.fpga_restore_state.json',state);t=Fake({'es':'0x0008DFFF'})
  with self.assertRaisesRegex(RuntimeError,'unresolved'):self.run_restore(t)
  self.assertFalse(t.dispatches)
 def test_wrong_terminal_token_retains_state(self):
  t=Fake({'es':'0x0008DFFF'});t.bad_token=True
  with patch.object(f.time,'sleep'),patch.object(f.time,'monotonic',side_effect=[0,0,2]):
   with self.assertRaisesRegex(RuntimeError,'not verified'):self.run_restore(t,timeout=1)
  self.assertEqual(t.dispatches,['es']);self.assertIn('es',json.loads((self.root/'.fpga_restore_state.json').read_text()))
 def test_all_five_derived_scripts_are_boot_bound_and_keep_gates(self):
  for node in f.NODES:
   directory=self.root/node;directory.mkdir();snapshot=f.validate(Fake().snapshot(node),node)
   helper,watchdog,inp,launcher,ns=f.render(self.root,node,snapshot,'a'*64,'lab13_'+node+'_1234567890abcdef',directory)
   text=helper.read_text();w=watchdog.read_text()
   self.assertIn('EXPECTED_PRE_VERSION=0x0008DFFF',text);self.assertIn(snapshot['boot'],text);self.assertNotIn('0x000CDFFF',text)
   for gate in ['require_no_device_users','require_exact_iiod','validate_recovery_ack','wait_manager_operating_after_load','require_ps_clocks final','require_no_waveform']:self.assertIn(gate,text)
   self.assertIn('DISARMED_ON_EXACT_PASS',w);self.assertIn('/usr/sbin/device_reboot',w)
   for script in (helper,watchdog):subprocess.run(['sh',str(script),'--plan'],check=True,capture_output=True)
   d=dict(line.split('=',1) for line in inp.read_text().splitlines());self.assertEqual(d['helper_sha256'],f.digest(helper.read_bytes()));self.assertEqual(d['watchdog_sha256'],f.digest(watchdog.read_bytes()))
if __name__=='__main__':unittest.main()
