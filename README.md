# Punch Clock – attendance app (GitHub Pages + Firebase)

- `index.html` – employee app. Installs on the phone like an app. Sign up with name + mobile + email, log in with mobile **or** email, punch in / punch out (time comes from the server, location is recorded if allowed).
- `admin.html` – admin only. See attendance by date range / employee, download Excel (Summary + All punches sheets), block or unblock employees.

GitHub Pages only hosts files, it can't store data, so the data lives in Firebase (free Spark plan is enough for a small team).

## Setup (about 15 minutes)

1. **Create Firebase project** – https://console.firebase.google.com → Add project.
2. **Turn on login** – Build → Authentication → Get started → Sign-in method → enable **Email/Password**.
3. **Create the admin account first** – Authentication → Users → Add user → your admin email + password.
   (Do this before publishing, so nobody else can register that email.)
4. **Create the database** – Build → Firestore Database → Create database → Production mode → region `asia-south1` (Mumbai).
5. **Paste the security rules** – Firestore → Rules → replace everything with `firestore.rules`, change `admin@yourcompany.com` to your admin email → Publish.
6. **Get the web config** – Project settings (gear) → Your apps → Web `</>` → register → copy the `firebaseConfig` object into `firebase-config.js`. Set `ADMIN_EMAIL` there too.
7. **Upload to GitHub** – new repo → upload all files (keep the `icons` folder) → Settings → Pages → Branch `main`, folder `/root` → Save.
8. **Allow your domain** – Firebase → Authentication → Settings → Authorized domains → add `yourname.github.io`.

Links:
- Employees: `https://yourname.github.io/repo-name/`
- Admin: `https://yourname.github.io/repo-name/admin.html`

## Installing on phones
- Android (Chrome): open the link → tap **Install** banner, or menu ⋮ → *Add to Home screen*.
- iPhone (Safari): Share → *Add to Home Screen*.

## How blocking works
Admin taps **Block** → the employee immediately sees "Account blocked" and the database rules reject any new punch from them, even if they try to bypass the app.

## Notes
- Mobile OTP (SMS) login is possible with Firebase Phone Auth, but Firebase requires the paid Blaze plan for SMS. This version uses mobile/email + password so it stays free.
- The Firebase `apiKey` in `firebase-config.js` is safe to be public; security comes from `firestore.rules`.
- After you change files, bump `CACHE = "punch-v1"` to `v2` in `sw.js` so phones pick up the update.
