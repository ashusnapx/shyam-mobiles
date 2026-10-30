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

-- Five products in every category: keypad phones and accessories, with full specs, colours and a mix of stock
-- (plenty, low, sold out). Safe to run on a database that already has the rest of the seed.
insert into public.brands (slug, name) values
  ('itel', 'itel'), ('jio', 'Jio'), ('jbl', 'JBL'), ('portronics', 'Portronics'), ('ambrane', 'Ambrane')
on conflict (slug) do nothing;

insert into public.products (slug, name, brand_id, category_id, description, specs, is_featured)
select p.slug, p.name, b.id, c.id, p.description, p.specs::jsonb, p.featured
from (values
  -- keypad phones
  ('nokia-105-classic', 'Nokia 105 Classic', 'nokia', 'keypad-phones',
   'The everyday keypad phone: a battery that lasts days, a loud speaker, a torch and wireless FM radio.',
   '[{"label":"Display","value":"1.8-inch QQVGA"},{"label":"Network","value":"2G, dual SIM"},{"label":"Battery","value":"800 mAh, removable, up to 12 days standby"},{"label":"Storage","value":"Up to 2,000 contacts and 500 SMS"},{"label":"Extras","value":"Wireless FM radio, torch, Snake game"},{"label":"Warranty","value":"1 year manufacturer"}]', false),
  ('nokia-110-4g-2024', 'Nokia 110 4G (2024)', 'nokia', 'keypad-phones',
   '4G calls in HD, a camera, and UPI payments with 123PAY, all on a keypad phone.',
   '[{"label":"Display","value":"2-inch QVGA"},{"label":"Network","value":"4G VoLTE, dual SIM"},{"label":"Camera","value":"0.3 MP rear with flash"},{"label":"Battery","value":"1450 mAh, removable, Type-C charging"},{"label":"Storage","value":"microSD up to 32 GB"},{"label":"Extras","value":"UPI 123PAY, MP3 player, wireless FM radio"},{"label":"Warranty","value":"1 year manufacturer"}]', false),
  ('lava-a1-josh', 'LAVA A1 Josh', 'lava', 'keypad-phones',
   'Made in India keypad phone with a big battery, number talker in Hindi and English, and a bright torch.',
   '[{"label":"Display","value":"1.77-inch QQVGA"},{"label":"Network","value":"2G, dual SIM"},{"label":"Battery","value":"1000 mAh, up to 6 days standby"},{"label":"Storage","value":"microSD up to 32 GB"},{"label":"Extras","value":"Number talker, call recording, FM radio, torch"},{"label":"Warranty","value":"1 year manufacturer"}]', false),
  ('itel-magic-x-play', 'itel Magic X Play', 'itel', 'keypad-phones',
   '4G keypad phone with WhatsApp and YouTube, a 2.4-inch screen and a 1900 mAh battery.',
   '[{"label":"Display","value":"2.4-inch QVGA"},{"label":"Network","value":"4G VoLTE, dual SIM"},{"label":"Camera","value":"0.3 MP rear"},{"label":"Battery","value":"1900 mAh"},{"label":"Storage","value":"48 MB RAM, 128 MB; microSD up to 64 GB"},{"label":"Extras","value":"WhatsApp, YouTube, hotspot, FM radio"},{"label":"Warranty","value":"1 year manufacturer"}]', false),
  ('jio-bharat-b1-4g', 'Jio Bharat B1 4G', 'jio', 'keypad-phones',
   'Jio’s 4G phone with JioPay UPI, JioCinema and JioSaavn built in. Works with a Jio SIM.',
   '[{"label":"Display","value":"2.4-inch QVGA"},{"label":"Network","value":"4G VoLTE, Jio SIM only"},{"label":"Camera","value":"0.3 MP rear"},{"label":"Battery","value":"2000 mAh, removable"},{"label":"Storage","value":"microSD up to 128 GB"},{"label":"Extras","value":"JioPay UPI, JioCinema, JioSaavn, FM radio"},{"label":"Warranty","value":"1 year manufacturer"}]', false),
  -- cases & covers
  ('apple-iphone-16-silicone-case-magsafe', 'Apple iPhone 16 Silicone Case with MagSafe', 'apple', 'cases-covers',
   'Apple’s own silky silicone case with a soft microfibre lining. MagSafe chargers snap on through it.',
   '[{"label":"Fits","value":"iPhone 16"},{"label":"Material","value":"Silicone outside, microfibre lining"},{"label":"MagSafe","value":"Yes, built-in magnets"},{"label":"Warranty","value":"1 year Apple"}]', false),
  ('spigen-tough-armor-galaxy-s25', 'Spigen Tough Armor Case for Galaxy S25', 'spigen', 'cases-covers',
   'Dual-layer protection with a built-in kickstand for watching videos hands-free.',
   '[{"label":"Fits","value":"Galaxy S25"},{"label":"Material","value":"Polycarbonate shell, TPU inner layer, foam corners"},{"label":"Protection","value":"Military-grade drop tested"},{"label":"Extras","value":"Built-in kickstand, raised camera lip"}]', false),
  ('spigen-liquid-air-pixel-9a', 'Spigen Liquid Air Case for Pixel 9a', 'spigen', 'cases-covers',
   'Slim matte case with a textured grip pattern that keeps the phone light in the pocket.',
   '[{"label":"Fits","value":"Pixel 9a"},{"label":"Material","value":"Flexible TPU"},{"label":"Protection","value":"Air Cushion corners"},{"label":"Extras","value":"Tactile buttons, raised screen and camera lips"}]', false),
  ('oneplus-13-sandstone-magnetic-case', 'OnePlus 13 Sandstone Magnetic Case', 'oneplus', 'cases-covers',
   'The classic OnePlus sandstone grip with magnets for magnetic chargers and car mounts.',
   '[{"label":"Fits","value":"OnePlus 13"},{"label":"Material","value":"Sandstone-textured polycarbonate"},{"label":"Magnetic","value":"Yes, works with magnetic chargers"},{"label":"Warranty","value":"6 months OnePlus"}]', false),
  -- screen guards
  ('spigen-glastr-ez-fit-iphone-16', 'Spigen GlasTR EZ Fit Screen Guard for iPhone 16 (2 pack)', 'spigen', 'screen-guards',
   'Bubble-free tempered glass that lines itself up with the EZ Fit tray in seconds.',
   '[{"label":"Fits","value":"iPhone 16"},{"label":"In the box","value":"2 guards, EZ Fit installer, cleaning kit"},{"label":"Hardness","value":"9H"},{"label":"Thickness","value":"0.33 mm"}]', false),
  ('spigen-glastr-slim-pixel-9a', 'Spigen GlasTR Slim Screen Guard for Pixel 9a (2 pack)', 'spigen', 'screen-guards',
   'Case-friendly tempered glass that keeps the in-display fingerprint sensor working.',
   '[{"label":"Fits","value":"Pixel 9a"},{"label":"In the box","value":"2 guards, alignment kit"},{"label":"Hardness","value":"9H"},{"label":"Fingerprint sensor","value":"Supported"}]', false),
  ('spigen-neo-flex-oneplus-13', 'Spigen Neo Flex Film for OnePlus 13 (2 pack)', 'spigen', 'screen-guards',
   'Self-healing film that follows the curved edges of the OnePlus 13, where glass can lift.',
   '[{"label":"Fits","value":"OnePlus 13"},{"label":"In the box","value":"2 films, spray solution, squeegee"},{"label":"Type","value":"TPU film, self-healing"},{"label":"Edges","value":"Full curved coverage"}]', false),
  ('spigen-optik-lens-protector-iphone-16', 'Spigen Optik Camera Lens Protector for iPhone 16 (2 pack)', 'spigen', 'screen-guards',
   'Tempered glass for the camera bump, so scratches never reach your photos.',
   '[{"label":"Fits","value":"iPhone 16"},{"label":"In the box","value":"2 lens protectors, EZ Fit tray"},{"label":"Hardness","value":"9H"},{"label":"Flash","value":"Cut-out, no glare"}]', false),
  -- chargers & cables
  ('samsung-25w-super-fast-charger', 'Samsung 25W Super Fast Charger (USB-C)', 'samsung', 'chargers-cables',
   'Samsung’s own 25 W adapter for Super Fast Charging on Galaxy phones. Cable not included.',
   '[{"label":"Output","value":"25 W USB-C, PD 3.0 PPS"},{"label":"Ports","value":"1 x USB-C"},{"label":"Works with","value":"Galaxy S, A and M series; any USB-C PD phone"},{"label":"In the box","value":"Adapter only"},{"label":"Warranty","value":"1 year Samsung"}]', false),
  ('apple-20w-usb-c-power-adapter', 'Apple 20W USB-C Power Adapter', 'apple', 'chargers-cables',
   'Apple’s fast charger: about 50% charge in 30 minutes on recent iPhones.',
   '[{"label":"Output","value":"20 W USB-C Power Delivery"},{"label":"Ports","value":"1 x USB-C"},{"label":"Works with","value":"iPhone 8 and later, iPad, AirPods"},{"label":"In the box","value":"Adapter only"},{"label":"Warranty","value":"1 year Apple"}]', false),
  ('anker-322-usb-c-cable-1-8m', 'Anker 322 USB-C to USB-C Cable (1.8 m, 60 W)', 'anker', 'chargers-cables',
   'Braided 1.8 m cable that fast-charges phones and laptops up to 60 W.',
   '[{"label":"Length","value":"1.8 m"},{"label":"Power","value":"Up to 60 W"},{"label":"Data","value":"USB 2.0, 480 Mbps"},{"label":"Build","value":"Double-braided nylon, 10,000+ bend lifespan"},{"label":"Warranty","value":"18 months Anker"}]', false),
  ('portronics-konnect-l-type-c-to-lightning', 'Portronics Konnect L Type-C to Lightning Cable (1.2 m)', 'portronics', 'chargers-cables',
   'Fast-charge an iPhone from any USB-C charger with this 20 W braided cable.',
   '[{"label":"Length","value":"1.2 m"},{"label":"Power","value":"Up to 20 W PD"},{"label":"Connectors","value":"USB-C to Lightning"},{"label":"Build","value":"Nylon braided"},{"label":"Warranty","value":"6 months Portronics"}]', false),
  -- earbuds & headphones
  ('oneplus-nord-buds-3-pro', 'OnePlus Nord Buds 3 Pro', 'oneplus', 'earbuds-headphones',
   'Up to 49 dB noise cancellation, 44 hours with the case, and a 10-minute charge for 11 hours.',
   '[{"label":"Noise cancellation","value":"Active, up to 49 dB"},{"label":"Playback","value":"Up to 44 h with case"},{"label":"Fast charge","value":"10 min for 11 h"},{"label":"Drivers","value":"12.4 mm titanium"},{"label":"Water resistance","value":"IP55"},{"label":"Warranty","value":"1 year OnePlus"}]', true),
  ('apple-airpods-4', 'Apple AirPods 4', 'apple', 'earbuds-headphones',
   'Redesigned for comfort, with Personalised Spatial Audio and a USB-C case.',
   '[{"label":"Chip","value":"H2"},{"label":"Playback","value":"Up to 30 h with case"},{"label":"Audio","value":"Personalised Spatial Audio, Adaptive EQ"},{"label":"Charging","value":"USB-C"},{"label":"Water resistance","value":"IP54"},{"label":"Warranty","value":"1 year Apple"}]', false),
  ('jbl-tune-520bt', 'JBL Tune 520BT Wireless Headphones', 'jbl', 'earbuds-headphones',
   'JBL Pure Bass sound, 57 hours of playback and a 5-minute charge for 3 more hours.',
   '[{"label":"Type","value":"On-ear, foldable"},{"label":"Playback","value":"Up to 57 h"},{"label":"Fast charge","value":"5 min for 3 h"},{"label":"Bluetooth","value":"5.3, multipoint"},{"label":"Warranty","value":"1 year JBL"}]', false),
  ('boat-rockerz-450', 'boAt Rockerz 450 Bluetooth Headphones', 'boat', 'earbuds-headphones',
   'Padded on-ear headphones with 15 hours of playback and a 3.5 mm cable for when the battery runs out.',
   '[{"label":"Type","value":"On-ear, adjustable"},{"label":"Playback","value":"Up to 15 h"},{"label":"Drivers","value":"40 mm"},{"label":"Modes","value":"Bluetooth 5.0 and AUX"},{"label":"Warranty","value":"1 year boAt"}]', false),
  -- power banks
  ('xiaomi-20000mah-33w-power-bank-4i', 'Xiaomi 20000 mAh 33W Power Bank 4i', 'xiaomi', 'power-banks',
   'Charges a phone about four times, and the phone and the bank fast-charge over USB-C.',
   '[{"label":"Capacity","value":"20000 mAh"},{"label":"Output","value":"33 W max, 2 x USB-A + 1 x USB-C"},{"label":"Input","value":"USB-C, 27 W"},{"label":"Weight","value":"434 g"},{"label":"Warranty","value":"6 months Xiaomi"}]', false),
  ('ambrane-stylo-pro-10000mah', 'Ambrane Stylo Pro 10000 mAh Power Bank', 'ambrane', 'power-banks',
   'Slim, light everyday power bank with 20 W fast charging, made in India.',
   '[{"label":"Capacity","value":"10000 mAh"},{"label":"Output","value":"20 W PD, 1 x USB-C + 2 x USB-A"},{"label":"Input","value":"USB-C or micro-USB"},{"label":"Weight","value":"230 g"},{"label":"Warranty","value":"180 days Ambrane"}]', false),
  ('anker-621-maggo-5000mah', 'Anker 621 MagGo Magnetic Battery (5000 mAh)', 'anker', 'power-banks',
   'Snaps onto the back of a MagSafe iPhone and charges it wirelessly, no cable needed.',
   '[{"label":"Capacity","value":"5000 mAh"},{"label":"Output","value":"7.5 W magnetic wireless"},{"label":"Input","value":"USB-C, 12 W"},{"label":"Works with","value":"iPhone 12 and later"},{"label":"Warranty","value":"18 months Anker"}]', false),
  ('samsung-10000mah-25w-battery-pack', 'Samsung 10000 mAh 25W Battery Pack', 'samsung', 'power-banks',
   'Super Fast Charging on the go for Galaxy phones, with two devices at once.',
   '[{"label":"Capacity","value":"10000 mAh"},{"label":"Output","value":"25 W USB-C PD + USB-C"},{"label":"Input","value":"USB-C, 25 W"},{"label":"Weight","value":"208 g"},{"label":"Warranty","value":"1 year Samsung"}]', false)
) p(slug, name, brand, category, description, specs, featured)
join public.brands b on b.slug = p.brand
join public.categories c on c.slug = p.category
on conflict (slug) do nothing;

