// Minimal WASI shim: enough to run a Shopify Function (shopify_function 0.8, stdin/stdout JSON).
// Same code works in the browser — only fs is Node-specific here.
import fs from 'fs';
export async function runFunction(wasmBytes, exportName, inputObj) {
  const input = new TextEncoder().encode(JSON.stringify(inputObj));
  let inPos = 0, out = [], err = [], mem;
  class Exit extends Error { constructor(c){ super('exit '+c); this.code=c; } }
  const v = () => new DataView(mem.buffer);
  const wasi = {
    random_get(ptr, len){ crypto.getRandomValues(new Uint8Array(mem.buffer, ptr, len)); return 0; },
    environ_get(){ return 0; },
    environ_sizes_get(cPtr, sPtr){ v().setUint32(cPtr,0,true); v().setUint32(sPtr,0,true); return 0; },
    fd_read(fd, iovs, iovsLen, nreadPtr){
      let n = 0;
      for (let i=0;i<iovsLen;i++){
        const p = v().getUint32(iovs+i*8,true), l = v().getUint32(iovs+i*8+4,true);
        const chunk = input.subarray(inPos, inPos+l);
        new Uint8Array(mem.buffer, p, chunk.length).set(chunk); inPos += chunk.length; n += chunk.length;
        if (chunk.length < l) break;
      }
      v().setUint32(nreadPtr, n, true); return 0;
    },
    fd_write(fd, iovs, iovsLen, nwPtr){
      let n = 0;
      for (let i=0;i<iovsLen;i++){
        const p = v().getUint32(iovs+i*8,true), l = v().getUint32(iovs+i*8+4,true);
        (fd===1?out:err).push(new Uint8Array(mem.buffer, p, l).slice()); n += l;
      }
      v().setUint32(nwPtr, n, true); return 0;
    },
    proc_exit(code){ throw new Exit(code); },
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { wasi_snapshot_preview1: wasi });
  mem = instance.exports.memory;
  const t0 = performance.now();
  try { instance.exports[exportName](); } catch (e) { if(!(e instanceof Exit)) { const d=new TextDecoder(); console.error("STDERR:", err.map(x=>d.decode(x)).join("")); } if (!(e instanceof Exit) || e.code !== 0) { if(!(e instanceof Exit)) throw e; } }
  const dec = b => new TextDecoder().decode(new Uint8Array(b.flatMap(x=>[...x])));
  return { ms: performance.now()-t0, stdout: dec(out), stderr: dec(err) };
}
if (import.meta.url === `file://${process.argv[1]}` && process.argv[2]) {
  const r = await runFunction(fs.readFileSync(process.argv[2]), process.argv[3], JSON.parse(fs.readFileSync(process.argv[4],'utf8')));
  console.log('ms', r.ms.toFixed(2)); console.log('stdout', r.stdout.slice(0,1500)); console.log('stderr', r.stderr.slice(0,800));
}
