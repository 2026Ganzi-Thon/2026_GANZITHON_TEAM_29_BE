import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'

// Local-only, all fixtures and statistics changes are rolled back.
const project = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8').match(/^project_id\s*=\s*"([^"]+)"/m)[1]
const ids = Array.from({ length: 6 }, () => randomUUID())
const labels = ['empty', 'small_12', 'large_10000', 'multi_year_10000', 'foreign_heavy_owner_12', 'foreign_100000']
const counts = [0, 12, 10000, 10000, 12, 100000]
const fixture = ids.map((id, i) => `
insert into auth.users(id,email) values('${id}','crop-benchmark-${id}@test.local');
insert into public.farm_plots(user_id,plot_index) values('${id}',1);
insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,target_seconds,focused_seconds,record_date)
select '${id}', p.id,'10000000-0000-4000-8000-000000000001','seed_saved',now(),600,30,
current_date - (n % ${i === 3 ? 1825 : 28})::int from public.farm_plots p
cross join generate_series(1,${counts[i]}) n where p.user_id='${id}';`).join('\n')
const query = `
begin;
${fixture}
update public.crops set is_active=false where id='10000000-0000-4000-8000-000000000001';
analyze public.focus_sessions;
create function pg_temp.measure_crop(p_id uuid) returns jsonb language plpgsql as $$
declare full_plan jsonb; join_plan jsonb; payload jsonb;
begin
perform set_config('request.jwt.claim.sub',p_id::text,true);
execute 'explain (analyze,buffers,format json) select public.get_crop_history(''all'')' into full_plan;
execute format('explain (analyze,buffers,format json)
select s.record_date,s.focused_seconds,c.name,h.session_id
from public.focus_sessions s join public.crops c on c.id=s.crop_id
left join public.harvests h on h.session_id=s.id
where s.user_id=%L::uuid and s.status in (''seed_saved'',''ripe'',''harvested'')',p_id) into join_plan;
payload := public.get_crop_history('all');
return jsonb_build_object('execution_ms',full_plan->0->'Execution Time',
 'json_bytes',octet_length(payload::text),'summary',payload->'summary',
 'days',jsonb_array_length(payload->'items'),'months',jsonb_array_length(payload->'monthly'),
 'join_plan',join_plan);
end $$;
set local role authenticated;
${ids.slice(0,5).map((id, i) => `select jsonb_build_object('case','${labels[i]}','result',pg_temp.measure_crop('${id}'));`).join('\n')}
reset role;
rollback;`
const output = execFileSync('docker', ['exec', '-i', `supabase_db_${project}`, 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: query, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] })
const measurements = output.trim().split('\n').map(line => JSON.parse(line))
console.log(JSON.stringify({ environment: 'LOCAL_ONLY', other_user_sessions: 100000, measurements, cleanup: 'ROLLBACK' }, null, 2))
