-- 0006_images.sql
-- Product images. Three entry routes, one destination.
--
--   1. Phone   — chachu photographs a box in the godown, it uploads straight to storage.
--   2. Excel   — a URL column in the bulk import; the importer fetches and stores it.
--   3. Direct  — dragged into the product form on a desktop.
--
-- All three land in the same bucket and the same table. There is no "external URL" mode where
-- the image lives on somebody else's server: a WhatsApp or Drive link will rot, and the customer
-- portal would then show a broken product.
--
-- APPLY-TIME WARNING, deliberately not worked around. storage.objects and storage.buckets are
-- owned by supabase_storage_admin, not by postgres. On most hosted projects postgres is a
-- member of that role and the four statements below succeed; on some they fail with
-- "must be owner of table objects" or a permission denied on storage.buckets. The migration
-- runs as one transaction, so if the storage block fails NOTHING in this file lands — the
-- product_image table below will be missing too, and the failure will look like it came from
-- the wrong place. If that happens: create the bucket and its two policies once from the
-- Dashboard (Storage → Buckets, then Storage → Policies, which run as the storage admin), then
-- re-run this migration. The statements are all if-exists / on-conflict guarded, so the second
-- run is a no-op over whatever the Dashboard already created.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,                                   -- public read: the customer portal shows these
  10485760,                               -- 10 MB; phone photos should be resized client-side first
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict (id) do nothing;

-- Operator can write; anyone can read (the portal is public by link).
drop policy if exists product_images_read  on storage.objects;
drop policy if exists product_images_write on storage.objects;

create policy product_images_read on storage.objects
  for select to public
  using (bucket_id = 'product-images');

create policy product_images_write on storage.objects
  for all to authenticated
  using (bucket_id = 'product-images')
  with check (bucket_id = 'product-images');

-- ---------------------------------------------------------------------------
-- A product can have several images: the marketing shot, the actual box, the back panel.
-- product.image_url stays as the single primary image for fast list rendering; this table is
-- the full set.
-- ---------------------------------------------------------------------------

create table if not exists product_image (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references product(id) on delete cascade,
  storage_path  text not null,
  caption       text,
  is_primary    boolean not null default false,
  sort_order    int not null default 0,
  source        text not null default 'upload'
                check (source in ('upload','phone','import','flyer')),
  created_at    timestamptz not null default now()
);

create index if not exists idx_product_image_product on product_image(product_id, sort_order);

-- Only one primary image per product.
create unique index if not exists uq_product_image_primary
  on product_image(product_id) where is_primary;

alter table product_image enable row level security;

drop policy if exists operator_all on product_image;
create policy operator_all on product_image
  for all to authenticated using (true) with check (true);

-- Keep product.image_url pointing at the primary image so list views need no join.
--
-- The branch on TG_OP is doing real work, not being tidy. NEW is null on a delete and OLD is
-- null on an insert, so a single coalesce reads correctly for those two — but it reads only
-- ONE product, and an update that moves an image from one product to another touches two. The
-- product that lost the image would keep an image_url pointing at a photo that now belongs to
-- somebody else, and every list and portal page would show the wrong box for that product. So
-- both ends of an update are collected and both are resynced. Naming the row variables per
-- operation also means this does not depend on the reader knowing the null-vs-unassigned rule.
create or replace function fn_sync_primary_product_image()
returns trigger
language plpgsql
as $$
declare
  v_affected uuid[];
begin
  if tg_op = 'INSERT' then
    v_affected := array[new.product_id];
  elsif tg_op = 'UPDATE' then
    v_affected := array[new.product_id, old.product_id];
  else  -- DELETE
    v_affected := array[old.product_id];
  end if;

  update product p
     set image_url = (
           select i.storage_path
           from product_image i
           where i.product_id = p.id and i.is_primary
           limit 1
         ),
         updated_at = now()
   where p.id = any (v_affected);
  return null;
end $$;

drop trigger if exists product_image_sync on product_image;
create trigger product_image_sync
  after insert or update or delete on product_image
  for each row execute function fn_sync_primary_product_image();
