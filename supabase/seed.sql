-- Local/dev catalog. Prices in rupees here, stored as paise. No images (upload via the admin screens).

insert into public.categories (slug, name, kind, sort) values
  ('smartphones', 'Smartphones', 'phone', 0),
  ('keypad-phones', 'Keypad phones', 'phone', 1), -- LAVA / Nokia feature phones sell big in a town shop
  ('cases-covers', 'Cases & covers', 'accessory', 2),
  ('screen-guards', 'Screen guards', 'accessory', 3),
  ('chargers-cables', 'Chargers & cables', 'accessory', 4),
  ('earbuds-headphones', 'Earbuds & headphones', 'accessory', 5),
  ('power-banks', 'Power banks', 'accessory', 6);

insert into public.brands (slug, name) values
  ('samsung', 'Samsung'), ('apple', 'Apple'), ('oneplus', 'OnePlus'), ('xiaomi', 'Xiaomi'),
  ('vivo', 'vivo'), ('realme', 'realme'), ('motorola', 'Motorola'), ('google', 'Google'),
  ('nothing', 'Nothing'), ('oppo', 'OPPO'), ('lava', 'LAVA'), ('nokia', 'Nokia'),
  ('spigen', 'Spigen'), ('anker', 'Anker'), ('boat', 'boAt');

