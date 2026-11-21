-- Noir Manager · สัญญาณสด (รอบ 21): เครื่องอื่นบันทึก → เครื่องนี้รู้ทันที
-- วิธีใช้: Supabase › SQL Editor › New query › วาง › Run (รันซ้ำได้)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_rows'
  ) then
    alter publication supabase_realtime add table public.sync_rows;
  end if;
end $$;
