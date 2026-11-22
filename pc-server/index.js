// Receptor en la PC: recibe codigos del celular por WiFi y los "teclea"
// en la ventana activa, como si fuera una pistola lectora USB.
//
// Uso:  node index.js [--port=8765] [--suffix=enter|tab|none] [--reset-token]

const http = require('http');
const os = require('os');
const dgram = require('dgram');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const qrcode = require('qrcode-terminal');

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  }),
);
const PORT = Number(args.port || 8765);
const SUFFIX = String(args.suffix || 'enter');
const DEDUP_MS = 1000;

// --- Token de emparejamiento (se guarda para no re-emparejar cada vez) ---
// Empaquetado como .exe (pkg), __dirname es de solo lectura: el token se guarda junto al .exe.
const BASE_DIR = process.pkg ? path.dirname(process.execPath) : __dirname;
const configPath = path.join(BASE_DIR, 'config.json');
let config = {};
try { config = JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch {}
if (!config.token || args['reset-token']) {
  config.token = crypto.randomBytes(16).toString('hex');
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}
const TOKEN = config.token;
// Identificador publico derivado del token (el token en si nunca sale por broadcast).
const PAIR_ID = crypto.createHash('sha256').update(TOKEN).digest('hex').slice(0, 16);
const DISCOVERY_PORT = PORT + 1;

// --- Proceso PowerShell persistente que simula el teclado ---
// PowerShell no puede ejecutar un archivo que vive dentro del .exe: se extrae a una carpeta temporal.
const typerPath = path.join(os.tmpdir(), `barsfree-typer-${process.pid}.ps1`);
fs.writeFileSync(typerPath, fs.readFileSync(path.join(__dirname, 'typer.ps1'), 'utf8'), 'utf8');
process.on('exit', () => { try { fs.unlinkSync(typerPath); } catch {} });
process.on('SIGINT', () => process.exit(0)); // Ctrl+C: cierre limpio

const typer = spawn(
  'powershell.exe',
  ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', typerPath],
  { stdio: ['pipe', 'inherit', 'inherit'], windowsHide: true },
);
typer.on('exit', (c) => { console.error(`typer.ps1 termino (${c})`); process.exit(1); });

function typeCode(code, suffix = SUFFIX) {
  typer.stdin.write(`T ${Buffer.from(code, 'utf8').toString('base64')}\n`);
  if (suffix === 'enter') typer.stdin.write('K 13\n');
  else if (suffix === 'tab') typer.stdin.write('K 9\n');
}

// --- Servidor WebSocket ---
const server = http.createServer((_, res) => { res.writeHead(404); res.end(); });
const wss = new WebSocketServer({
  server,
  verifyClient: ({ req }) => {
    const url = new URL(req.url, 'http://x');
    return url.searchParams.get('token') === TOKEN;
  },
});

let last = { code: '', at: 0 };
wss.on('connection', (ws, req) => {
  console.log(`[+] Celular conectado (${req.socket.remoteAddress})`);
  ws.send(JSON.stringify({ type: 'hello', host: os.hostname() }));
  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }
    if (msg.type !== 'scan' || typeof msg.code !== 'string' || !msg.code) return;
    const code = msg.code.slice(0, 256);
    const now = Date.now();
    if (code === last.code && now - last.at < DEDUP_MS) return; // lectura doble
    last = { code, at: now };
    console.log(`[>] ${code}`);
    // El celular puede pedir que no se envie la tecla final (send: false).
    // Si no lo indica (apps viejas), se usa --suffix.
    typeCode(code, msg.send === false ? 'none' : SUFFIX);
    ws.send(JSON.stringify({ type: 'ok', code }));
  });
  ws.on('close', () => console.log('[-] Celular desconectado'));
});

// --- IPs de la red local ---
function lanIPs() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) {
      if (i.family === 'IPv4' && !i.internal &&
          /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(i.address)) out.push(i.address);
    }
  }
  return out;
}

// --- Descubrimiento UDP: el celular pregunta "donde esta mi PC?" y respondemos con la IP actual ---
const udp = dgram.createSocket({ type: 'udp4', reuseAddr: true });
udp.on('message', (buf, rinfo) => {
  let msg;
  try { msg = JSON.parse(buf.toString()); } catch { return; }
  if (msg.type !== 'find' || msg.id !== PAIR_ID) return; // solo respondemos al celular emparejado
  const reply = JSON.stringify({ type: 'here', id: PAIR_ID, h: lanIPs(), p: PORT, host: os.hostname() });
  udp.send(reply, rinfo.port, rinfo.address);
});
udp.on('error', (e) => console.error(`Descubrimiento UDP desactivado (${e.message})`));
udp.bind(DISCOVERY_PORT, '0.0.0.0');

server.listen(PORT, '0.0.0.0', () => {
  const ips = lanIPs();
  console.log('\n=== Codebars - receptor PC ===');
  console.log(`Puerto: ${PORT} | Sufijo: ${SUFFIX}`);
  if (!ips.length) { console.log('No encontre una IP de red local. Conectate a WiFi.'); return; }
  console.log(`IPs: ${ips.join(', ')}`);
  console.log('\nEscanea este QR desde la app para emparejar:\n');
  qrcode.generate(JSON.stringify({ h: ips, p: PORT, t: TOKEN, i: PAIR_ID }), { small: true });
  console.log('\nEsperando codigos... (Ctrl+C para salir)');
});
