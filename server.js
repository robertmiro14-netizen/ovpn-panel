'use strict';
const express    = require('express');
const session    = require('express-session');
const bcrypt     = require('bcryptjs');
const https      = require('https');
const http       = require('http');
const fs         = require('fs');
const path       = require('path');
const crypto     = require('crypto');
const { execSync } = require('child_process');

const PORT       = 51822;
const PWFILE     = '/opt/vol-ovpn-panel/.password';
const HTML       = path.join(__dirname, 'panel.html');
const CERT_KEY   = '/opt/vol-ovpn-panel/cert.key';
const CERT_CRT   = '/opt/vol-ovpn-panel/cert.crt';
const CONTAINER  = 'vol-openvpn';
const INDEX_FILE = '/opt/ovpn-data/pki/index.txt';
const ISSUED_DIR = '/opt/ovpn-data/pki/issued';

const app = express();
app.set('trust proxy', 1);
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(session({
  secret: crypto.randomBytes(32).toString('hex'),
  resave: false, saveUninitialized: false,
  cookie: { httpOnly: true, secure: true, maxAge: 86400000 }
}));

const hasPwd = () => fs.existsSync(PWFILE);
const auth   = (req, res, next) => {
  if (!hasPwd()) return res.redirect('/setup');
  if (req.session && req.session.ok) return next();
  res.redirect('/login');
};

// ── Auth pages ────────────────────────────────────────────────
function authPage(title, formHtml, err) {
  return `<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vol OVPN Panel</title><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
background:linear-gradient(135deg,#0d2137,#1a4a6b);
min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.c{background:#fff;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,.35);
padding:44px;width:100%;max-width:400px}
.logo{display:flex;align-items:center;gap:12px;margin-bottom:32px}
.lb{width:44px;height:44px;background:linear-gradient(135deg,#1a6b3c,#27ae60);
border-radius:12px;display:flex;align-items:center;justify-content:center}
.lb svg{width:22px;height:22px;fill:none;stroke:#fff;stroke-width:2.5;stroke-linecap:round;stroke-linejoin:round}
.lt{font-size:18px;font-weight:700;color:#0d2137}
.lt small{font-size:11px;font-weight:400;color:#888;display:block}
h2{font-size:15px;color:#555;margin-bottom:22px;font-weight:400}
.err{background:#fef2f2;border-left:4px solid #e74c3c;color:#c0392b;
padding:10px 14px;border-radius:6px;margin-bottom:14px;font-size:13px}
.f{margin-bottom:16px}label{display:block;font-size:13px;color:#444;margin-bottom:6px;font-weight:500}
input[type=password]{width:100%;padding:11px 14px;border:1.5px solid #e0e0e0;border-radius:10px;
font-size:15px;outline:none;background:#fafafa;transition:border-color .2s,box-shadow .2s}
input[type=password]:focus{border-color:#27ae60;background:#fff;box-shadow:0 0 0 3px rgba(39,174,96,.08)}
button{width:100%;padding:12px;background:linear-gradient(135deg,#1a6b3c,#27ae60);
color:#fff;border:none;border-radius:10px;font-size:15px;font-weight:600;cursor:pointer;margin-top:6px}
button:hover{opacity:.9}
</style></head><body><div class="c">
<div class="logo"><div class="lb">
<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="M12 8v4l3 3"/></svg>
</div><div class="lt">Vol OVPN Panel<small>OpenVPN Management</small></div></div>
<h2>${title}</h2>${err ? '<div class="err">'+err+'</div>' : ''}
<form method="POST">${formHtml}</form></div></body></html>`;
}

const setupForm = `<div class="f"><label>Пароль (мин. 6 символов)</label>
<input type="password" name="p" autofocus required></div>
<div class="f"><label>Подтвердите пароль</label>
<input type="password" name="c" required></div>
<button>Создать и войти →</button>`;

const loginForm = `<div class="f"><label>Пароль</label>
<input type="password" name="p" autofocus required></div>
<button>Войти →</button>`;

