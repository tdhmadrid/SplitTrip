import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RESEND_KEY = Deno.env.get('RESEND_API_KEY') ?? '';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    }});
  }

  try {
    const { to, inviter, trip_name, trip_dest, trip_emoji, join_url } = await req.json();

    const html = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:20px;">
<div style="max-width:500px;margin:0 auto;background:#0A0F1E;border-radius:16px;padding:32px;text-align:center;">
  <div style="font-size:48px;margin-bottom:12px;">${trip_emoji}</div>
  <h2 style="color:#F5F7FF;font-size:22px;margin:0 0 8px;">¡Te invitan a un viaje!</h2>
  <p style="color:rgba(245,247,255,0.6);margin:0 0 20px;font-size:15px;">
    <strong style="color:#FF5C3A;">${inviter}</strong> te invita a unirte a
  </p>
  <div style="background:rgba(255,92,58,0.15);border:1px solid rgba(255,92,58,0.3);border-radius:12px;padding:18px;margin-bottom:24px;">
    <div style="color:#F5F7FF;font-size:18px;font-weight:700;">${trip_name}</div>
    <div style="color:rgba(245,247,255,0.5);font-size:13px;margin-top:4px;">📍 ${trip_dest}</div>
  </div>
  <a href="${join_url}" style="display:inline-block;background:#FF5C3A;color:#fff;text-decoration:none;padding:13px 28px;border-radius:10px;font-weight:700;font-size:15px;">
    Unirme al viaje →
  </a>
  <p style="color:rgba(245,247,255,0.3);font-size:11px;margin-top:20px;">${join_url}</p>
</div>
</body></html>`;

    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'SplitTrip <onboarding@resend.dev>',
        to: [to],
        subject: `${inviter} te invita a ${trip_emoji} ${trip_name} — SplitTrip`,
        html,
      }),
    });

    const data = await r.json();
    return new Response(JSON.stringify(data), {
      status: r.ok ? 200 : 500,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
    });

  } catch(e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
    });
  }
});
