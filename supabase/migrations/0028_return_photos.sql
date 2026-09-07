-- 0028_return_photos.sql
-- Photographs of damage, taken at the moment it is found, kept where the customer cannot reach them.
--
-- `movement.photos` has existed since 0002 and nothing has ever written to it. This gives it a
-- bucket, a contract, and two permissions.
--
-- WHY A SECOND BUCKET AND NOT THE ONE WE HAVE. `product-images` is PUBLIC, which is correct for a
-- catalogue photograph: the customer portal shows it, and a signed URL on a picture of a speaker
-- would be ceremony with no secret behind it. It is exactly wrong for this. A photograph of a
-- cracked cabinet is taken inside somebody's wedding hall — their property, their event, their
-- guests in the background — and a public bucket is world-readable at a URL that only has to be
-- guessed once. That is not our picture to publish. Two buckets, opposite defaults, and the
-- default is the protection: nothing has to be remembered at upload time.
--
-- WHO MAY LOOK. returns.write, because the man recording the return is the man holding the phone.
-- ledger.view, because this is evidence for a money conversation — the deposit deduction gets
-- argued about a week later, over the telephone, and the person defending the number has to be
-- able to open the picture. Nobody else, and NOT the portal: see the assertion at the foot of this
-- file. A customer arguing about a deduction is shown the photograph by a person, not served it by
-- a machine, because the photograph of one job's damage sits in the same bucket as every other
-- job's and the portal is public by link.
--
-- WHEN IT IS WRITTEN, AND WHY IT CANNOT BE ADDED LATER. `movement` is append-only: 0009's
-- movement_no_update trigger refuses UPDATE outright. So a path lands in `photos` in the INSERT
-- that records the return, or it never lands at all. That is a real constraint on the screen — the
-- picture is taken BEFORE "Record returns" is pressed — and it is the right one for evidence:
-- a photograph attached afterwards is a photograph of something, taken at an unknown time. The
-- cost is that a forgotten photograph needs 0019's correction path to get in, and that cost is
-- recorded in docs/backlog.md rather than worked around here.

-- ---------------------------------------------------------------------------
-- THE BUCKET.
--
-- Same apply-time warning as 0006: storage.buckets and storage.objects belong to
-- supabase_storage_admin, not to postgres. If this block fails with "must be owner of table
-- objects", create the bucket from the Dashboard (Storage → Buckets, private) and re-run — every
-- statement here is on-conflict or if-exists guarded, so the second run is a no-op over it.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'return-photos',
  'return-photos',
  false,                                  -- PRIVATE. Reads go through a signed URL, minted per look.
  10485760,                               -- 10 MB, same as the catalogue: resize on the phone first.
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict (id) do update
  set public             = false,         -- if a Dashboard hand created it public, this corrects it
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- No policy names `public` or `anon`. There is nothing to switch off later and nothing to get
-- wrong: an unauthenticated request matches no policy and storage refuses it. Proved with a real
-- HTTP request rather than by reading this comment — supabase/probes/0028_return_photos_probe.sh.
drop policy if exists return_photos_read   on storage.objects;
drop policy if exists return_photos_write  on storage.objects;
drop policy if exists return_photos_delete on storage.objects;

create policy return_photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'return-photos'
    and (public.fn_has_permission('returns.write') or public.fn_has_permission('ledger.view'))
  );

-- Uploading is the van's job, so it is returns.write alone. Somebody who may only READ the ledger
-- has no business adding evidence to it.
create policy return_photos_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'return-photos'
    and public.fn_has_permission('returns.write')
  );

-- REPLACING AND REMOVING, AND THE LINE BETWEEN A DRAFT AND EVIDENCE.
--
-- The first version of this migration granted neither, on "rule 12, history is never deleted", and
-- that was one rule applied to two different things. A photograph becomes evidence at the moment a
-- movement row references it — before that it is a blurry picture of a floor, taken by somebody
-- standing in a hall with one hand, and the retake is the normal case rather than the exception.
-- After that it is attached to an append-only row and must not move.
--
-- So the policy asks the question directly: is any movement pointing at this key? Unattached, the
-- man who took it may replace or remove it. Attached, nobody can, and the correction path is the
-- only way to say the record is wrong. This is the same shape as 0019 — you may peel the tip, you
-- may never reach into the middle.
--
-- (It is also what lets supabase/probes/0028_return_photos_probe.sh tidy up after itself. Storage
-- refuses direct DELETE on storage.objects — storage.protect_delete() — so a probe with no policy
-- to use leaves rubbish behind every run, and a probe that leaves rubbish stops being run.)
create policy return_photos_replace on storage.objects
  for update to authenticated
  using (
    bucket_id = 'return-photos'
    and public.fn_has_permission('returns.write')
    and not exists (
      select 1 from movement m
      where m.photos @> jsonb_build_array(jsonb_build_object('path', storage.objects.name)))
  );

create policy return_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'return-photos'
    and public.fn_has_permission('returns.write')
    and not exists (
      select 1 from movement m
      where m.photos @> jsonb_build_array(jsonb_build_object('path', storage.objects.name)))
  );

-- The containment test above runs on every storage write, so it gets an index rather than a seq
-- scan over every movement ever recorded.
create index if not exists movement_photos_gin on movement using gin (photos jsonb_path_ops);

-- ---------------------------------------------------------------------------
-- THE CONTRACT ON movement.photos.
--
-- An array of objects: [{"path": "<order_id>/<uuid>.jpg", "at": "2026-09-08", "caption": "..."}].
-- `path` is a key inside return-photos and nowhere else — a path is not a URL, so nothing here
-- rots when the project moves, and a row that quietly pointed at the PUBLIC bucket would be a leak
-- wearing the right shape. The first folder is the order id, so an orphan (photographed, return
-- never recorded) can still be traced to the job it belongs to.
-- ---------------------------------------------------------------------------