app.get('/setup', (req, res) => {
  if (hasPwd()) return res.redirect('/login');
  res.send(authPage('Создайте пароль администратора', setupForm));
});
app.post('/setup', async (req, res) => {
  if (hasPwd()) return res.redirect('/login');
  const { p, c } = req.body;
  if (!p || p.length < 6) return res.send(authPage('Создайте пароль', setupForm, 'Минимум 6 символов'));
  if (p !== c)            return res.send(authPage('Создайте пароль', setupForm, 'Пароли не совпадают'));
  fs.writeFileSync(PWFILE, await bcrypt.hash(p, 12), { mode: 0o600 });
  req.session.ok = true;
  res.redirect('/');
});
app.get('/login', (req, res) => {
  if (!hasPwd()) return res.redirect('/setup');
  if (req.session && req.session.ok) return res.redirect('/');
  res.send(authPage('Войдите в панель', loginForm));
});
app.post('/login', async (req, res) => {
  if (!hasPwd()) return res.redirect('/setup');
  try {
    const ok = await bcrypt.compare(req.body.p, fs.readFileSync(PWFILE,'utf8').trim());
    if (ok) { req.session.ok = true; return res.redirect('/'); }
  } catch(e) {}
  res.send(authPage('Войдите в панель', loginForm, 'Неверный пароль'));
});
app.get(['/logout','/api/logout'], (req,res) => req.session.destroy(() => res.redirect('/login')));

// ── Client helpers ────────────────────────────────────────────
function parseClients() {
  if (!fs.existsSync(INDEX_FILE)) return [];
  return fs.readFileSync(INDEX_FILE, 'utf8')
    .split('\n')
    .filter(l => l.startsWith('V\t'))
    .map(line => {
      const parts = line.split('\t');
      const subject = parts[parts.length - 1] || '';
      const name = subject.replace('/CN=', '').trim();
      if (!name || name === 'server') return null;
      const certPath = path.join(ISSUED_DIR, name + '.crt');
      const createdAt = fs.existsSync(certPath) ? fs.statSync(certPath).mtime : null;
      return { name, createdAt };
    })
    .filter(Boolean);
}

function run(cmd) {
  return execSync(cmd, { timeout: 30000, maxBuffer: 4 * 1024 * 1024 });
}

// ── API routes ────────────────────────────────────────────────
app.get('/api/clients', auth, (req, res) => {
  try { res.json(parseClients()); }
  catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/clients', auth, (req, res) => {
  const name = (req.body.name || '').trim();
  if (!name || !/^[a-zA-Z0-9_-]{1,64}$/.test(name))
    return res.status(400).json({ error: 'Недопустимое имя (только a-z, 0-9, _, -)' });
  try {
    run(`docker exec -e EASYRSA_BATCH=1 ${CONTAINER} easyrsa build-client-full "${name}" nopass`);
    res.json({ ok: true, name });
  } catch(e) {
    res.status(500).json({ error: e.stderr ? e.stderr.toString().slice(0,300) : e.message });
  }
});

app.delete('/api/clients/:name', auth, (req, res) => {
  const name = req.params.name;
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) return res.status(400).json({ error: 'Invalid name' });
  try {
    run(`docker exec -e EASYRSA_BATCH=1 ${CONTAINER} ovpn_revokeclient "${name}" remove`);
    res.json({ ok: true });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/clients/:name/config', auth, (req, res) => {
  const name = req.params.name;
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) return res.status(400).send('Invalid');
  try {
    const buf = run(`docker exec ${CONTAINER} ovpn_getclient "${name}"`);
    res.set('Content-Type', 'application/x-openvpn-profile');
    res.set('Content-Disposition', `attachment; filename="${name}.ovpn"`);
    res.send(buf);
  } catch(e) { res.status(500).send('Error'); }
});

app.get('/', auth, (req, res) => res.sendFile(HTML));

// ── Start server (HTTPS if cert exists, else HTTP) ────────────
const proto = fs.existsSync(CERT_KEY) && fs.existsSync(CERT_CRT) ? 'https' : 'http';
if (proto === 'https') {
  https.createServer({ key: fs.readFileSync(CERT_KEY), cert: fs.readFileSync(CERT_CRT) }, app)
    .listen(PORT, () => console.log('[Vol OVPN Panel] https://0.0.0.0:' + PORT));
} else {
  http.createServer(app).listen(PORT, () => console.log('[Vol OVPN Panel] http://0.0.0.0:' + PORT));
}