insert into public.products (slug, name, brand_id, category_id, description, specs, is_featured)
select p.slug, p.name, b.id, c.id, p.description, p.specs::jsonb, p.featured
from (values
  ('samsung-galaxy-s25', 'Samsung Galaxy S25', 'samsung', 'smartphones',
   'Compact flagship with Galaxy AI, a bright 120 Hz screen and 7 years of updates.',
   '[{"label":"Display","value":"6.2-inch Dynamic AMOLED 2X, 120 Hz"},{"label":"Processor","value":"Snapdragon 8 Elite for Galaxy"},{"label":"Camera","value":"50 MP + 12 MP ultra-wide + 10 MP 3x tele; 12 MP front"},{"label":"Battery","value":"4000 mAh, 25 W"},{"label":"Software","value":"Android 15, One UI 7"}]', true),
  ('samsung-galaxy-a56-5g', 'Samsung Galaxy A56 5G', 'samsung', 'smartphones',
   'Metal frame, IP67 and six OS upgrades at a mid-range price.',
   '[{"label":"Display","value":"6.7-inch Super AMOLED+, 120 Hz"},{"label":"Processor","value":"Exynos 1580"},{"label":"Camera","value":"50 MP + 12 MP ultra-wide + 5 MP macro; 12 MP front"},{"label":"Battery","value":"5000 mAh, 45 W"},{"label":"Software","value":"Android 15, One UI 7"}]', false),
  ('apple-iphone-16', 'Apple iPhone 16', 'apple', 'smartphones',
   'A18 chip, Camera Control and Apple Intelligence.',
   '[{"label":"Display","value":"6.1-inch Super Retina XDR OLED"},{"label":"Processor","value":"A18"},{"label":"Camera","value":"48 MP Fusion + 12 MP ultra-wide; 12 MP front"},{"label":"Battery","value":"Up to 22 h video playback"},{"label":"Software","value":"iOS 18"}]', true),
  ('apple-iphone-15', 'Apple iPhone 15', 'apple', 'smartphones',
   'Dynamic Island, 48 MP camera and USB-C.',
   '[{"label":"Display","value":"6.1-inch Super Retina XDR OLED"},{"label":"Processor","value":"A16 Bionic"},{"label":"Camera","value":"48 MP + 12 MP ultra-wide; 12 MP front"},{"label":"Battery","value":"Up to 20 h video playback"},{"label":"Software","value":"iOS 17"}]', false),
  ('oneplus-13', 'OnePlus 13', 'oneplus', 'smartphones',
   'Hasselblad triple 50 MP cameras, 6000 mAh battery and 100 W charging.',
   '[{"label":"Display","value":"6.82-inch LTPO AMOLED, 120 Hz"},{"label":"Processor","value":"Snapdragon 8 Elite"},{"label":"Camera","value":"50 MP + 50 MP ultra-wide + 50 MP 3x tele; 32 MP front"},{"label":"Battery","value":"6000 mAh, 100 W wired, 50 W wireless"},{"label":"Software","value":"Android 15, OxygenOS 15"}]', true),
  ('oneplus-nord-5', 'OnePlus Nord 5', 'oneplus', 'smartphones',
   'Flagship-grade chip and a 144 Hz display for gaming.',
   '[{"label":"Display","value":"6.83-inch AMOLED, 144 Hz"},{"label":"Processor","value":"Snapdragon 8s Gen 3"},{"label":"Camera","value":"50 MP + 8 MP ultra-wide; 50 MP front"},{"label":"Battery","value":"6800 mAh, 80 W"},{"label":"Software","value":"Android 15, OxygenOS 15"}]', false),
  ('xiaomi-redmi-note-14-pro-5g', 'Xiaomi Redmi Note 14 Pro 5G', 'xiaomi', 'smartphones',
   'Curved AMOLED, 50 MP OIS camera and IP68 dust and water resistance.',
   '[{"label":"Display","value":"6.67-inch AMOLED, 120 Hz"},{"label":"Processor","value":"MediaTek Dimensity 7300 Ultra"},{"label":"Camera","value":"50 MP + 8 MP ultra-wide + 2 MP macro; 20 MP front"},{"label":"Battery","value":"5110 mAh, 45 W"},{"label":"Software","value":"Android 14, HyperOS"}]', false),
  ('vivo-v50', 'vivo V50', 'vivo', 'smartphones',
   'Slim body with ZEISS portrait cameras and a 6000 mAh battery.',
   '[{"label":"Display","value":"6.77-inch AMOLED, 120 Hz"},{"label":"Processor","value":"Snapdragon 7 Gen 3"},{"label":"Camera","value":"50 MP + 50 MP ultra-wide; 50 MP front"},{"label":"Battery","value":"6000 mAh, 90 W"},{"label":"Software","value":"Android 15, Funtouch OS 15"}]', false),
  ('realme-narzo-80-pro-5g', 'realme Narzo 80 Pro 5G', 'realme', 'smartphones',
   'Fast charging and a bright display for under twenty thousand.',
   '[{"label":"Display","value":"6.77-inch AMOLED, 120 Hz"},{"label":"Processor","value":"MediaTek Dimensity 7400"},{"label":"Camera","value":"50 MP + 2 MP; 16 MP front"},{"label":"Battery","value":"6000 mAh, 80 W"},{"label":"Software","value":"Android 15, realme UI 6"}]', false),
  ('motorola-edge-60-fusion', 'Motorola Edge 60 Fusion', 'motorola', 'smartphones',
   'Quad-curved pOLED, Pantone colours and MIL-STD-810H toughness.',
   '[{"label":"Display","value":"6.67-inch pOLED, 120 Hz"},{"label":"Processor","value":"MediaTek Dimensity 7400"},{"label":"Camera","value":"50 MP + 13 MP ultra-wide; 32 MP front"},{"label":"Battery","value":"5500 mAh, 68 W"},{"label":"Software","value":"Android 15"}]', false),
  ('google-pixel-9a', 'Google Pixel 9a', 'google', 'smartphones',
   'Pixel camera and Gemini with 7 years of OS and security updates.',
   '[{"label":"Display","value":"6.3-inch Actua pOLED, 120 Hz"},{"label":"Processor","value":"Google Tensor G4"},{"label":"Camera","value":"48 MP + 13 MP ultra-wide; 13 MP front"},{"label":"Battery","value":"5100 mAh, 23 W"},{"label":"Software","value":"Android 15"}]', true),
  ('nothing-phone-3a', 'Nothing Phone (3a)', 'nothing', 'smartphones',
   'Glyph interface, 2x telephoto camera and a clean Nothing OS.',
   '[{"label":"Display","value":"6.77-inch AMOLED, 120 Hz"},{"label":"Processor","value":"Snapdragon 7s Gen 3"},{"label":"Camera","value":"50 MP + 50 MP 2x tele + 8 MP ultra-wide; 32 MP front"},{"label":"Battery","value":"5000 mAh, 50 W"},{"label":"Software","value":"Android 15, Nothing OS 3.1"}]', false),
  ('spigen-ultra-hybrid-iphone-16', 'Spigen Ultra Hybrid Case for iPhone 16', 'spigen', 'cases-covers',
   'Clear hard back with a shock-absorbing bumper. MagSafe compatible.',
   '[{"label":"Fits","value":"iPhone 16"},{"label":"Material","value":"Polycarbonate back, TPU bumper"},{"label":"Protection","value":"Military-grade drop tested"}]', false),
  ('spigen-glastr-galaxy-s25', 'Spigen GlasTR Screen Guard for Galaxy S25 (2 pack)', 'spigen', 'screen-guards',
   'Tempered glass with an auto-align installer. Fingerprint sensor friendly.',
   '[{"label":"Fits","value":"Galaxy S25"},{"label":"In the box","value":"2 guards, alignment kit"},{"label":"Hardness","value":"9H"}]', false),
  ('anker-nano-20w-usb-c-charger', 'Anker Nano 20W USB-C Charger', 'anker', 'chargers-cables',
   'Pocket-size fast charger for iPhone, Galaxy and Pixel.',
   '[{"label":"Output","value":"20 W USB-C Power Delivery"},{"label":"Ports","value":"1 x USB-C"},{"label":"In the box","value":"Charger only, no cable"}]', false),
  ('boat-airdopes-141', 'boAt Airdopes 141', 'boat', 'earbuds-headphones',
   'Truly wireless earbuds with up to 42 hours of playback.',
   '[{"label":"Playback","value":"Up to 42 h with case"},{"label":"Drivers","value":"8 mm"},{"label":"Calls","value":"ENx noise cancellation"},{"label":"Water resistance","value":"IPX4"}]', true),
  ('anker-powercore-10000', 'Anker PowerCore 10000 Power Bank', 'anker', 'power-banks',
   'Credit-card-size 10000 mAh power bank.',
   '[{"label":"Capacity","value":"10000 mAh"},{"label":"Output","value":"12 W USB-A"},{"label":"Weight","value":"180 g"}]', false)
) p(slug, name, brand, category, description, specs, featured)
join public.brands b on b.slug = p.brand
join public.categories c on c.slug = p.category;

