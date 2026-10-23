-- Vorschlag für Supabase/PostgreSQL; vor produktivem Einsatz prüfen und testen.
create extension if not exists pgcrypto;

create table if not exists public.kennels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.kennel_members (
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','editor','viewer')),
  created_at timestamptz not null default now(),
  primary key (kennel_id, user_id)
);

create or replace function public.is_kennel_member(target_kennel uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.kennel_members km
    where km.kennel_id = target_kennel and km.user_id = auth.uid()
  );
$$;

create table if not exists public.kennel_details (
  kennel_id uuid primary key references public.kennels(id) on delete cascade,
  member_of text, member_since date, protection_applied_on date,
  section11_since date, veterinary_office text,
  breeder_name text, street text, postal_city text, phone text, email text
);

create table if not exists public.dogs (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  name text not null, sex text check (sex in ('Hündin','Rüde')),
  birth_date date, registration_number text, chip_number text,
  color text, size text, weight text, hair_type text,
  entry_date date, exit_date date,
  status text, required_examinations text, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.litters (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dam_id uuid references public.dogs(id) on delete set null,
  sire_id uuid references public.dogs(id) on delete set null,
  litter_date date, mating_date date,
  sire_owner text, sire_registration_or_chip text,
  live_females integer default 0, live_males integer default 0,
  dead_females integer default 0, dead_males integer default 0,
  notes text, created_at timestamptz not null default now()
);

create table if not exists public.titles (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dog_id uuid references public.dogs(id) on delete set null,
  event_date date, location text, achievement text, rating text, judge text, notes text
);
create table if not exists public.ztp_records (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dog_id uuid references public.dogs(id) on delete set null,
  exam_date date, location text, examiner text, passed text, overall_appearance text, notes text
);
create table if not exists public.dewormings (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dog_id uuid references public.dogs(id) on delete set null,
  product text, administered_on date, next_due date, dosage text, notes text
);
create table if not exists public.vaccinations (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dog_id uuid references public.dogs(id) on delete set null,
  veterinarian text, vaccine_name text, administered_on date, valid_until date, next_due date, notes text
);
create table if not exists public.whelping_protocols (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  litter_id uuid references public.litters(id) on delete set null,
  dam_id uuid references public.dogs(id) on delete set null,
  sire_id uuid references public.dogs(id) on delete set null,
  litter_date date, mating_date date,
  dam_health_before text, dam_health_after text, dam_health_after_nursing text,
  litter_count integer, gestation_duration text, nursing_duration text,
  birth_course text, weights_at_birth text, weights_at_week_one text,
  weights_at_week_four text, weights_at_week_eight text,
  dewormed_on text, vaccinated_on text, observations text,
  inspected_by_breeder_advisor text, accepted_by text
);

-- Alle Zuchtbereiche werden nur Mitgliedern des jeweiligen Zuchtbetriebs gezeigt.
alter table public.kennels enable row level security;
alter table public.kennel_members enable row level security;
alter table public.kennel_details enable row level security;
alter table public.dogs enable row level security;
alter table public.litters enable row level security;
alter table public.titles enable row level security;
alter table public.ztp_records enable row level security;
alter table public.dewormings enable row level security;
alter table public.vaccinations enable row level security;
alter table public.whelping_protocols enable row level security;

create policy "members can read own kennels" on public.kennels
for select using (public.is_kennel_member(id));
create policy "members can read membership rows" on public.kennel_members
for select using (user_id = auth.uid() or public.is_kennel_member(kennel_id));

-- Schreibrechte: owner/editor; Leserechte: alle Rollen des Mandanten.
do $$
declare tbl text;
begin
  foreach tbl in array array['kennel_details','dogs','litters','titles','ztp_records','dewormings','vaccinations','whelping_protocols'] loop
    execute format('create policy "members read %1$s" on public.%1$I for select using (public.is_kennel_member(kennel_id))', tbl);
    execute format('create policy "editors write %1$s" on public.%1$I for all using (exists (select 1 from public.kennel_members km where km.kennel_id = %1$I.kennel_id and km.user_id = auth.uid() and km.role in (''owner'',''editor''))) with check (exists (select 1 from public.kennel_members km where km.kennel_id = %1$I.kennel_id and km.user_id = auth.uid() and km.role in (''owner'',''editor'')))', tbl);
  end loop;
end $$;

-- Hinweis: Diese SQL-Datei ist ein Startpunkt. Policies für Kennel-Erstellung,
-- Mitgliedereinladungen und Owner-Administration müssen ergänzend sicher umgesetzt
-- und mit mehreren Testkonten geprüft werden, bevor echte Daten eingetragen werden.


create table if not exists public.mating_calendar (
  id uuid primary key default gen_random_uuid(),
  kennel_id uuid not null references public.kennels(id) on delete cascade,
  dam_id uuid references public.dogs(id) on delete set null,
  sire_id uuid references public.dogs(id) on delete set null,
  mating_date date not null,
  gestation_days integer not null default 63 check (gestation_days between 1 and 100),
  estimated_birth_date date not null,
  notes text,
  created_at timestamptz not null default now()
);
alter table public.mating_calendar enable row level security;
create policy "members read mating calendar" on public.mating_calendar
for select using (public.is_kennel_member(kennel_id));
create policy "editors write mating calendar" on public.mating_calendar
for all using (exists (select 1 from public.kennel_members km where km.kennel_id = mating_calendar.kennel_id and km.user_id = auth.uid() and km.role in ('owner','editor')))
with check (exists (select 1 from public.kennel_members km where km.kennel_id = mating_calendar.kennel_id and km.user_id = auth.uid() and km.role in ('owner','editor')));
