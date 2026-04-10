# SplitTrip — Guía de configuración completa

## Stack
- **Frontend**: HTML + CSS + Vanilla JS (ES Modules)
- **Backend**: Supabase (Auth, DB, Realtime)
- **Email**: EmailJS (invitaciones)
- **Deploy**: GitHub Pages (estático)

---

## 1. Supabase — Crear proyecto

1. Ve a https://supabase.com y crea un proyecto nuevo
2. Anota tu **Project URL** y tu **anon/public key**
3. En el SQL Editor, copia y pega todo el contenido de `supabase_schema.sql` y ejecútalo

---

## 2. Configurar Auth en Supabase

En **Authentication > URL Configuration**:

- **Site URL**: `https://tdhmadrid.github.io/SplitTrip`
- **Redirect URLs** (añadir):
  - `https://tdhmadrid.github.io/SplitTrip`
  - `http://localhost:3000` (para desarrollo local)

En **Authentication > Email Templates**, puedes personalizar el email de magic link.

---

## 3. EmailJS — Invitaciones por correo

1. Ve a https://emailjs.com y crea una cuenta gratuita (200 emails/mes gratis)
2. Crea un **Email Service** (Gmail, Outlook, etc.)
3. Crea un **Email Template** con las siguientes variables:

```
Asunto: {{inviter}} te invita a {{trip_emoji}} {{trip_name}}

Cuerpo:
Hola,

{{inviter}} te ha invitado al viaje "{{trip_name}}" a {{trip_dest}}.

Únete aquí y empieza a ver el itinerario, los gastos del grupo y el chat:

👉 {{join_url}}

— SplitTrip
```

4. Anota tu **Service ID**, **Template ID** y **Public Key**

---

## 4. Configurar variables en index.html

Busca en `index.html` las siguientes líneas y reemplaza:

```js
// En el <script> de EmailJS (cabecera):
emailjs.init({ publicKey: "YOUR_EMAILJS_PUBLIC_KEY" });

// En el módulo principal:
const SURL = 'https://YOUR_PROJECT.supabase.co';
const SKEY = 'YOUR_ANON_KEY';

// En las llamadas emailjs.send():
emailjs.send('YOUR_SERVICE_ID', 'YOUR_TEMPLATE_ID', {...})
```

---

## 5. Deploy en GitHub Pages

```bash
# Crear repo
git init
git add .
git commit -m "Initial SplitTrip"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/splittrip.git
git push -u origin main
```

En GitHub > Settings > Pages:
- Source: Deploy from branch
- Branch: `main` / `/(root)`

La app estará en: `https://TU_USUARIO.github.io/splittrip/`

---

## 6. Flujo de invitación por email

```
1. Usuario A crea viaje → añade email de Usuario B
2. SplitTrip crea registro en `trip_invitations` con token único
3. EmailJS envía email a Usuario B con link: 
   https://tu-app.com?join=TOKEN_UNICO
4. Usuario B hace clic → abre la app
5. Si no está registrado → entra su email → recibe magic link
6. Al iniciar sesión, la app detecta el token en la URL
7. Se une automáticamente al viaje
8. Invitation queda marcada como 'accepted'
```

---

## 7. Flujo de código de invitación

Alternativa más simple: el organizador comparte el **código de 8 caracteres** 
(visible en la sección Miembros del viaje) por WhatsApp, Telegram, etc.

El invitado:
1. Abre la app
2. Introduce su email
3. En "¿Tienes un código?" pega el código
4. Se une automáticamente tras verificar su email

---

## 8. Variables de entorno (opcional para producción)

Si usas Vite u otro bundler, puedes usar `.env`:

```env
VITE_SUPABASE_URL=https://xxx.supabase.co
VITE_SUPABASE_KEY=eyJ...
VITE_EMAILJS_KEY=xxx
VITE_EMAILJS_SERVICE=service_xxx
VITE_EMAILJS_TEMPLATE=template_xxx
```

---

## 9. Próximas funcionalidades (roadmap)

- [ ] Marketplace real con APIs (Booking, Skyscanner, Viator)
- [ ] Notificaciones push (nuevos gastos, mensajes)
- [ ] Exportar resumen del viaje a PDF
- [ ] Integración WhatsApp Business para invitar
- [ ] Recordatorios de pago automáticos
- [ ] Fotos del viaje compartidas
- [ ] Encuestas de grupo (¿hotel A o B?)
- [ ] Calculadora de propinas por país

---

## Estructura de archivos

```
splittrip/
├── index.html          ← App completa (single file)
├── app.js              ← Módulo de lógica reutilizable
├── supabase_schema.sql ← Schema de base de datos
└── README.md           ← Esta guía
```
