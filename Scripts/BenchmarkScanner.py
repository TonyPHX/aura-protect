#!/usr/bin/env python3
"""Manual synthetic ClamAV worker benchmark; uses harmless local fixtures only.

Runs 1/2/4/8 byte-balanced file-list clients against the bundled daemon,
with a spare daemon thread. Records first and repeat scans, daemon peak RSS, and cumulative daemon CPU time.
Official definition databases are not loaded. Results are not production speed
or memory estimates. Temporary files remain at the printed path for inspection.
"""
import tempfile, os, pathlib, subprocess, time, socket, statistics, zipfile, json
root=pathlib.Path(tempfile.mkdtemp(prefix='aura-bench-',dir='/private/tmp'))
root.mkdir(exist_ok=True)
runtime=pathlib.Path(__file__).resolve().parent.parent/'Vendor/ClamAV'
env=os.environ|{'DYLD_LIBRARY_PATH':str(runtime/'lib'),'CVD_CERTS_DIR':str(runtime/'etc/certs')}
db=root/'db'; db.mkdir(exist_ok=True)
(db/'fixture.ndb').write_text('AuraHarmlessFixture:0:*:4155524150524f5445435456414c49444154494f4e5349474e4154555245\n')
for kind in ['small','archives']:
    corpus=root/kind;corpus.mkdir(exist_ok=True)
    if kind=='small':
        for i in range(256): (corpus/f'{i}.txt').write_bytes((f'Harmless scan benchmark {i}. '.encode()*2700)[:65536])
    else:
        for i in range(24):
            with zipfile.ZipFile(corpus/f'{i}.zip','w',zipfile.ZIP_DEFLATED) as z:
                z.writestr('example.txt',(f'Harmless archive contents {i}. '.encode()*60000))
results=[]
for workers in [1,2,4,8]:
    sock=root/f'd{workers}.sock';cfg=root/f'd{workers}.conf'
    cfg.write_text(f'LocalSocket {sock}\nForeground yes\nDatabaseDirectory {db}\nMaxThreads {workers+1}\nMaxQueue 100\nLogTime yes\nAlertExceedsMax yes\nAlertEncrypted yes\nMaxScanTime 120000\n')
    with (root/f'd{workers}.log').open('w') as output:
        started=time.perf_counter()
        daemon=subprocess.Popen([str(runtime/'sbin/clamd'),f'--config-file={cfg}'],stdout=output,stderr=output,env=env)
        try:
            for _ in range(200):
                try:
                    c=socket.socket(socket.AF_UNIX);c.connect(str(sock));c.sendall(b'zPING\0');answer=c.recv(64);c.close()
                    if b'PONG' in answer:break
                except OSError:time.sleep(.05)
            else:raise RuntimeError('daemon not ready')
            startup=time.perf_counter()-started
            for kind in ['small','archives']:
                samples=[]
                groups=[[] for _ in range(workers)]
                group_bytes=[0]*workers
                for file in sorted((root/kind).iterdir()):
                    index=min(range(workers),key=lambda i:group_bytes[i])
                    groups[index].append(file)
                    group_bytes[index]+=file.stat().st_size
                lists=[]
                for index,files in enumerate(groups):
                    if not files:continue
                    filelist=root/f'{kind}-{index}.txt'
                    filelist.write_text(''.join(str(f)+'\n' for f in files))
                    lists.append(filelist)
                for _ in range(3):
                    t=time.perf_counter()
                    clients=[subprocess.Popen([str(runtime/'bin/clamdscan'),f'--config-file={cfg}',
                        '--stdout','--verbose','--no-summary',f'--file-list={filelist}'],
                        env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE) for filelist in lists]
                    for client in clients:
                        _,errors=client.communicate()
                        assert client.returncode==0,(client.returncode,errors)
                    samples.append(round(time.perf_counter()-t,4))
                results.append(dict(workers=workers,corpus=kind,median_seconds=statistics.median(samples),samples=samples,startup_seconds=round(startup,4)))
        finally:
            os.kill(daemon.pid,15);_,status,usage=os.wait4(daemon.pid,0);daemon.returncode=os.waitstatus_to_exitcode(status)
            for r in results:
                if r['workers']==workers:r['peak_daemon_memory_MB']=round(usage.ru_maxrss/1048576,1);r['daemon_cpu_seconds']=round(usage.ru_utime+usage.ru_stime,3)
(root/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
print(f"Scratch corpus and results: {root}")