insert into public.variants (product_id, sku, name, attributes, price_paise, mrp_paise, stock, sort)
select pr.id, v.sku, v.name, v.attributes::jsonb, v.price * 100, v.mrp * 100, v.stock, v.sort
from (values
  ('nokia-105-classic', 'NK-105C-CHR', 'Charcoal', '{"color":"Charcoal","color_hex":"#2E2E30"}', 999, 1199, 40, 0),
  ('nokia-105-classic', 'NK-105C-BLU', 'Blue', '{"color":"Blue","color_hex":"#2F5D8C"}', 999, 1199, 18, 1),
  ('nokia-110-4g-2024', 'NK-110-4G-CHR', 'Charcoal', '{"color":"Charcoal","color_hex":"#2E2E30"}', 2399, 2799, 12, 0),
  ('nokia-110-4g-2024', 'NK-110-4G-BLU', 'Blue', '{"color":"Blue","color_hex":"#3B6EA5"}', 2399, 2799, 3, 1),
  ('lava-a1-josh', 'LV-A1J-BLK', 'Black Blue', '{"color":"Black Blue","color_hex":"#1F2A3A"}', 1049, 1349, 35, 0),
  ('lava-a1-josh', 'LV-A1J-BRS', 'Black Red', '{"color":"Black Red","color_hex":"#5A1F24"}', 1049, 1349, 0, 1),
  ('itel-magic-x-play', 'IT-MXP-BLK', 'Black', '{"color":"Black","color_hex":"#1C1C1C"}', 1999, 2499, 9, 0),
  ('itel-magic-x-play', 'IT-MXP-LBL', 'Light Blue', '{"color":"Light Blue","color_hex":"#9CC3E6"}', 1999, 2499, 2, 1),
  ('jio-bharat-b1-4g', 'JIO-B1-BLK', 'Black', '{"color":"Black","color_hex":"#202020"}', 1299, 1299, 25, 0),
  ('apple-iphone-16-silicone-case-magsafe', 'APL-SC-IP16-DNM', 'Denim', '{"color":"Denim","color_hex":"#4C6A8E"}', 4900, 4900, 4, 0),
  ('apple-iphone-16-silicone-case-magsafe', 'APL-SC-IP16-BLK', 'Black', '{"color":"Black","color_hex":"#2B2B2B"}', 4900, 4900, 6, 1),
  ('apple-iphone-16-silicone-case-magsafe', 'APL-SC-IP16-PLM', 'Plum', '{"color":"Plum","color_hex":"#7A4A6B"}', 4900, 4900, 0, 2),
  ('spigen-tough-armor-galaxy-s25', 'SP-TA-S25-BLK', 'Black', '{"color":"Black","color_hex":"#1E1E1E"}', 1899, 3999, 14, 0),
  ('spigen-tough-armor-galaxy-s25', 'SP-TA-S25-GNM', 'Gunmetal', '{"color":"Gunmetal","color_hex":"#53565A"}', 1899, 3999, 5, 1),
  ('spigen-liquid-air-pixel-9a', 'SP-LA-P9A-MBK', 'Matte Black', '{"color":"Matte Black","color_hex":"#222222"}', 1199, 2499, 11, 0),
  ('oneplus-13-sandstone-magnetic-case', 'OP-13-SSC-BLK', 'Sandstone Black', '{"color":"Sandstone Black","color_hex":"#2A2A2A"}', 1499, 1999, 7, 0),
  ('spigen-glastr-ez-fit-iphone-16', 'SP-GEZ-IP16-2PK', '2 pack', '{}', 1499, 3199, 22, 0),
  ('spigen-glastr-slim-pixel-9a', 'SP-GLS-P9A-2PK', '2 pack', '{}', 999, 2199, 16, 0),
  ('spigen-neo-flex-oneplus-13', 'SP-NF-OP13-2PK', '2 pack', '{}', 1099, 2299, 1, 0),
  ('spigen-optik-lens-protector-iphone-16', 'SP-OPT-IP16-2PK', '2 pack', '{}', 899, 1799, 19, 0),
  ('samsung-25w-super-fast-charger', 'SAM-TA25-BLK', 'Black', '{"color":"Black","color_hex":"#1F1F1F"}', 1149, 1699, 24, 0),
  ('samsung-25w-super-fast-charger', 'SAM-TA25-WHT', 'White', '{"color":"White","color_hex":"#F4F4F4"}', 1149, 1699, 8, 1),
  ('apple-20w-usb-c-power-adapter', 'APL-20W-WHT', 'White', '{"color":"White","color_hex":"#F7F7F7"}', 1599, 1900, 15, 0),
  ('anker-322-usb-c-cable-1-8m', 'AN-322-CC18-BLK', 'Black', '{"color":"Black","color_hex":"#1E1E1E"}', 699, 1299, 30, 0),
  ('anker-322-usb-c-cable-1-8m', 'AN-322-CC18-WHT', 'White', '{"color":"White","color_hex":"#F2F2F2"}', 699, 1299, 12, 1),
  ('portronics-konnect-l-type-c-to-lightning', 'PT-KL-CL12-GRY', 'Grey', '{"color":"Grey","color_hex":"#7A7D80"}', 349, 899, 45, 0),
  ('oneplus-nord-buds-3-pro', 'OP-NB3P-SJD', 'Soft Jade', '{"color":"Soft Jade","color_hex":"#9FC5B5"}', 2799, 3299, 10, 0),
  ('oneplus-nord-buds-3-pro', 'OP-NB3P-SBK', 'Starry Black', '{"color":"Starry Black","color_hex":"#1D1F24"}', 2799, 3299, 6, 1),
  ('apple-airpods-4', 'APL-APD4-WHT', 'White', '{"color":"White","color_hex":"#F5F5F5"}', 12900, 12900, 3, 0),
  ('jbl-tune-520bt', 'JBL-T520-BLK', 'Black', '{"color":"Black","color_hex":"#1A1A1A"}', 2999, 4999, 9, 0),
  ('jbl-tune-520bt', 'JBL-T520-BLU', 'Blue', '{"color":"Blue","color_hex":"#2F5BA8"}', 2999, 4999, 4, 1),
  ('jbl-tune-520bt', 'JBL-T520-WHT', 'White', '{"color":"White","color_hex":"#EFEFEF"}', 2999, 4999, 0, 2),
  ('boat-rockerz-450', 'BT-RZ450-LBK', 'Luscious Black', '{"color":"Luscious Black","color_hex":"#1C1C1C"}', 1499, 3990, 20, 0),
  ('boat-rockerz-450', 'BT-RZ450-AQB', 'Aqua Blue', '{"color":"Aqua Blue","color_hex":"#2E8FB8"}', 1499, 3990, 7, 1),
  ('xiaomi-20000mah-33w-power-bank-4i', 'XI-PB4I-20K-BLK', 'Black', '{"color":"Black","color_hex":"#1F1F1F"}', 2199, 3999, 13, 0),
  ('xiaomi-20000mah-33w-power-bank-4i', 'XI-PB4I-20K-WHT', 'White', '{"color":"White","color_hex":"#F3F3F3"}', 2199, 3999, 2, 1),
  ('ambrane-stylo-pro-10000mah', 'AM-STP-10K-BLK', 'Black', '{"color":"Black","color_hex":"#202020"}', 799, 1999, 28, 0),
  ('ambrane-stylo-pro-10000mah', 'AM-STP-10K-BLU', 'Blue', '{"color":"Blue","color_hex":"#2C4F8C"}', 799, 1999, 9, 1),
  ('anker-621-maggo-5000mah', 'AN-621-MG5K-WHT', 'Ice White', '{"color":"Ice White","color_hex":"#F0F2F4"}', 2999, 4999, 5, 0),
  ('samsung-10000mah-25w-battery-pack', 'SAM-EBP10-GRY', 'Grey', '{"color":"Grey","color_hex":"#6E7074"}', 1999, 2999, 0, 0)
) v(product, sku, name, attributes, price, mrp, stock, sort)
join public.products pr on pr.slug = v.product
on conflict (sku) do nothing;

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
