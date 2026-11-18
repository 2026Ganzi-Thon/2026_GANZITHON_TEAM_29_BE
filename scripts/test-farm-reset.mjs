import assert from 'node:assert/strict'
import { execFile, execFileSync } from 'node:child_process'
import { promisify } from 'node:util'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const status=JSON.parse(execFileSync('npx',['supabase','status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}))
assert.equal(new URL(status.API_URL).hostname,'127.0.0.1','Reset integration is local only')
const project=readFileSync(new URL('../supabase/config.toml',import.meta.url),'utf8').match(/^project_id\s*=\s*"([^"]+)"/m)?.[1]
assert.ok(project)
const container=`supabase_db_${project}`
const sqlArgs=q=>['exec',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-c',q]
const sql=q=>execFileSync('docker',sqlArgs(q),{stdio:['ignore','pipe','pipe']})
const asyncSql=q=>promisify(execFile)('docker',sqlArgs(q))
const clients=[], ids=[]
const run=randomUUID(), password=`LocalReset-${randomUUID()}-Aa1!`
const crop='10000000-0000-4000-8000-000000000001'
async function rpc(c,name,args){const r=await c.rpc(name,args);assert.equal(r.error,null,`${name}: ${r.error?.code}`);return r.data}
async function rows(query){const r=await query;assert.equal(r.error,null);return r.data}
async function signup(label){
  const c=createClient(status.API_URL,status.PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});clients.push(c)
  const r=await c.auth.signUp({email:`reset-${label}-${run}@test.local`,password,options:{data:{nickname:`초기화${label}`}}})
  assert.equal(r.error,null);assert.ok(r.data.session);ids.push(r.data.user.id)
  return {c,id:r.data.user.id}
}
try{
  const a=await signup('a'),b=await signup('b')
  a.farm=await rpc(a.c,'ensure_farm');b.farm=await rpc(b.c,'ensure_farm')
  await rpc(a.c,'complete_onboarding');await rpc(b.c,'complete_onboarding')
  const profile=await rpc(a.c,'get_my_profile')
  const start=()=>rpc(a.c,'start_focus',{p_plot_id:a.farm[0].plot_id,p_crop_id:crop})
  const reset=()=>rpc(a.c,'reset_farm_history')
  const ready=async()=>{const s=await start();sql(`update public.focus_sessions set started_at=clock_timestamp()-interval '601 seconds' where id='${s.session_id}' and user_id='${a.id}'`);await rpc(a.c,'finalize_my_focus');sql(`update public.focus_sessions set auto_harvest_at=clock_timestamp()+interval '1 hour' where id='${s.session_id}' and user_id='${a.id}'`);return s}
  const foreign=await rpc(b.c,'start_focus',{p_plot_id:b.farm[0].plot_id,p_crop_id:crop})
  let s=await start();const token=(await rpc(a.c,'preview_stop_focus',{p_session_id:s.session_id})).stop_token
  await rpc(a.c,'pause_focus',{p_session_id:s.session_id})
  sql(`insert into private.overwork_notices values ('${a.id}',current_date,now())`)
  assert.deepEqual(await reset(),{success:true})
  assert.deepEqual(await rpc(a.c,'get_my_profile'),profile)
  assert.deepEqual(await rpc(a.c,'ensure_farm'),a.farm)
  assert.ok((await rpc(a.c,'get_my_farm')).every(x=>x.farm_status==='empty'&&x.session_id===null))
  assert.equal((await rpc(a.c,'get_active_focus')).session,null)
  assert.equal((await a.c.auth.getUser()).data.user.id,a.id)
  assert.equal((await a.c.auth.getSession()).data.session.user.id,a.id)
  for(const p of ['today','week','all']){
    const h=await rpc(a.c,'get_focus_history',{p_period:p})
    assert.deepEqual(h.summary,{focused_seconds:0,seed_count:0,harvest_count:0})
    assert.equal(h.capabilities.harvest_count,true)
    assert.equal(h.items.length,p==='today'?1:p==='week'?7:0)
  }
  assert.equal((await a.c.rpc('confirm_stop_focus',{p_stop_token:token})).error?.details,'STOP_TOKEN_NOT_FOUND')
  assert.equal((await rpc(b.c,'get_active_focus')).session.session_id,foreign.session_id)
  assert.deepEqual(await rows(a.c.from('focus_sessions').select('id').eq('user_id',b.id)),[])
  const anonymous=createClient(status.API_URL,status.PUBLISHABLE_KEY,{auth:{persistSession:false}})
  assert.equal((await anonymous.rpc('reset_farm_history')).error?.code,'42501')

  // Both orderings are legal; unrelated errors (including deadlock) are not.
  async function race(name,args,allowed=[]){
    const results=await Promise.all([a.c.rpc('reset_farm_history'),a.c.rpc(name,args)])
    assert.equal(results[0].error,null)
    if(results[1].error)assert.ok(allowed.includes(results[1].error.details),`${name}: ${results[1].error.code}/${results[1].error.details}`)
    await reset()
    assert.deepEqual(await rows(a.c.from('focus_sessions').select('id')),[])
  }
  await race('reset_farm_history')
  await race('start_focus',{p_plot_id:a.farm[0].plot_id,p_crop_id:crop})
  s=await start();await race('pause_focus',{p_session_id:s.session_id},['SESSION_NOT_FOUND'])
  s=await start();await rpc(a.c,'pause_focus',{p_session_id:s.session_id});await race('resume_focus',{p_session_id:s.session_id},['SESSION_NOT_FOUND'])
  await start();await race('finalize_my_focus')
  s=await start();const p=await rpc(a.c,'preview_stop_focus',{p_session_id:s.session_id});await race('confirm_stop_focus',{p_stop_token:p.stop_token},['STOP_TOKEN_NOT_FOUND'])
  s=await ready();await race('harvest_crop',{p_session_id:s.session_id},['SESSION_NOT_FOUND'])
  s=await ready();let h=await rpc(a.c,'harvest_crop',{p_session_id:s.session_id});await race('save_harvest_note',{p_harvest_id:h.harvest_id,p_note:'동시 메모'},['HARVEST_NOT_FOUND'])
  s=await ready();h=await rpc(a.c,'harvest_crop',{p_session_id:s.session_id});await race('start_rest',{p_harvest_id:h.harvest_id},['HARVEST_NOT_FOUND'])
  s=await start();await race('claim_overwork_notice',{p_session_id:s.session_id})
  s=await ready();sql(`update public.focus_sessions set auto_harvest_at=clock_timestamp()-interval '1 minute' where id='${s.session_id}' and user_id='${a.id}'`)
  const worker=asyncSql('select public.process_due_harvests()')
  await reset();await worker
  assert.deepEqual(await rows(a.c.from('harvests').select('id')),[])
  assert.equal((await rpc(b.c,'get_active_focus')).session.session_id,foreign.session_id)
  console.log('Farm reset SDK: PASS (auth/plots preserved, zero history, isolation, token invalidation, concurrent reset/start/pause/stop/harvest/note/rest/claim/worker)')
}finally{
  for(const c of clients)await c.auth.signOut().catch(()=>{})
  for(const id of ids){assert.match(id,/^[0-9a-f-]{36}$/);sql(`delete from auth.users where id='${id}'`)}
}