-- A CHECK cannot contain a subquery, and walking an array needs one — so the walk lives in an
-- immutable function and the constraint calls it. Immutable is not decoration here: Postgres will
-- happily accept a volatile function in a CHECK and then not re-evaluate it when you expect.
create or replace function fn_photos_are_bucket_keys(p jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p) = 'array'
     and not exists (
       select 1 from jsonb_array_elements(p) e
       where jsonb_typeof(e) <> 'object'
          or coalesce(e->>'path', '') = ''
          or e->>'path' like 'http%'             -- a URL, not a key: rots, and may point anywhere
          or e->>'path' like 'product-images/%'  -- the PUBLIC bucket, by name
          or e->>'path' like '/%'
     );
$$;

comment on function fn_photos_are_bucket_keys(jsonb) is
  'True when a photos array holds only {path,...} objects whose path is a relative key inside the private return-photos bucket. Rejects URLs and anything addressed into the public catalogue bucket (0028).';

alter table movement drop constraint if exists movement_photos_shape;
alter table movement add constraint movement_photos_shape
  check (fn_photos_are_bucket_keys(photos)) not valid;
-- `not valid` skips the existing rows, which are all '[]' and would pass anyway; validating
-- separately keeps the ACCESS EXCLUSIVE lock off the movement table on a live database.
alter table movement validate constraint movement_photos_shape;

comment on column movement.photos is
  'Damage evidence, written only at INSERT (movement is append-only). Array of {path, at, caption?} where path is a key inside the PRIVATE return-photos bucket — never a URL, never the public product-images bucket. Readable by returns.write or ledger.view; never exposed to the portal (0028).';

-- ---------------------------------------------------------------------------
-- READING THEM BACK. v_unit_history is the piece sheet, so that is where the evidence belongs.
--
-- RULE 14 APPLIED TO A PICTURE. photo_count is always visible, so an account that may not open
-- them still learns that they exist — "2 photos, not visible from this account" is a refusal a
-- screen can explain. `photos` itself is NULL without the key, never an empty array: an empty
-- array says "nobody photographed this", which is a different and much more comfortable claim than
-- "you may not look", and it is the comfortable wrong answer that never gets questioned.
-- ---------------------------------------------------------------------------

-- 0019's definition verbatim, with two columns appended. `create or replace view` may add columns
-- at the end and may not touch the ones already there, so this is restated whole rather than
-- wrapped: a wrapper over the old view would have needed a second join back to movement anyway,
-- and every screen reading v_unit_history would then be two views away from the row it displays.
create or replace view v_unit_history with (security_invoker = on) as
select
  m.id                as movement_id,
  m.unit_id,
  m.product_id,
  m.movement_type,
  m.moved_on,
  m.created_at,
  m.from_kind, m.from_id, m.to_kind, m.to_id,
  m.order_id,
  o.order_no,
  m.condition_at_move,
  m.notes,
  m.corrects_movement_id,
  (c.id is not null)  as is_corrected,
  c.id                as corrected_by_id,
  c.moved_on          as corrected_on,
  c.notes             as correction_reason,
  (m.movement_type = 'correction') as is_correction,
  -- Always visible: that evidence EXISTS is not itself the evidence.
  jsonb_array_length(coalesce(m.photos, '[]'::jsonb)) as photo_count,
  -- NULL, not '[]', without the key.
  case when public.fn_has_permission('returns.write') or public.fn_has_permission('ledger.view')
       then m.photos end as photos
from movement m
left join movement c
  on c.movement_type = 'correction' and c.corrects_movement_id = m.id
left join rental_order o on o.id = m.order_id
where m.unit_id is not null;

comment on view v_unit_history is
  'Everything that happened to one piece, corrections included. photo_count is always present; photos is NULL rather than [] without returns.write or ledger.view, because "none were taken" and "you may not look" must not read the same (rule 14).';

revoke all on table v_unit_history from anon;
grant select on table v_unit_history to authenticated;

-- ---------------------------------------------------------------------------
-- THE ASSERTION: the portal does not carry these, and cannot start carrying them by accident.
--
-- fn_portal_snapshot is security definer and builds its JSON as an explicit allow-list, so today
-- it cannot leak a column it does not name. That is a property of how it happens to be written,
-- not a guarantee, and the next person to add a field to the portal will be adding it to a
-- jsonb_build_object a hundred lines long. This fails the migration if `photos` ever appears in it.
-- ---------------------------------------------------------------------------
do $assert$
declare def text; n int;
begin
  select pg_get_functiondef(p.oid) into def
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_portal_snapshot';

  if def is null then
    raise exception 'fn_portal_snapshot not found. 0028 asserts that the portal does not serve damage photographs; it cannot assert that against a function that is not there.';
  end if;
  if def ~* '\mphotos\M' then
    raise exception
      'fn_portal_snapshot names "photos". Expected: the portal serves order lines, balances and the ledger, and NOT damage evidence — the picture is shown to a customer by a person, because the bucket holds every other job''s damage too. Actual: the portal function references photos (0028).';
  end if;

  select count(*)::int into n from storage.buckets where id = 'return-photos' and public = false;
  if n <> 1 then
    raise exception 'Expected: exactly 1 bucket named return-photos with public = false. Actual: %. A public bucket makes every signed URL in this migration ceremony over a world-readable object.', n;
  end if;

  raise notice '0028 ok: return-photos is private, the portal does not name photos, and movement.photos has a shape.';
end $assert$;
