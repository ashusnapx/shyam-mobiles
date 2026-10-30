-- A photo can belong to one colour of a product ("Navy", matching variants.attributes->>'color'), so picking a
-- colour shows that colour. Null = the product in general (box, back, any colour); those show for every colour.
alter table public.product_images
  add column color text check (color is null or (char_length(color) between 1 and 40 and public.is_clean_text(color)));
