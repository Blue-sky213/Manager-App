-- Noir Manager · ระบบบัญชี + ซิงก์ (รอบ 16)
-- วิธีใช้: Supabase › SQL Editor › New query › วางทั้งไฟล์ › Run (รันซ้ำได้ ไม่พัง)

-- 1) ตารางเดียวเก็บทุกอย่าง: 1 แถว = 1 รายการในแอป (งาน, วิชา, เช็กอิน …)
create table if not exists public.sync_rows (
  user_id    uuid   not null default auth.uid() references auth.users(id) on delete cascade,
  tbl        text   not null,               -- ชื่อตารางในแอป เช่น activity
  row_id     text   not null,               -- รหัสกลางของรายการ (เหมือนกันทุกเครื่อง)
  vals       jsonb  not null default '{}',  -- ค่าแต่ละช่อง
  stamps     jsonb  not null default '{}',  -- เวลาที่กดแก้แต่ละช่อง (ms)
  deleted_at bigint,                        -- ลบเมื่อไหร่ · null = ยังอยู่
  device     text,                          -- เครื่องที่ส่งล่าสุด
  rev        bigint not null default 0,     -- ลำดับการเปลี่ยน (ดึงเฉพาะที่ใหม่กว่า)
  updated_at timestamptz not null default now(),
  primary key (user_id, tbl, row_id)
);
create index if not exists sync_rows_rev on public.sync_rows (user_id, rev);

-- 2) ทุกครั้งที่ส่งขึ้น → ได้เลขลำดับใหม่ (เครื่องอื่นดึงเฉพาะเลขที่ใหม่กว่าที่เคยเห็น)
create sequence if not exists public.sync_seq;
grant usage, select on sequence public.sync_seq to authenticated;

create or replace function public.sync_bump() returns trigger
language plpgsql as $$
begin
  new.rev := nextval('public.sync_seq');
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists sync_bump on public.sync_rows;
create trigger sync_bump before insert or update on public.sync_rows
  for each row execute function public.sync_bump();

-- 3) ความปลอดภัย: เห็น/แก้ได้เฉพาะข้อมูลของบัญชีตัวเอง
alter table public.sync_rows enable row level security;
drop policy if exists "own rows" on public.sync_rows;
create policy "own rows" on public.sync_rows
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.sync_rows to authenticated;
revoke all on public.sync_rows from anon;
