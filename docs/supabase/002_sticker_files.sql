-- Noir Manager · ที่เก็บรูปสติกเกอร์ (รอบ 20)
-- วิธีใช้: Supabase › SQL Editor › New query › วางทั้งไฟล์ › Run (รันซ้ำได้)

-- ถังเก็บรูปแบบส่วนตัว (ไม่มีลิงก์สาธารณะ) · รูปละไม่เกิน 2 MB · รับเฉพาะรูป
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stickers', 'stickers', false, 2097152, array['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

-- แต่ละบัญชีเห็น/แก้ได้เฉพาะโฟลเดอร์ของตัวเอง: stickers/<รหัสบัญชี>/…
drop policy if exists "stickers own read" on storage.objects;
create policy "stickers own read" on storage.objects for select to authenticated
  using (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "stickers own insert" on storage.objects;
create policy "stickers own insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "stickers own update" on storage.objects;
create policy "stickers own update" on storage.objects for update to authenticated
  using (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "stickers own delete" on storage.objects;
create policy "stickers own delete" on storage.objects for delete to authenticated
  using (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);
