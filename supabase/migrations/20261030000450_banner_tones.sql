-- Six banner colours instead of three: plum, indigo and rose join peacock, marigold and emerald (the app's
-- heroGradients, in that order).
alter table public.banners drop constraint banners_tone_check;
alter table public.banners add constraint banners_tone_check check (tone between 0 and 5);
