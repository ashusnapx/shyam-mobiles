-- 1 MB per photo instead of 5 MB: the app uploads WebP at most 1600 px (about 20-300 KB), so anything bigger is an
-- uncompressed original that would only grow the storage and bandwidth bill. The type list stays webp/jpeg/png.
update storage.buckets set file_size_limit = 1048576 where id = 'product-images';
