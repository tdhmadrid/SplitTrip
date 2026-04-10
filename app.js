// ============================================================
// SplitTrip — app.js
// Core application logic + Supabase integration
// Replace SUPABASE_URL and SUPABASE_ANON_KEY with your values
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── CONFIG ──────────────────────────────────────────────────
const SUPABASE_URL  = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_KEY  = 'YOUR_ANON_KEY';
const APP_URL       = window.location.origin;

export const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

// ── STATE ────────────────────────────────────────────────────
export const ST = {
  user:    null,   // current auth user
  profile: null,   // current profile row
  trips:   [],     // user's trips
  cur:     null,   // active trip object
  members: [],     // members of cur trip
  expenses:[],     // expenses of cur trip
  splits:  [],     // splits of cur trip
  settles: [],     // settlements of cur trip
  itin:    [],     // itinerary items
  msgs:    [],     // chat messages
  theme:   localStorage.getItem('st_theme') || 'dark',
};

// ── THEME ────────────────────────────────────────────────────
export function applyTheme(t) {
  ST.theme = t;
  document.documentElement.setAttribute('data-theme', t);
  localStorage.setItem('st_theme', t);
  const btn = document.getElementById('theme-toggle');
  if (btn) btn.textContent = t === 'dark' ? '☀️' : '🌙';
}

// ── AUTH ─────────────────────────────────────────────────────
export async function signInWithEmail(email) {
  const { error } = await sb.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: APP_URL }
  });
  return error;
}

export async function signOut() {
  await sb.auth.signOut();
  ST.user = ST.profile = null;
  showView('auth');
}

export async function loadProfile() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return null;
  ST.user = user;
  const { data } = await sb.from('profiles').select('*').eq('id', user.id).single();
  ST.profile = data;
  return data;
}

export async function updateProfile(updates) {
  const { data, error } = await sb.from('profiles')
    .update(updates)
    .eq('id', ST.user.id)
    .select()
    .single();
  if (!error) ST.profile = data;
  return { data, error };
}

// ── TRIPS ────────────────────────────────────────────────────
export async function loadTrips() {
  // Get trips where user is a member
  const { data: memberRows } = await sb
    .from('trip_members')
    .select('trip_id')
    .eq('user_id', ST.user.id);

  if (!memberRows?.length) { ST.trips = []; return []; }

  const tripIds = memberRows.map(r => r.trip_id);
  const { data } = await sb
    .from('trip_summary')
    .select('*')
    .in('id', tripIds)
    .order('created_at', { ascending: false });

  ST.trips = data || [];
  return ST.trips;
}

export async function createTrip({ name, destination, emoji, start_date, end_date }) {
  const { data: trip, error } = await sb.from('trips').insert({
    name, destination, emoji, start_date, end_date,
    owner_id: ST.user.id,
    status: 'planning'
  }).select().single();

  if (error) return { error };

  // Add self as owner member
  await sb.from('trip_members').insert({
    trip_id: trip.id,
    user_id: ST.user.id,
    role: 'owner'
  });

  return { data: trip };
}

export async function joinTripByCode(code) {
  const { data: trip } = await sb
    .from('trips')
    .select('*')
    .eq('invite_code', code.toUpperCase())
    .single();

  if (!trip) return { error: 'Código inválido' };

  const { error } = await sb.from('trip_members').insert({
    trip_id: trip.id,
    user_id: ST.user.id,
    role: 'member'
  });

  return error ? { error: error.message } : { data: trip };
}

export async function joinTripByToken(token) {
  const { data: invite } = await sb
    .from('trip_invitations')
    .select('*, trips(*)')
    .eq('token', token)
    .eq('status', 'pending')
    .single();

  if (!invite) return { error: 'Invitación inválida o expirada' };
  if (new Date(invite.expires_at) < new Date()) return { error: 'Invitación expirada' };

  await sb.from('trip_members').upsert({
    trip_id: invite.trip_id,
    user_id: ST.user.id,
    role: 'member'
  }, { onConflict: 'trip_id,user_id' });

  await sb.from('trip_invitations')
    .update({ status: 'accepted' })
    .eq('id', invite.id);

  return { data: invite.trips };
}

