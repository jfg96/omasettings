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
    mutationTimeoutMs:30000, readTimeoutMs:15000, mutationExpectations:{},
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
  vm.runInContext(functions(source.slice(source.indexOf('  // A single scheduler'), source.indexOf('  function set(key,'))),ctx);
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
 const {c,flush,write,read,events}=harness();
 c.expectMutation(1,true,()=>c.state.hypr.blur,'Blur');
 c.run(['set','blur','true']);flush();
 assert.equal(c.applyProc.command[0],'python3');
 assert.ok(c.applyProc.command.includes('30'));
 write();read({hypr:{blur:false},hyprChanged:[]});
 let result=events.filter(e=>e[0]==='reconciled').at(-1)[1];
 assert.equal(result.success,true);assert.equal(result.accepted,false);
 assert.match(result.verificationError,/Blur did not accept/);
 assert.equal(Object.keys(c.mutationExpectations).length,0);
 c.expectMutation(2,true,()=>c.state.hypr.blur,'Blur');
 c.run(['set','blur','true']);flush();write();
 read({hypr:{blur:true},hyprChanged:[]});
 result=events.filter(e=>e[0]==='reconciled').at(-1)[1];
 assert.equal(result.accepted,true);
 console.log('PASS shared toggle verification rejects silent no-op and accepts actual value');
}
{
 const {c,flush,write,read,events}=harness();
 c.expectMutation(1,true,()=>c.state.hypr.blur,'Blur');
 c.run(['set','blur','true']);c.run(['set','shadow','true']);flush();
 write(124,'Settings operation timed out after 30s');
 assert.ok(c.applyProc.running);write();
 assert.ok(c.sliceProc.running);assert.ok(c.sliceProc.command.includes('15'));
 read({},124);
 assert.equal(c.readRunning,false);assert.equal(c.mutationRunning,false);
 assert.equal(c.mutationQueue.length,0);assert.equal(Object.keys(c.mutationExpectations).length,0);
 assert.equal(events.find(e=>e[0]==='finished')[1].timedOut,true);
 assert.ok(events.some(e=>e[0]==='readFailure' && e[1]===2));
 c.run(['set','blur','false']);flush();assert.ok(c.applyProc.running);
 write();read({hypr:{blur:false},hyprChanged:[]});
 assert.equal(c.reconciledMutationId,3);
 console.log('PASS write/read timeout releases affected controls and later requests proceed');
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
