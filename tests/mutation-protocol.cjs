// Exercise the production QML scheduler functions with deterministic processes.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(`${__dirname}/../SettingsWindow.qml`, 'utf8');
function functions(text) {
  const out = [];
  const re = /^  function \w+\([^\n]*\) \{/gm;
  let m;
  while ((m = re.exec(text))) {
    // Top-level functions end with a two-space closing brace in this codebase.
    const end = text.indexOf('\n  }', m.index) + 4;
    out.push(text.slice(m.index, end));
  }
  return out.join('\n');
}
function harness() {
  const deferred = [];
  const events = [];
  const ctx = {
    Qt: {callLater: f => { if (!deferred.includes(f)) deferred.push(f); }},
    refreshOwed:false, readRunning:false, mutationQueue:[], activeMutation:null,
    mutationRunning:false, nextMutationId:1, completedMutations:[],
    reconciliationSlices:[], reconciliationFull:false, reconciliationGeneration:0,
    reconciledMutationId:0, readingMutations:[], readingSlices:[], settleOwed:false,
    state:{hypr:{blur:false}}, loaded:true, lastError:'', helperPath:'mock',
    mutationFinished: r => events.push(['finished', r]),
    mutationReconciled: r => events.push(['reconciled', r]),
    reconciliationFailed: id => events.push(['readFailure', id]),
    settleTimer:{running:false, restart(){this.running=true},stop(){this.running=false}},
  };
  for (const name of ['applyProc','sliceProc','stateProc']) {
    const proc = {command:[], errorText:'', outputText:''};
    let running = false;
    Object.defineProperty(proc,'running',{get:()=>running,set:v=>{
      if (v) {
        for (const other of ['applyProc','sliceProc','stateProc'])
          if (other !== name) assert.ok(!ctx[other].running, `${name} overlaps ${other}`);
        events.push([name,Array.from(proc.command)]);
      }
      running=v;
    }});
    ctx[name]=proc;
  }
  ctx.root=ctx;
  vm.createContext(ctx);
  vm.runInContext(functions(source.slice(source.indexOf('  function refresh()'), source.indexOf('  function set(key,'))),ctx);
  const flush=()=>{while(deferred.length) deferred.shift()()};
  const write=(code=0,error='',status=0)=>{
    ctx.applyProc.running=false;
    ctx.applyProc.errorText=error;
    ctx.finishMutation(code,status); flush();
  };
  const read=(part,code=0)=>{
    const full=ctx.stateProc.running;
    ctx[full?'stateProc':'sliceProc'].running=false;
    ctx.finishRead(full,code,0,typeof part==='string'?part:JSON.stringify(part),'');flush();
  };
  return {c:ctx,events,flush,write,read};
}
{
 const {c,events,flush,write,read}=harness();
 c.run(['set','blur','true']); c.run(['bar','spacer','size','left','0','42']); flush();
 assert.equal(c.nextMutationId,3);
 write(); assert.ok(c.applyProc.running); assert.ok(!c.sliceProc.running);
 write(); assert.ok(c.sliceProc.running);
 assert.deepEqual(Array.from(c.readingSlices),['hypr','hyprChanged','bar']);
 read({hypr:{blur:true},hyprChanged:['blur'],bar:{}});
 assert.equal(c.reconciliationGeneration,1); assert.equal(c.reconciledMutationId,2);
 assert.ok(c.settleTimer.running);
 assert.deepEqual(events.filter(e=>/Proc$/.test(e[0])).map(e=>e[0]),['applyProc','applyProc','sliceProc']);
 console.log('PASS ordered writes, union, single read, delayed settle');
}
{
 const {c,flush,write,read}=harness();
 c.run(['set','blur','true']);flush();write(7);
 assert.match(c.lastError,/exit 7/);
 read({hypr:{blur:false},hyprChanged:[]});
 assert.equal(c.reconciliationGeneration,1);assert.equal(c.state.hypr.blur,false);
 c.run(['set','blur','true']);flush();write();
 read({hypr:{blur:false},hyprChanged:[]});
 assert.equal(c.reconciliationGeneration,2);
 console.log('PASS failure without stderr and successful no-op reconcile unchanged state');
}
{
 const {c,flush,write,read,events}=harness();
 c.refresh();c.run(['set','blur','true']);flush();assert.ok(!c.applyProc.running);
 read({hypr:{blur:false}});assert.ok(c.applyProc.running);
 write(); const id=c.nextMutationId;
 c.run(['audio','mute','output','on']);flush();assert.ok(!c.applyProc.running);
 read({hypr:{blur:true},hyprChanged:['blur']});
 assert.ok(c.reconciledMutationId<id);assert.ok(c.applyProc.running);
 write(9,'same error');read('bad json');assert.equal(c.reconciliationGeneration,1);
 assert.ok(events.some(e=>e[0]==='readFailure' && e[1]===id));
 assert.equal(events.at(-1)[1].reconciled,false);
 assert.ok(c.settleTimer.running);
 console.log('PASS writes wait for reads; old read cannot acknowledge new request; invalid read releases only its own rows');
}
{
 const {c,flush,write,read}=harness();
 c.run(['set','blur','true']);flush();write(4,'same error');
 c.run(['set','snap','true']);flush(); // waits for the first reconciliation
 read({hypr:{blur:false},hyprChanged:[]});
 assert.equal(c.applyProc.errorText,'');write(4,'same error');
 read({hypr:{blur:false},hyprChanged:[]});
 assert.equal(c.reconciledMutationId,2);assert.equal(c.lastError,'same error');
 c.run(['set','theme','example']);flush();write();assert.ok(c.stateProc.running);
 read({hypr:{},groups:{}});assert.equal(c.reconciliationGeneration,3);
 assert.ok(!c.settleTimer.running);
 console.log('PASS repeated identical failures; per-command stderr reset; unknown slices use one full reconciliation');
}
