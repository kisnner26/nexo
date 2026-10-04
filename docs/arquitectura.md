# arquitectura

## piezas

| pieza | qué hace |
|---|---|
| hub (mac) | `NWListener` tcp anunciado por bonjour (`_nexo._tcp`). ejecuta órdenes, reúne el estado y lo difunde. |
| iphone | cliente del hub (`NexoClient`) y puente del reloj por `WatchConnectivity`. |
| reloj | intenta conectar directo al hub; si no puede, manda las órdenes al iphone. |
| `NexoCore` | paquete compartido por las tres apps. |

## canal

trama: `[longitud u32][hmac-sha256 32 bytes][json]`. el json lleva un número de secuencia creciente que el receptor exige estrictamente mayor que el anterior, así que una trama repetida se descarta. la clave del hmac se deriva con hkdf-sha256 del código de emparejamiento (12 caracteres de un alfabeto de 30, unos 58 bits). una trama con firma inválida corta la conexión. el contenido no va cifrado: protege contra órdenes ajenas, no contra quien escuche la red local.

mensajes: `hello`, `command`, `status`, `alert`, `clipboard`, `ack`, `catalog`, `requestCatalog`, `requestIcons`, `icons`.

## camino del reloj

1. conexión directa por wi-fi si el reloj ve la mac por bonjour.
2. si no, `sendMessage` al iphone con la orden y respuesta; el iphone la ejecuta y contesta con estado, catálogo y código. el movimiento del trackpad y la corona se agrupan cada 50 ms.
3. el iphone empuja el estado al reloj en cada cambio, y el reloj lo consulta cada 3 s mientras no haya conexión directa.

con el iphone cerca, el reloj usa su red a través del iphone y normalmente no ve la red local, así que el camino 2 es el habitual.

## en la mac

- volumen y estado: `osascript` con límite de 3 s para no colgar el hub si macos pregunta por un permiso de automatización.
- brillo: `DisplayServices` (las teclas simuladas no cambian el brillo en apple silicon).
- indicador de volumen y brillo: `OSDManager` del sistema; si `OSDUIHelper` no despierta, un hud propio con el mismo aspecto.
- bloqueo: `SACLockScreenImmediate`, con `pmset displaysleepnow` como alternativa.
- cursor, clics, scroll y teclas: `CGEvent` (requiere accesibilidad). dos clics seguidos en menos de 0,4 s cuentan como doble clic.
- iconos de apps: `NSWorkspace`, 96×96 px, en lotes de 8.

`DisplayServices`, `OSD` y `login` son frameworks privados: pueden cambiar entre versiones de macos.

## pruebas

```bash
cd Packages/NexoCore && swift test                    # canal, firma y mensajes
swift build --product nexoprobe
.build/debug/nexoprobe CODIGO vol:50                  # órdenes contra el hub real
```

## límites conocidos

- perfil gratuito de apple: la app caduca a los 7 días.
- sin app group no se comparten datos entre app y widgets; los controles del centro de control usan el grupo `group.com.kisnner26.nexo`.
- la mac debe estar despierta y en la misma red.
