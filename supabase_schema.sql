-- ============================================================
-- SplitTrip — Supabase Schema v2 (fixed dependency order)
-- ============================================================

create extension if not exists "uuid-ossp";

-- ============================================================
-- STEP 1: TABLES (sin policies todavía)
-- ============================================================

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text unique not null,
  name         text,
  avatar_url   text,
  avatar_color text default '#FF5C3A',
  created_at   timestamptz default now()
);

create table if not exists public.trips (
  id           uuid primary key default uuid_generate_v4(),
  name         text not null,
  destination  text not null,
  emoji        text default '🏖',
  status       text default 'planning' check (status in ('planning','active','done')),
  start_date   date,
  end_date     date,
  owner_id     uuid references public.profiles(id) on delete cascade,
  invite_code  text unique default upper(substr(md5(random()::text), 1, 8)),
  created_at   timestamptz default now()
);

create table if not exists public.trip_members (
  id        uuid primary key default uuid_generate_v4(),
  trip_id   uuid references public.trips(id) on delete cascade,
  user_id   uuid references public.profiles(id) on delete cascade,
  role      text default 'member' check (role in ('owner','member')),
  joined_at timestamptz default now(),
  unique(trip_id, user_id)
);

create table if not exists public.trip_invitations (
  id         uuid primary key default uuid_generate_v4(),
  trip_id    uuid references public.trips(id) on delete cascade,
  email      text not null,
  invited_by uuid references public.profiles(id),
  token      text unique default uuid_generate_v4()::text,
  status     text default 'pending' check (status in ('pending','accepted','expired')),
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '7 days'),
  unique(trip_id, email)
);

create table if not exists public.expenses (
  id          uuid primary key default uuid_generate_v4(),
  trip_id     uuid references public.trips(id) on delete cascade,
  description text not null,
  amount      numeric(10,2) not null check (amount > 0),
  category    text default '🍽',
  paid_by     uuid references public.profiles(id),
  date        date default current_date,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz default now()
);

create table if not exists public.expense_splits (
  id         uuid primary key default uuid_generate_v4(),
  expense_id uuid references public.expenses(id) on delete cascade,
  user_id    uuid references public.profiles(id),
  amount     numeric(10,2) not null,
  is_paid    boolean default false,
  paid_at    timestamptz
);

create table if not exists public.settlements (
  id         uuid primary key default uuid_generate_v4(),
  trip_id    uuid references public.trips(id) on delete cascade,
  from_user  uuid references public.profiles(id),
  to_user    uuid references public.profiles(id),
  amount     numeric(10,2) not null,
  note       text,
  settled_at timestamptz default now(),
  created_by uuid references public.profiles(id)
);

create table if not exists public.itinerary_items (
  id             uuid primary key default uuid_generate_v4(),
  trip_id        uuid references public.trips(id) on delete cascade,
  name           text not null,
  icon           text default '📍',
  day_number     integer not null,
  start_time     time,
  cost_estimate  numeric(10,2) default 0,
  notes          text,
  created_by     uuid references public.profiles(id),
  created_at     timestamptz default now()
);

create table if not exists public.messages (
  id         uuid primary key default uuid_generate_v4(),
  trip_id    uuid references public.trips(id) on delete cascade,
  user_id    uuid references public.profiles(id),
  content    text not null,
  created_at timestamptz default now()
);

-- ============================================================
-- STEP 2: ENABLE RLS
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.trips             enable row level security;
alter table public.trip_members      enable row level security;
alter table public.trip_invitations  enable row level security;
alter table public.expenses          enable row level security;
alter table public.expense_splits    enable row level security;
alter table public.settlements       enable row level security;
alter table public.itinerary_items   enable row level security;
alter table public.messages          enable row level security;

-- ============================================================
-- STEP 3: POLICIES — profiles
-- ============================================================

create policy "profiles_select_all"
  on public.profiles for select using (true);

create policy "profiles_insert_own"
  on public.profiles for insert with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update using (auth.uid() = id);

-- ============================================================
-- STEP 4: POLICIES — trips
-- (now trip_members exists, so the subquery works)
-- ============================================================

create policy "trips_select_member"
  on public.trips for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = id and tm.user_id = auth.uid()
    )
  );

