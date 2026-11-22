# Codebars

Convierte tu celular Android en un **lector de códigos de barras inalámbrico** para tu PC con Windows.

La app del celular escanea con la cámara y envía el código por WiFi. Un programa receptor en la PC lo **teclea en la ventana que tengas activa**, igual que una pistola lectora USB. Funciona con cualquier programa: Excel, el navegador, un sistema de ventas, etc.

```
[Celular: app Flutter]  --WiFi (WebSocket)-->  [PC: receptor Node.js]  --> teclea el código + Enter
  escanea con la cámara                          en la ventana activa
```

## Características

- Escaneo continuo con un recuadro de lectura: solo se lee lo que está dentro del recuadro.
- Animación de línea láser, cambio a verde, vibración y sonido al leer.
- Emparejamiento una sola vez escaneando un QR que muestra la PC.
- Reconexión automática y **descubrimiento de la PC** por la red si su IP cambia, sin volver a emparejar.
- Linterna para ambientes oscuros.
- Filtro de lecturas dobles (el mismo código no se repite en menos de 1 segundo en la PC ni 1,5 segundos en el celular).
- Formatos: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, ITF, Codabar, QR y Data Matrix.

## Tecnologías

| Parte | Tecnología |
|---|---|
| App del celular | [Flutter](https://flutter.dev) (Dart), solo Android |
| Escaneo | [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) |
| Conexión | [`web_socket_channel`](https://pub.dev/packages/web_socket_channel), UDP con `dart:io` |
| Datos locales | [`shared_preferences`](https://pub.dev/packages/shared_preferences) |
| Sonido | [`audioplayers`](https://pub.dev/packages/audioplayers) |
| Receptor en la PC | [Node.js](https://nodejs.org) con [`ws`](https://www.npmjs.com/package/ws) y [`qrcode-terminal`](https://www.npmjs.com/package/qrcode-terminal) |
| Simulación de teclado | PowerShell + `SendInput` de Windows (sin módulos nativos) |

## Estructura

```
.
├── mobile/        App Flutter (Android)
│   ├── lib/main.dart                 Pantallas de emparejar y de escaneo
│   ├── lib/connection_service.dart   Conexión, reconexión y descubrimiento
│   ├── lib/scanner_overlay.dart      Recuadro y animación
│   └── assets/beep.mp3               Sonido de lectura
└── pc-server/     Receptor para Windows
    ├── index.js                      Servidor WebSocket, QR y descubrimiento UDP
    └── typer.ps1                     Simula el teclado
```

## Requisitos

**En la PC**
- Windows 10 u 11.
- [Node.js](https://nodejs.org) 18 o superior.

**Para compilar la app**
- [Flutter SDK](https://docs.flutter.dev/get-started/install) con el SDK de Android configurado (`flutter doctor` sin errores).
- Un celular Android con la **depuración USB** activada (o solo el APK ya compilado).

**Red**
- El celular y la PC deben estar en la **misma red WiFi**, y la red debe permitir la comunicación entre dispositivos (algunas redes de invitados no lo permiten).

## Instalación y uso

### 1. Receptor en la PC

```powershell
cd pc-server
npm install
node index.js
```

Aparece el QR de emparejamiento en la consola. **Dejá la ventana abierta** mientras uses la app.

La primera vez, Windows pregunta si permitís a Node recibir conexiones. Aceptá para **redes privadas**, o el celular no podrá conectarse.

### 2. App en el celular

```powershell
cd mobile
flutter pub get
flutter run
```

Para generar un APK instalable sin cable:

```powershell
flutter build apk --release
```

El archivo queda en `mobile/build/app/outputs/flutter-apk/app-release.apk`. Copialo al celular e instalalo (habrá que permitir instalar apps de orígenes desconocidos).

### 3. Emparejar y escanear

1. Abrí la app y aceptá el permiso de cámara.
2. Escaneá con la app el **QR que aparece en la consola de la PC**.
3. Cuando la barra superior diga **"Conectado a ..."**, ya está listo.
4. En la PC, poné el cursor donde quieras que se escriba el código.
5. Apuntá el celular a un código de barras, dentro del recuadro. Se escribe en la PC y se envía Enter.

El emparejamiento se recuerda: la próxima vez solo hay que abrir el receptor y la app.

## Opciones del receptor

```powershell
node index.js [--port=8765] [--suffix=enter|tab|none] [--reset-token]
```

| Opción | Descripción | Por defecto |
|---|---|---|
| `--port` | Puerto del WebSocket. El descubrimiento UDP usa `puerto + 1`. | `8765` |
| `--suffix` | Tecla que se pulsa después del código: `enter`, `tab` o `none`. | `enter` |
| `--reset-token` | Genera un token nuevo. Invalida el emparejamiento anterior. | — |

Si cambiás `--port`, hay que volver a emparejar escaneando el QR nuevo.

## Cómo funciona

- **Emparejamiento:** el QR contiene las IPs de la PC, el puerto, un token secreto y un identificador público derivado del token. El token se guarda en `pc-server/config.json`.
- **Conexión:** el celular abre un WebSocket (`ws://IP:8765/?token=...`). Sin el token correcto, el servidor rechaza la conexión (HTTP 401).
- **Mensajes:** el celular envía `{"type":"scan","code":"..."}` y la PC responde `{"type":"ok"}`.
- **Teclado:** el servidor mantiene un proceso PowerShell (`typer.ps1`) que escribe el texto con `SendInput` en modo Unicode.
- **IP cambiada:** si no puede conectar, la app envía un broadcast UDP preguntando por la PC, usando solo el identificador público. La PC responde con su IP actual y la app reconecta sola.

## Solución de problemas

| Problema | Posible causa y solución |
|---|---|
| `EADDRINUSE` al iniciar el receptor | Ya hay otro receptor abierto. Cerralo, o buscá el proceso con `netstat -ano \| findstr :8765` y terminalo con `taskkill /PID <pid> /F`. |
| La app queda en "Buscando la PC..." | Verificá que ambos estén en la misma WiFi, que el receptor esté corriendo y que el firewall de Windows permita Node en redes privadas. |
| No encuentra la PC tras cambiar su IP | Si emparejaste con una versión anterior sin descubrimiento, reemparejá escaneando el QR. Algunas redes bloquean el broadcast. |
| El código no se escribe en ningún programa | La ventana de destino debe estar enfocada. Si es un programa ejecutado como administrador, ejecutá el receptor también como administrador. |
| No suena el beep | Revisá el volumen de medios del celular. En modo silencio no suena. |
| Error `Could not close incremental caches` al compilar | El proyecto y la caché de Flutter están en discos distintos (por ejemplo `E:` y `C:`). Ya está resuelto con `kotlin.incremental=false` en `mobile/android/gradle.properties`. |

## Seguridad

- No compartas ni subas `pc-server/config.json`: contiene el token que da acceso para escribir en tu PC. Ya está incluido en `.gitignore`.
- Si sospechás que el token se filtró, ejecutá `node index.js --reset-token` y reemparejá.
- La comunicación usa `ws://` sin cifrar, pensada para una red local de confianza. No la uses en redes públicas.

## Limitaciones

- El receptor funciona solo en **Windows** (usa PowerShell y la API de Windows).
- La app está pensada y probada para **Android**. No se probó en iOS.
- Requiere que el celular y la PC estén en la misma red local.
