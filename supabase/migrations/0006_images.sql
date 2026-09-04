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
create or replace function fn_sync_primary_product_image()
returns trigger
language plpgsql
as $$
begin
  update product p
     set image_url = (
           select i.storage_path
           from product_image i
           where i.product_id = p.id and i.is_primary
           limit 1
         ),
         updated_at = now()
   where p.id = coalesce(new.product_id, old.product_id);
  return null;
end $$;

drop trigger if exists product_image_sync on product_image;
create trigger product_image_sync
  after insert or update or delete on product_image
  for each row execute function fn_sync_primary_product_image();
