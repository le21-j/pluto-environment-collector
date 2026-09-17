"""Extract immutable assets once; never reset an active session registry."""
import hashlib,json,pathlib,tarfile,sys
HERE=pathlib.Path(__file__).resolve().parent
destination=HERE/'.runtime'
update='--update' in sys.argv
if destination.exists() and not update:
 raise SystemExit('Runtime already exists. Refusing to reset collection/session state. Use collect.py --check.')
assets=json.loads((HERE/'assets.json').read_text())
for name,digest in assets.items():
 p=HERE/name
 if not p.exists():raise SystemExit('Missing '+name+'. Download the matching release assets first (README).')
 digest_actual=hashlib.sha256()
 with p.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):digest_actual.update(block)
 if digest_actual.hexdigest()!=digest:raise SystemExit('Checksum mismatch: '+name)
destination.mkdir(exist_ok=update)
for name in assets:
 if update and name!='fixed-pure-support.tar.gz':continue
 with tarfile.open(HERE/name) as archive:
  for member in archive.getmembers():
   target=(destination/member.name).resolve()
   if not target.is_relative_to(destination):raise ValueError('Unsafe archive path')
   if member.islnk() or member.issym():
    link=(target.parent/member.linkname).resolve() if member.issym() else (destination/member.linkname).resolve()
    if not link.is_relative_to(destination):raise ValueError('Unsafe archive link')
  if update:
   for member in archive.getmembers():
    target=destination/member.name
    if target.exists() and member.isfile():
     with archive.extractfile(member) as stream:
      expected=hashlib.sha256(stream.read()).digest()
     if hashlib.sha256(target.read_bytes()).digest()!=expected:raise ValueError('Refusing to overwrite changed runtime file: '+member.name)
     continue
    archive.extract(member,destination)
  else:archive.extractall(destination)
print('Runtime extracted. State persists in .runtime; do not delete it after collection.')
