"""Run inside the portable path mappings. Never calls device methods."""
import hashlib,importlib.util,json,pathlib,subprocess,tempfile
root=pathlib.Path('/mnt/c/Users/Jayden Le/Desktop/aircomp-regret-pluto')
transport=root/'candidate/rx_dma_v12/rf_preparation/runtime/root_transport_major13_v2.py'
spec=importlib.util.spec_from_file_location('portable_transport_check',transport)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
flight=json.loads((root/'.probe/rx12/mu_sweep_100_20260915/b01_mu35/runtime_package_v2/flight_manifest.json').read_text())
review=root/'docs/results/mu_sweep_stability_audit_2026-09-15/procscan_v2/INDEPENDENT_PROC_SCAN_REVIEW.json'
flight['procscan_review']={'path':str(review),'bytes':review.stat().st_size,'sha256':hashlib.sha256(review.read_bytes()).hexdigest()}
module.RootTransport(flight,pathlib.Path(flight['stage1_prepare_node']['path']),pathlib.Path(flight['pty_ssh']['path']))
compiler='/home/jayden/armv7-eabihf--glibc--stable/bin/arm-buildroot-linux-gnueabihf-gcc'
with tempfile.TemporaryDirectory(prefix='pluto-portable-compile-') as temporary:
 binary=pathlib.Path(temporary)/'helper.arm'
 source=root/'candidate/rx_dma_v12/rf_live_support/objective_models_v1/objective_fixed_loop_file_helper_v1.c'
 subprocess.run([compiler,'-std=c99','-O2',str(source),'-L/home/jayden/.cache/aircomp_pluto_link','-l:libiio.so.0','-l:libad9361.so.0','-lm','-lpthread','-o',str(binary)],check=True)
 header=binary.read_bytes()[:20]
 if header[:4]!=b'\x7fELF' or int.from_bytes(header[18:20],'little')!=40:raise ValueError('Expected ARM ELF output')
print('Transport integrity checks and ARM compile/link passed; no devices contacted.')
