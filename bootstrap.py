"""Extract immutable assets once; never reset an active session registry."""
import hashlib,json,pathlib,tarfile
HERE=pathlib.Path(__file__).resolve().parent
destination=HERE/'.runtime'
if destination.exists():
 raise SystemExit('Runtime already exists. Refusing to reset collection/session state. Use collect.py --check.')
assets=json.loads((HERE/'assets.json').read_text())
for name,digest in assets.items():
 p=HERE/name
 if not p.exists():raise SystemExit('Missing '+name+'. Download the matching release assets first (README).')
 digest_actual=hashlib.sha256()
 with p.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):digest_actual.update(block)
 if digest_actual.hexdigest()!=digest:raise SystemExit('Checksum mismatch: '+name)
destination.mkdir()
for name in assets:
 with tarfile.open(HERE/name) as archive:
  for member in archive.getmembers():
   target=(destination/member.name).resolve()
   if not target.is_relative_to(destination):raise ValueError('Unsafe archive path')
   if member.islnk() or member.issym():
    link=(target.parent/member.linkname).resolve() if member.issym() else (destination/member.linkname).resolve()
    if not link.is_relative_to(destination):raise ValueError('Unsafe archive link')
  archive.extractall(destination)
print('Runtime extracted. State persists in .runtime; do not delete it after collection.')