create policy "trips_insert_auth"
  on public.trips for insert
  with check (auth.uid() = owner_id);

create policy "trips_update_owner"
  on public.trips for update
  using (owner_id = auth.uid());

create policy "trips_delete_owner"
  on public.trips for delete
  using (owner_id = auth.uid());

-- ============================================================
-- STEP 5: POLICIES — trip_members
-- ============================================================

create policy "members_select"
  on public.trip_members for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = trip_members.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "members_insert_self"
  on public.trip_members for insert
  with check (auth.uid() = user_id);

create policy "members_delete_owner"
  on public.trip_members for delete
  using (
    exists (
      select 1 from public.trips t
      where t.id = trip_members.trip_id and t.owner_id = auth.uid()
    )
  );

-- ============================================================
-- STEP 6: POLICIES — trip_invitations
-- ============================================================

create policy "invitations_select"
  on public.trip_invitations for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = trip_invitations.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "invitations_insert"
  on public.trip_invitations for insert
  with check (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = trip_invitations.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "invitations_update"
  on public.trip_invitations for update
  using (true);

-- ============================================================
-- STEP 7: POLICIES — expenses
-- ============================================================

create policy "expenses_select"
  on public.expenses for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = expenses.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "expenses_insert"
  on public.expenses for insert
  with check (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = expenses.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "expenses_update"
  on public.expenses for update
  using (created_by = auth.uid());

create policy "expenses_delete"
  on public.expenses for delete
  using (created_by = auth.uid());

-- ============================================================
-- STEP 8: POLICIES — expense_splits
-- ============================================================

create policy "splits_select"
  on public.expense_splits for select
  using (
    exists (
      select 1 from public.expenses e
      join public.trip_members tm on tm.trip_id = e.trip_id
      where e.id = expense_splits.expense_id and tm.user_id = auth.uid()
    )
  );

create policy "splits_insert"
  on public.expense_splits for insert
  with check (
    exists (
      select 1 from public.expenses e
      join public.trip_members tm on tm.trip_id = e.trip_id
      where e.id = expense_splits.expense_id and tm.user_id = auth.uid()
    )
  );

create policy "splits_update_own"
  on public.expense_splits for update
  using (user_id = auth.uid());

-- ============================================================
-- STEP 9: POLICIES — settlements
-- ============================================================

create policy "settlements_select"
  on public.settlements for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = settlements.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "settlements_insert"
  on public.settlements for insert
  with check (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = settlements.trip_id and tm.user_id = auth.uid()
    )
  );

-- ============================================================
-- STEP 10: POLICIES — itinerary_items
-- ============================================================

create policy "itin_select"
  on public.itinerary_items for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = itinerary_items.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "itin_insert"
  on public.itinerary_items for insert
  with check (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = itinerary_items.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "itin_update"
  on public.itinerary_items for update
  using (created_by = auth.uid());

create policy "itin_delete"
  on public.itinerary_items for delete
  using (created_by = auth.uid());

-- ============================================================
-- STEP 11: POLICIES — messages
-- ============================================================

create policy "messages_select"
  on public.messages for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = messages.trip_id and tm.user_id = auth.uid()
    )
  );

create policy "messages_insert"
  on public.messages for insert
  with check (
    auth.uid() = user_id and
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = messages.trip_id and tm.user_id = auth.uid()
    )
  );

-- ============================================================
-- STEP 12: AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- STEP 13: REALTIME
-- ============================================================

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.expenses;
alter publication supabase_realtime add table public.expense_splits;
alter publication supabase_realtime add table public.settlements;
alter publication supabase_realtime add table public.itinerary_items;

-- ============================================================
-- STEP 14: VIEWS
-- ============================================================

create or replace view public.trip_summary as
select
  t.id,
  t.name,
  t.destination,
  t.emoji,
  t.status,
  t.start_date,
  t.end_date,
  t.invite_code,
  t.owner_id,
  t.created_at,
  count(distinct tm.user_id)  as member_count,
  coalesce(sum(e.amount), 0)  as total_spent,
  count(distinct e.id)        as expense_count
from public.trips t
left join public.trip_members tm on tm.trip_id = t.id
left join public.expenses e      on e.trip_id  = t.id
group by t.id;
