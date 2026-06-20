# 👻 GhostMessage — Anonymous Messaging Platform

> **Send truth. Stay hidden. Go ghost.**

GhostMessage is an anonymous messaging platform built with HTML, CSS, and JavaScript on the frontend, backed by **Supabase** (PostgreSQL) for real accounts, real messages, and real-time delivery. Users create a free account, get a unique anonymous link, share it, and receive honest messages — the sender is **never** revealed.

---

## ⚡ Setup (Do This First)

This project requires a Supabase project before it will work. It takes about 5 minutes:

1. Go to [supabase.com](https://supabase.com) and create a free project.
2. Open **SQL Editor** in your Supabase dashboard → New Query.
3. Paste the entire contents of `supabase_schema.sql` (included in this folder) and click **Run**.
4. Go to **Settings → API** and copy your **Project URL** and **anon public** key.
5. Open `SUPABASE_KEYS_GO_HERE.js` in this folder, paste your keys in.
6. Copy that exact same URL and key into the `<script>` block near the top of **every** HTML file (look for the comment `SUPABASE CONFIG — PASTE YOUR KEYS HERE` in: `index.html`, `signup.html`, `login.html`, `dashboard.html`, `message.html`, `settings.html`, `admin.html`).
7. **Important:** change the default admin password immediately. In the Supabase SQL Editor, run:
   ```sql
   update public.admin_config set admin_password_hash = crypt('YourNewSecurePassword', gen_salt('bf')) where id = 1;
   ```
   The default password is `changeme123` — don't leave it like that.
8. Open `index.html` in a browser (or deploy — see below). You're live.

---

## 🚀 Features

- ✅ Beautiful animated landing page with ghost theme
- ✅ Signup & Login backed by **Supabase** (no email required — username + password only)
- ✅ Passwords hashed server-side with bcrypt (via `pgcrypto`) — never stored in plaintext
- ✅ Personal anonymous message link per user
- ✅ Full message dashboard with read/unread/delete, all synced to the database
- ✅ **Realtime** new-message notifications via Supabase subscriptions
- ✅ Dashboard statistics (total, unread, read, real link visits)
- ✅ First-time walkthrough tutorial modal
- ✅ Copy link & Share to WhatsApp buttons
- ✅ Spam protection (30-second cooldown between sends)
- ✅ Profile customization (display name, avatar color)
- ✅ Password change in settings
- ✅ Toggle preferences (sounds, animations, notifications)
- ✅ Delete account / clear all messages
- ✅ Confetti animation on success events
- ✅ Toast notification system
- ✅ Mobile-responsive with **left-sliding** hamburger menu
- ✅ Animated particle backgrounds
- ✅ Floating ghost animations
- ✅ Page loading screen
- ✅ AI-powered chatbot (GhostBot) on every page
- ✅ Terms of Service page
- ✅ Privacy Policy page
- ✅ 404 page with auto-redirect
- ✅ **Admin Control Center** (`admin.html`) — password-protected dashboard to view all users, all messages, platform stats, ban/delete users, delete any message, and manage the admin password
- ✅ Row Level Security (RLS) enforced at the database level — direct table access is blocked; everything goes through verified server-side functions
- ✅ WhatsApp float button
- ✅ SEO meta tags on all pages

---

## 📁 File Structure

```
ghostmessage/
├── index.html                  ← Landing page
├── signup.html                 ← Registration page (Supabase)
├── login.html                  ← Login page (Supabase)
├── dashboard.html               ← User inbox & stats (Supabase + Realtime)
├── message.html                 ← Anonymous send page (Supabase)
├── settings.html                 ← Profile settings (Supabase)
├── admin.html                    ← Admin Control Center (password-gated)
├── terms.html                    ← Terms of Service
├── privacy.html                  ← Privacy Policy
├── setup.html                    ← Developer reference guide (not linked in nav)
├── 404.html                      ← 404 error page
├── supabase_schema.sql           ← Run this in Supabase SQL Editor first!
├── SUPABASE_KEYS_GO_HERE.js      ← Reference file for your keys
├── logo.png                       ← GhostMessage logo
└── README.md                      ← This file
```

---

## 🗄️ How the Database Works

GhostMessage uses two main tables:

- **`users`** — username, hashed password, display name, avatar settings, preferences, ban status, link visit count.
- **`messages`** — recipient username, message text, read status, timestamp.

**Security model:** Since this uses simple username+password (not Supabase Auth), Row Level Security blocks all direct table reads/writes from the browser. Instead, every action goes through a Postgres function (RPC) that verifies the password server-side first:

| Function | Purpose |
|---|---|
| `gm_signup` | Create a new account |
| `gm_login` | Verify credentials, return profile |
| `gm_get_profile` | Public profile lookup for message.html (no password needed) |
| `gm_send_message` | Anyone can call this — it's how anonymous sending works |
| `gm_get_messages` | Requires password — returns only that user's messages |
| `gm_mark_read` / `gm_delete_message` / `gm_clear_messages` | Requires password |
| `gm_update_profile` / `gm_change_password` / `gm_delete_account` | Requires password |
| `gm_admin_*` | Requires the separate admin password — full platform visibility |

This means even if someone inspects the browser's network requests, they cannot read another user's messages without that user's actual password — the anonymity and privacy guarantees are enforced by the database, not just hidden in the UI.

---

## 🛡️ Admin Control Center

Visit `admin.html` and enter your admin password (set in step 7 of Setup) to access:

- **Overview** — total users, total messages, unread count, total link visits, signups today, messages today, most recent users
- **Users** — search, view message counts, view link visits, ban/unban, delete any account
- **Messages** — search and view every message sent on the platform, delete any message
- **Admin Settings** — change your admin password

This page is intentionally **not linked anywhere in the public navigation** — bookmark it yourself. It's also excluded from search engines via a `noindex` meta tag.

---

## 🌐 Deploy Online (Free)

| Platform | Steps | Domain |
|----------|-------|--------|
| **Vercel** | Drag folder to vercel.com | yoursite.vercel.app |
| **Netlify** | Drag to app.netlify.com/drop | yoursite.netlify.app |
| **GitHub Pages** | Push to GitHub → Settings → Pages | username.github.io/repo |
| **Cloudflare Pages** | Connect GitHub repo | yoursite.pages.dev |

### Vercel CLI (fastest):
```bash
npm install -g vercel
cd ghostmessage
vercel
```

Since Supabase keys are pasted directly into the HTML, no environment variables or build step are needed — any static host works.

---

## 🎨 Customization

### Change Colors
Edit the `:root` CSS variables in each file:
```css
:root {
  --red:    #e63946;   /* Main accent color */
  --green:  #2dc653;   /* Success/CTA color */
  --yellow: #ffd60a;   /* Highlight color */
  --dark:   #0a0a0f;   /* Background */
}
```

### Change Platform Name
Find & Replace (Ctrl+Shift+H in VS Code):
- Find: `GhostMessage` → Replace with your name
- Find: `GhostBot` → Replace with your bot name

### Change Developer Contact
- Find: `0554196068` → Replace with your number
- Find: `Ibratech` → Replace with your brand
- Find: `Ibrahim Mohammed Lotsu` → Replace with your name

### Replace Logo
Just drop a new `logo.png` in the project root — all pages reference it automatically.

---

## 🤖 GhostBot (AI Chatbot)

Every page has GhostBot — an AI chatbot powered by the Anthropic Claude API. It:
- Answers questions about GhostMessage
- Guides users through features
- Redirects unanswerable questions to WhatsApp (+233554196068)

The chatbot uses `claude-sonnet-4-6` via the `/v1/messages` API endpoint.

---

## 💰 Monetization Ideas

| Idea | Description |
|------|-------------|
| **Premium Accounts** | "Ghost Pro" — custom link slug, analytics, history export |
| **Google AdSense** | Non-intrusive ads on the message sending page |
| **Custom Themes** | Sell ghost avatar packs and profile themes |
| **Business Plans** | School/company anonymous feedback portals |
| **Sponsored Messages** | Partner with local brands for sponsored placements |

---

## 📱 Mobile Support

GhostMessage is fully responsive with:
- **Left-sliding** hamburger menu on mobile (not top-down)
- Touch-friendly buttons and inputs
- Responsive grid layouts
- Mobile-optimized chatbot panel and admin tables

---

## 🛡️ Privacy & Anonymity

- Sender identity is **never stored or logged**
- Passwords are hashed with bcrypt — never stored in plaintext, never sent back to the browser
- Row Level Security blocks direct database access; all reads/writes are verified server-side
- No tracking scripts or advertising cookies
- Admin page is unlisted and noindexed, protected by its own separate password

---

## 👨‍💻 Developer Credits

**Built by Ibrahim Mohammed Lotsu**
**Brand:** Ibratech
**WhatsApp:** [+233 554 196 068](https://wa.me/233554196068)
**Portfolio:** [ibratech-dev.vercel.app](https://ibratech-dev.vercel.app)
**Location:** Accra, Ghana 🇬🇭

> *Where Accounting Meets Technology* 🚀

---

## 📄 Legal

- [Terms of Service](terms.html)
- [Privacy Policy](privacy.html)

---

© 2025 GhostMessage. All rights reserved. Built with ❤️ in Ghana.
