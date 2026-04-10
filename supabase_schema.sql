-- ============================================================
-- SplitTrip — Supabase Schema
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================================
-- PROFILES (extends auth.users)
-- ============================================================
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text unique not null,
  name        text,
  avatar_url  text,
  avatar_color text default '#FF5C3A',
  created_at  timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view all profiles"
  on public.profiles for select using (true);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- TRIPS
-- ============================================================
create table public.trips (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  destination text not null,
  emoji       text default '🏖',
  status      text default 'planning' check (status in ('planning','active','done')),
  start_date  date,
  end_date    date,
  owner_id    uuid references public.profiles(id) on delete cascade,
  invite_code text unique default substr(md5(random()::text), 1, 8),
  created_at  timestamptz default now()
);

alter table public.trips enable row level security;

create policy "Trip members can view trips"
  on public.trips for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = trips.id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Owner can update trip"
  on public.trips for update
  using (owner_id = auth.uid());

create policy "Authenticated users can create trips"
  on public.trips for insert
  with check (auth.uid() = owner_id);

create policy "Owner can delete trip"
  on public.trips for delete
  using (owner_id = auth.uid());

-- ============================================================
-- TRIP MEMBERS
-- ============================================================
create table public.trip_members (
  id        uuid primary key default uuid_generate_v4(),
  trip_id   uuid references public.trips(id) on delete cascade,
  user_id   uuid references public.profiles(id) on delete cascade,
  role      text default 'member' check (role in ('owner','member')),
  joined_at timestamptz default now(),
  unique(trip_id, user_id)
);

alter table public.trip_members enable row level security;

create policy "Members can view trip members"
  on public.trip_members for select
  using (
    exists (
      select 1 from public.trip_members tm
      where tm.trip_id = trip_members.trip_id
      and tm.user_id = auth.uid()
    )
  );

create policy "Owner can manage members"
  on public.trip_members for all
  using (
    exists (
      select 1 from public.trips
      where trips.id = trip_members.trip_id
      and trips.owner_id = auth.uid()
    )
  );

create policy "Users can join via invite"
  on public.trip_members for insert
  with check (auth.uid() = user_id);

-- ============================================================
-- TRIP INVITATIONS (email invites)
-- ============================================================
create table public.trip_invitations (
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

alter table public.trip_invitations enable row level security;

create policy "Trip members can view invitations"
  on public.trip_invitations for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = trip_invitations.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Trip members can create invitations"
  on public.trip_invitations for insert
  with check (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = trip_invitations.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

-- ============================================================
-- EXPENSES
-- ============================================================
create table public.expenses (
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

alter table public.expenses enable row level security;

create policy "Trip members can view expenses"
  on public.expenses for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = expenses.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Trip members can add expenses"
  on public.expenses for insert
  with check (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = expenses.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Expense creator can update/delete"
  on public.expenses for update using (created_by = auth.uid());

create policy "Expense creator can delete"
  on public.expenses for delete using (created_by = auth.uid());

-- ============================================================
-- EXPENSE SPLITS (who owes what per expense)
-- ============================================================
create table public.expense_splits (
  id         uuid primary key default uuid_generate_v4(),
  expense_id uuid references public.expenses(id) on delete cascade,
  user_id    uuid references public.profiles(id),
  amount     numeric(10,2) not null,
  is_paid    boolean default false,
  paid_at    timestamptz
);

alter table public.expense_splits enable row level security;

create policy "Trip members can view splits"
  on public.expense_splits for select
  using (
    exists (
      select 1 from public.expenses e
      join public.trip_members tm on tm.trip_id = e.trip_id
      where e.id = expense_splits.expense_id
      and tm.user_id = auth.uid()
    )
  );

create policy "Trip members can insert splits"
  on public.expense_splits for insert
  with check (
    exists (
      select 1 from public.expenses e
      join public.trip_members tm on tm.trip_id = e.trip_id
      where e.id = expense_splits.expense_id
      and tm.user_id = auth.uid()
    )
  );

create policy "Users can update own splits"
  on public.expense_splits for update
  using (user_id = auth.uid());

-- ============================================================
-- SETTLEMENTS (liquidaciones)
-- ============================================================
create table public.settlements (
  id          uuid primary key default uuid_generate_v4(),
  trip_id     uuid references public.trips(id) on delete cascade,
  from_user   uuid references public.profiles(id),
  to_user     uuid references public.profiles(id),
  amount      numeric(10,2) not null,
  note        text,
  settled_at  timestamptz default now(),
  created_by  uuid references public.profiles(id)
);

alter table public.settlements enable row level security;

create policy "Trip members can view settlements"
  on public.settlements for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = settlements.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Trip members can add settlements"
  on public.settlements for insert
  with check (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = settlements.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

-- ============================================================
-- ITINERARY ITEMS
-- ============================================================
create table public.itinerary_items (
  id          uuid primary key default uuid_generate_v4(),
  trip_id     uuid references public.trips(id) on delete cascade,
  name        text not null,
  icon        text default '📍',
  day_number  integer not null,
  start_time  time,
  cost_estimate numeric(10,2) default 0,
  notes       text,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz default now()
);

alter table public.itinerary_items enable row level security;

create policy "Trip members can view itinerary"
  on public.itinerary_items for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = itinerary_items.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Trip members can add itinerary items"
  on public.itinerary_items for insert
  with check (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = itinerary_items.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Creator can update/delete"
  on public.itinerary_items for update using (created_by = auth.uid());
create policy "Creator can delete"
  on public.itinerary_items for delete using (created_by = auth.uid());

-- ============================================================
-- CHAT MESSAGES
-- ============================================================
create table public.messages (
  id         uuid primary key default uuid_generate_v4(),
  trip_id    uuid references public.trips(id) on delete cascade,
  user_id    uuid references public.profiles(id),
  content    text not null,
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

create policy "Trip members can view messages"
  on public.messages for select
  using (
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = messages.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

create policy "Trip members can send messages"
  on public.messages for insert
  with check (
    auth.uid() = user_id and
    exists (
      select 1 from public.trip_members
      where trip_members.trip_id = messages.trip_id
      and trip_members.user_id = auth.uid()
    )
  );

-- ============================================================
-- REALTIME
-- ============================================================
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.expenses;
alter publication supabase_realtime add table public.expense_splits;
alter publication supabase_realtime add table public.settlements;
alter publication supabase_realtime add table public.itinerary_items;

-- ============================================================
-- HELPER VIEWS
-- ============================================================

-- Balance view: net balance per user per trip
create or replace view public.trip_balances as
select
  e.trip_id,
  es.user_id,
  sum(case when e.paid_by = es.user_id then e.amount else 0 end) -
  sum(es.amount) as net_balance
from public.expense_splits es
join public.expenses e on e.id = es.expense_id
where es.is_paid = false
group by e.trip_id, es.user_id;

-- Trip summary view
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
  count(distinct tm.user_id) as member_count,
  coalesce(sum(e.amount), 0) as total_spent,
  count(distinct e.id) as expense_count
from public.trips t
left join public.trip_members tm on tm.trip_id = t.id
left join public.expenses e on e.trip_id = t.id
group by t.id;