// ── INVITATIONS ───────────────────────────────────────────────
export async function inviteByEmail(tripId, email) {
  // Check if already a member
  const { data: profile } = await sb
    .from('profiles')
    .select('id')
    .eq('email', email)
    .single();

  if (profile) {
    // Already registered → add directly
    const { error } = await sb.from('trip_members').upsert({
      trip_id: tripId, user_id: profile.id, role: 'member'
    }, { onConflict: 'trip_id,user_id' });
    if (error) return { error: error.message };
  }

  // Create invitation record (email sent via Supabase Edge Function or EmailJS)
  const { data: inv, error } = await sb.from('trip_invitations').upsert({
    trip_id: tripId,
    email,
    invited_by: ST.user.id
  }, { onConflict: 'trip_id,email' }).select().single();

  if (error) return { error: error.message };

  // Send email via EmailJS (configure in index.html)
  const trip = ST.trips.find(t => t.id === tripId) || ST.cur;
  await sendInviteEmail(email, inv.token, trip);

  return { data: inv };
}

async function sendInviteEmail(email, token, trip) {
  if (typeof emailjs === 'undefined') return;
  const joinUrl = `${APP_URL}?join=${token}`;
  try {
    await emailjs.send('YOUR_SERVICE_ID', 'YOUR_TEMPLATE_ID', {
      to_email:   email,
      trip_name:  trip?.name || 'un viaje',
      trip_dest:  trip?.destination || '',
      inviter:    ST.profile?.name || ST.profile?.email || 'Tu amigo/a',
      join_url:   joinUrl,
      trip_emoji: trip?.emoji || '✈️',
    });
  } catch(e) { console.warn('EmailJS error:', e); }
}

// ── MEMBERS ───────────────────────────────────────────────────
export async function loadMembers(tripId) {
  const { data } = await sb
    .from('trip_members')
    .select('*, profiles(*)')
    .eq('trip_id', tripId);
  ST.members = data || [];
  return ST.members;
}

// ── EXPENSES ─────────────────────────────────────────────────
export async function loadExpenses(tripId) {
  const { data } = await sb
    .from('expenses')
    .select('*, profiles!paid_by(id,name,email,avatar_color), expense_splits(*, profiles(id,name,email,avatar_color))')
    .eq('trip_id', tripId)
    .order('date', { ascending: false });
  ST.expenses = data || [];
  return ST.expenses;
}

export async function addExpense({ tripId, description, amount, category, paidBy, splitAmong, date }) {
  const { data: expense, error } = await sb.from('expenses').insert({
    trip_id:     tripId,
    description,
    amount,
    category,
    paid_by:     paidBy,
    date:        date || new Date().toISOString().split('T')[0],
    created_by:  ST.user.id
  }).select().single();

  if (error) return { error };

  // Create splits
  const perPerson = amount / splitAmong.length;
  const splitRows = splitAmong.map(userId => ({
    expense_id: expense.id,
    user_id:    userId,
    amount:     parseFloat(perPerson.toFixed(2))
  }));

  await sb.from('expense_splits').insert(splitRows);
  return { data: expense };
}

export async function deleteExpense(expenseId) {
  return sb.from('expenses').delete().eq('id', expenseId);
}

// ── BALANCES (computed client-side from expenses+splits) ──────
export function computeBalances() {
  const bal = {};
  ST.members.forEach(m => { bal[m.user_id] = 0; });

  ST.expenses.forEach(exp => {
    // Payer receives credit
    bal[exp.paid_by] = (bal[exp.paid_by] || 0) + Number(exp.amount);
    // Each split owes their share
    exp.expense_splits?.forEach(sp => {
      if (!sp.is_paid) bal[sp.user_id] = (bal[sp.user_id] || 0) - Number(sp.amount);
    });
  });

  return bal;
}