insert into public.variants (product_id, sku, name, attributes, price_paise, mrp_paise, stock, sort)
select pr.id, v.sku, v.name, v.attributes::jsonb, v.price * 100, v.mrp * 100, v.stock, v.sort
from (values
  ('samsung-galaxy-s25', 'SAM-S25-12-256-NVY', '12 GB · 256 GB · Navy', '{"ram":"12 GB","storage":"256 GB","color":"Navy","color_hex":"#2C3646"}', 74999, 80999, 8, 0),
  ('samsung-galaxy-s25', 'SAM-S25-12-256-ICB', '12 GB · 256 GB · Icyblue', '{"ram":"12 GB","storage":"256 GB","color":"Icyblue","color_hex":"#B9CCE0"}', 74999, 80999, 5, 1),
  ('samsung-galaxy-s25', 'SAM-S25-12-512-NVY', '12 GB · 512 GB · Navy', '{"ram":"12 GB","storage":"512 GB","color":"Navy","color_hex":"#2C3646"}', 86999, 92999, 2, 2),
  ('samsung-galaxy-a56-5g', 'SAM-A56-8-128-GPH', '8 GB · 128 GB · Awesome Graphite', '{"ram":"8 GB","storage":"128 GB","color":"Awesome Graphite","color_hex":"#3B3B3D"}', 38999, 41999, 12, 0),
  ('samsung-galaxy-a56-5g', 'SAM-A56-8-256-OLV', '8 GB · 256 GB · Awesome Olive', '{"ram":"8 GB","storage":"256 GB","color":"Awesome Olive","color_hex":"#8A8F6A"}', 41999, 44999, 6, 1),
  ('apple-iphone-16', 'APL-IP16-128-BLK', '128 GB · Black', '{"storage":"128 GB","color":"Black","color_hex":"#3C3D3A"}', 69900, 79900, 6, 0),
  ('apple-iphone-16', 'APL-IP16-128-ULT', '128 GB · Ultramarine', '{"storage":"128 GB","color":"Ultramarine","color_hex":"#9AADF6"}', 69900, 79900, 0, 1),
  ('apple-iphone-16', 'APL-IP16-256-BLK', '256 GB · Black', '{"storage":"256 GB","color":"Black","color_hex":"#3C3D3A"}', 79900, 89900, 3, 2),
  ('apple-iphone-15', 'APL-IP15-128-BLK', '128 GB · Black', '{"storage":"128 GB","color":"Black","color_hex":"#35393B"}', 59900, 69900, 0, 0),
  ('apple-iphone-15', 'APL-IP15-128-BLU', '128 GB · Blue', '{"storage":"128 GB","color":"Blue","color_hex":"#D5DDDF"}', 59900, 69900, 0, 1),
  ('oneplus-13', 'OP-13-12-256-MOC', '12 GB · 256 GB · Midnight Ocean', '{"ram":"12 GB","storage":"256 GB","color":"Midnight Ocean","color_hex":"#1F2A44"}', 69999, 72999, 4, 0),
  ('oneplus-13', 'OP-13-16-512-BEC', '16 GB · 512 GB · Black Eclipse', '{"ram":"16 GB","storage":"512 GB","color":"Black Eclipse","color_hex":"#1A1A1A"}', 76999, 79999, 2, 1),
  ('oneplus-nord-5', 'OP-N5-8-256-MSD', '8 GB · 256 GB · Marble Sands', '{"ram":"8 GB","storage":"256 GB","color":"Marble Sands","color_hex":"#E6E0D4"}', 31999, 31999, 10, 0),
  ('oneplus-nord-5', 'OP-N5-12-256-PGR', '12 GB · 256 GB · Phantom Grey', '{"ram":"12 GB","storage":"256 GB","color":"Phantom Grey","color_hex":"#4A4D52"}', 34999, 34999, 0, 1),
  ('xiaomi-redmi-note-14-pro-5g', 'XI-RN14P-8-128-TBK', '8 GB · 128 GB · Titan Black', '{"ram":"8 GB","storage":"128 GB","color":"Titan Black","color_hex":"#2A2B2E"}', 23999, 28999, 15, 0),
  ('xiaomi-redmi-note-14-pro-5g', 'XI-RN14P-8-256-PPL', '8 GB · 256 GB · Phantom Purple', '{"ram":"8 GB","storage":"256 GB","color":"Phantom Purple","color_hex":"#8C7BA8"}', 25999, 30999, 7, 1),
  ('vivo-v50', 'VI-V50-8-128-RSR', '8 GB · 128 GB · Rose Red', '{"ram":"8 GB","storage":"128 GB","color":"Rose Red","color_hex":"#C9566B"}', 34999, 40999, 6, 0),
  ('vivo-v50', 'VI-V50-12-256-TGR', '12 GB · 256 GB · Titanium Grey', '{"ram":"12 GB","storage":"256 GB","color":"Titanium Grey","color_hex":"#7D7F82"}', 38999, 44999, 3, 1),
  ('realme-narzo-80-pro-5g', 'RM-N80P-8-128-SSV', '8 GB · 128 GB · Speed Silver', '{"ram":"8 GB","storage":"128 GB","color":"Speed Silver","color_hex":"#C7CACE"}', 19999, 22999, 0, 0),
  ('motorola-edge-60-fusion', 'MO-E60F-8-256-AMZ', '8 GB · 256 GB · Pantone Amazonite', '{"ram":"8 GB","storage":"256 GB","color":"Pantone Amazonite","color_hex":"#2F6F68"}', 22999, 25999, 9, 0),
  ('motorola-edge-60-fusion', 'MO-E60F-12-256-SLP', '12 GB · 256 GB · Pantone Slipstream', '{"ram":"12 GB","storage":"256 GB","color":"Pantone Slipstream","color_hex":"#A9B7C6"}', 24999, 27999, 4, 1),
  ('google-pixel-9a', 'GO-P9A-8-256-OBS', '8 GB · 256 GB · Obsidian', '{"ram":"8 GB","storage":"256 GB","color":"Obsidian","color_hex":"#2B2B2D"}', 49999, 49999, 5, 0),
  ('google-pixel-9a', 'GO-P9A-8-256-PRC', '8 GB · 256 GB · Porcelain', '{"ram":"8 GB","storage":"256 GB","color":"Porcelain","color_hex":"#EDE8DF"}', 49999, 49999, 1, 1),
  ('nothing-phone-3a', 'NO-P3A-8-128-BLK', '8 GB · 128 GB · Black', '{"ram":"8 GB","storage":"128 GB","color":"Black","color_hex":"#1C1C1C"}', 24999, 27999, 12, 0),
  ('nothing-phone-3a', 'NO-P3A-8-256-WHT', '8 GB · 256 GB · White', '{"ram":"8 GB","storage":"256 GB","color":"White","color_hex":"#F2F2F0"}', 26999, 29999, 6, 1),
  ('spigen-ultra-hybrid-iphone-16', 'SP-UH-IP16-CLR', 'Crystal Clear', '{"color":"Crystal Clear","color_hex":"#E8EEF2"}', 1299, 2999, 25, 0),
  ('spigen-ultra-hybrid-iphone-16', 'SP-UH-IP16-MBK', 'Matte Black', '{"color":"Matte Black","color_hex":"#222222"}', 1399, 2999, 10, 1),
  ('spigen-glastr-galaxy-s25', 'SP-GLS-S25-2PK', '2 pack', '{}', 1199, 2499, 30, 0),
  ('anker-nano-20w-usb-c-charger', 'AN-NANO20-WHT', 'White', '{"color":"White","color_hex":"#F5F5F5"}', 1299, 1999, 20, 0),
  ('boat-airdopes-141', 'BT-AD141-BLK', 'Bold Black', '{"color":"Bold Black","color_hex":"#1E1E1E"}', 1099, 4490, 40, 0),
  ('boat-airdopes-141', 'BT-AD141-WHT', 'Pure White', '{"color":"Pure White","color_hex":"#FAFAFA"}', 1099, 4490, 0, 1),
  ('anker-powercore-10000', 'AN-PC10K-BLK', 'Black', '{"color":"Black","color_hex":"#202020"}', 1999, 3999, 2, 0)
) v(product, sku, name, attributes, price, mrp, stock, sort)
join public.products pr on pr.slug = v.product;

-- The shop: श्याम मोबाइल शॉप, wholesale and retail, Rajeev Complex, Waidhan (Singrauli, MP).
update public.store_settings set
  store_phone = '+917987559272',
  store_address = 'Rajeev Complex, Waidhan, District Singrauli, Madhya Pradesh 486886',
  -- the place pin of the "Shyam Mobile Center" Google Maps listing (!3d/!4d, not the @ viewport)
  store_lat = 24.0670269,
  store_lng = 82.6307508,
  store_maps_url = 'https://maps.google.com/?cid=3396347197360889573';

-- Local dev logins (scripts/dev_setup.py, app DEV_LOGIN) still use a password; production keeps this table empty.
insert into private.password_sign_in_domains (domain) values ('shyammobiles.test');