export function computeSettlements(balances) {
  const creditors = [], debtors = [];
  Object.entries(balances).forEach(([uid, bal]) => {
    if (bal > 0.01)  creditors.push({ uid, bal });
    else if (bal < -0.01) debtors.push({ uid, bal: -bal });
  });
  const tx = [];
  let ci = 0, di = 0;
  while (ci < creditors.length && di < debtors.length) {
    const c = creditors[ci], d = debtors[di];
    const amt = Math.min(c.bal, d.bal);
    tx.push({ from: d.uid, to: c.uid, amount: parseFloat(amt.toFixed(2)) });
    c.bal -= amt; d.bal -= amt;
    if (c.bal < 0.01) ci++;
    if (d.bal < 0.01) di++;
  }
  return tx;
}

export async function recordSettlement({ tripId, fromUser, toUser, amount, note }) {
  const { data, error } = await sb.from('settlements').insert({
    trip_id:    tripId,
    from_user:  fromUser,
    to_user:    toUser,
    amount,
    note,
    created_by: ST.user.id
  }).select().single();
  return { data, error };
}

// ── ITINERARY ─────────────────────────────────────────────────
export async function loadItinerary(tripId) {
  const { data } = await sb
    .from('itinerary_items')
    .select('*, profiles(name)')
    .eq('trip_id', tripId)
    .order('day_number').order('start_time');
  ST.itin = data || [];
  return ST.itin;
}

export async function addItineraryItem({ tripId, name, icon, day_number, start_time, cost_estimate, notes }) {
  return sb.from('itinerary_items').insert({
    trip_id: tripId, name, icon, day_number, start_time, cost_estimate, notes,
    created_by: ST.user.id
  }).select().single();
}

// ── MESSAGES (realtime) ───────────────────────────────────────
export async function loadMessages(tripId) {
  const { data } = await sb
    .from('messages')
    .select('*, profiles(id,name,email,avatar_color)')
    .eq('trip_id', tripId)
    .order('created_at')
    .limit(100);
  ST.msgs = data || [];
  return ST.msgs;
}

export async function sendMessage(tripId, content) {
  return sb.from('messages').insert({
    trip_id: tripId,
    user_id: ST.user.id,
    content
  });
}

let msgChannel = null;
export function subscribeMessages(tripId, onNew) {
  if (msgChannel) sb.removeChannel(msgChannel);
  msgChannel = sb.channel(`messages:${tripId}`)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'messages',
      filter: `trip_id=eq.${tripId}`
    }, payload => onNew(payload.new))
    .subscribe();
}

// ── UTILS ─────────────────────────────────────────────────────
export const COLORS = ['#FF5C3A','#39E07B','#38BDF8','#A78BFA','#FFBC40','#F472B6','#34D399','#FB923C'];

export function fmt(n) {
  return new Intl.NumberFormat('es-ES',{
    style:'currency', currency:'EUR',
    minimumFractionDigits:0, maximumFractionDigits:2
  }).format(n);
}

export function fmtDate(d) {
  if (!d) return '';
  const dt = new Date(d + 'T00:00:00');
  return dt.toLocaleDateString('es-ES', { day:'numeric', month:'short' });
}

export function initials(name, email) {
  const n = name || email || '?';
  return n.split(' ').map(w => w[0]).join('').toUpperCase().slice(0,2);
}

export function avatarStyle(profile, idx=0) {
  const color = profile?.avatar_color || COLORS[idx % COLORS.length];
  return `background:${color}22;color:${color};border:2px solid ${color}44`;
}

// ── VIEW ROUTER ───────────────────────────────────────────────
export function showView(name) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('on'));
  const el = document.getElementById(`view-${name}`);
  if (el) el.classList.add('on');
}
