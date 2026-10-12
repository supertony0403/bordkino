# Bordkino – Design

Stand: 12.10.2026 · Status: freigegeben (autonom im `/goal`-Modus, Annahmen unten markiert)

## 1. Ziel

Eine eigene CarPlay-App für Anthonys iPhone 11 (iOS 17.5.1, Dopamine-3-Jailbreak),
mit der YouTube-Videos auf dem CarPlay-Display im Auto laufen. Dazu kommen beliebige direkte
Videolinks (`.m3u8`/`.mp4`), weil der Wunsch „YouTube geht **und so**“ war.

**Erfolg heißt:** Im Auto erscheint ein Bordkino-Symbol auf dem CarPlay-Schirm. Man sucht dort
oder am Handy ein Video, es läuft mit Bild und Ton auf dem Autodisplay, und die
Lenkradtasten steuern Pause/Weiter.

### Was der Nutzer gesagt hat
- „meine eigene custom app programmieren für car play wo youtube geht und so“
- iPhone mit Dopamine

### Annahmen (autonom getroffen, umwerfbar)
| Annahme | Begründung |
|---|---|
| Name **Bordkino**, Oberfläche deutsch | eigener Name, CarTube ist vergeben |
| **Kein Google-Login** in v1 | kein Passwort/Cookie-Risiko; Abos lokal über RSS |
| **Fahrsperre an** (Bild nur im Stand, Ton läuft weiter), abschaltbar | § 23 Abs. 1a StVO; im Stau/Parken voll nutzbar |
| Auslieferung als **Rootless-.deb** | Dopamine ist rootless (`/var/jb`) |
| Abnahme im Auto macht Anthony | ohne CarPlay-Gerät hier nicht prüfbar |

## 2. Geprüfte Fakten (12.10.2026)

- **Gerät:** iPhone12,1 (A13), iOS 17.5.1, Dopamine 3.0.10 rootless. Per `ldid` ad-hoc signierte
  Binärdateien unter `/var/jb` laufen, Entitlements werden nicht gegen ein Profil geprüft.
- **CarPlay-Wege für Fremd-Apps:**
  - *Stark* (`SBStarkCapable`-Entitlement + Szenenrolle `UIWindowSceneSessionRoleCarPlay`): volles
    UIKit-Fenster mit Touch auf dem Autoschirm. CarTube (Avangelista, GPLv3) nutzt das bis iOS
    15.4.1. Unter iOS 16 (palera1n) erscheint die Szene und **native Views werden angezeigt**,
    der **WKWebView bleibt schwarz** (Issues #5, #59, #62). iOS 17 ist unbestätigt.
  - *Navigations-Template* (`com.apple.developer.carplay-maps`): `CPWindow` unter einer
    `CPMapTemplate` nimmt beliebige Views auf; Touch nur über Templates (Kartenknöpfe, Suche, Listen).
- **YouTube-Daten** (Live-Tests vom Heimnetz, 4 Videos):
  - Ablauf wie yt-dlp: `www.youtube.com` laden → `VISITOR_DATA` → `/youtubei/v1/player`.
  - Client **`visionos`** (`VISIONOS` 1.02) + Besucher-Kennung → `hlsManifestUrl` bei allen
    Testvideos, Varianten bis 1920×1080 avc1 + 2 Audiospuren, Segmente Anfang/Mitte/Ende alle 200.
    Ohne Besucher-Kennung: `LOGIN_REQUIRED` („kein Bot“).
  - `ios`: HLS nur bei manchen Videos. `android_vr`: Einzelformate 206, kombiniertes itag 18 teils 403.
    `web_safari`/`mweb`: `UNPLAYABLE` (PO-Token nötig).
  - Suche: `/youtubei/v1/search` mit WEB-Client + Besucher-Kennung → 20 `videoRenderer` je Seite.
  - Kanal-Feed: `https://www.youtube.com/feeds/videos.xml?channel_id=…` → 15 Einträge, kein Schlüssel.
- **Toolchain:** Theos `304e079` + L1ghtmann-clang 11.1 + `iPhoneOS16.5.sdk` baut auf Arch eine
  Rootless-`.deb`. clang 11 erzeugt die **alte arm64e-ABI** → App nur als **`arm64`** bauen
  (läuft nativ auf A13).

## 3. Lösungswege (verglichen)

1. **Eigene native App, zwei CarPlay-Varianten** *(gewählt)* – native Wiedergabe mit `AVPlayer`
   (kein WebKit im Auto), YouTube-Logik als austauschbares JavaScript in JavaScriptCore.
   Eine Fahrt klärt, welche CarPlay-Variante unter 17.5.1 funktioniert.
2. CarTube forken (WKWebView) – wenig Aufwand, aber genau der Teil, der ab iOS 16 schwarz bleibt.
3. Tweak, der die offizielle YouTube-App spiegelt (CarBridge-Art) – keine eigene App,
   tiefe SpringBoard-Hooks unter iOS 17, Video der YouTube-App nutzt dieselben Fremd-Layer.

## 4. Architektur

Zwei App-Bündel aus **einer** Codebasis, nebeneinander installierbar:

| Bündel | Kennung | CarPlay-Weg | Bedienung im Auto |
|---|---|---|---|
| **Bordkino** | `de.benzsw.bordkino` | Stark | eigene Touch-Oberfläche, eigene Tastatur |
| **Bordkino Navi** | `de.benzsw.bordkino.navi` | Navigations-Template | CarPlay-Suche/Listen, Kartenknöpfe |

Beide teilen Daten über `~/Library/Application Support/Bordkino/` (ohne Container,
`com.apple.private.security.no-container`).

### 4.1 Bausteine

| Baustein | Aufgabe | hängt ab von |
|---|---|---|
| `js/extractor.js` | reine Logik: Anfragen bauen, Antworten zerlegen, Client-Kette, Stream-Auswahl. Läuft in JavaScriptCore **und** unter Node (Tests). | `host.fetch` (vom Gastgeber) |
| `BKScriptHost` | lädt `extractor.js` in einen `JSContext`, stellt `host.fetch` (NSURLSession → Promise) und `host.log` bereit, ruft Funktionen asynchron auf | JavaScriptCore |
| `BKYouTube` | Fassade: `search:`, `resolve:`, `channelFeed:` → Modellobjekte | `BKScriptHost` |
| `BKExtractorUpdater` | holt neuere `extractor.js` aus dem GitHub-Repo, prüft Selbsttest, sonst eingebaute Fassung | `BKScriptHost` |
| `BKPlayer` | eine gemeinsame `AVPlayer`-Instanz, Audiositzung *playback*, Now-Playing + Fernsteuerbefehle, Position merken, bei Fehler nächsten Client probieren | AVFoundation, MediaPlayer |
| `BKVideoSurface` | zeigt das Bild. Renderer **A** = `AVPlayerLayer`, **B** = Bildpumpe (`AVPlayerItemVideoOutput` + `CADisplayLink` → `layer.contents`). Umschaltbar. | `BKPlayer` |
| `BKDriveGuard` | CoreLocation-Tempo: > 10 km/h für 3 s → Bild aus (Ton bleibt), < 3 km/h für 5 s → Bild an | CoreLocation |
| `BKLibrary` | JSON-Dateien: Verlauf (50), Merkliste, Kanäle, Positionen, Einstellungen | Foundation |
| `BKLog` | Ringpuffer 500 Zeilen + Datei, für die Diagnose-Ansicht | – |
| Auto-UI Stark | `BKCarSceneDelegate`, `BKCarRootViewController` (Leiste links: Start, Suche, Merkliste, Kanäle, Diagnose), Kachelraster, `BKKeyboardView` (QWERTZ, große Tasten), `BKCarPlayerViewController` (Bedienleiste blendet aus) | gemeinsame Bausteine |
| Auto-UI Navi | `BKTemplateSceneDelegate`: `CPMapTemplate` (Kartenknöpfe Play/Pause, −10 s, +30 s; Leistenknöpfe Suche, Listen), `CPSearchTemplate`, `CPListTemplate`; `CPWindow` zeigt `BKVideoViewController` | gemeinsame Bausteine |
| Handy-UI | Tabs Suche · Merkliste/Verlauf · Kanäle · Einstellungen; Tippen spielt im Auto (falls verbunden) sonst am Handy; YouTube-Link in der Zwischenablage wird angeboten; URL-Schema `bordkino://play?v=ID` bzw. `?url=…` | gemeinsame Bausteine |
| Diagnose (Auto + Handy) | Testbild, Testvideo mit Renderer A/B, experimenteller Web-Modus (WKWebView mit m.youtube.com), Protokoll | alle |

### 4.2 Datenfluss

- **Suche:** UI → `BKYouTube search:` → JS `search(q)` → `host.fetch` (Startseite für
  Besucher-Kennung, 6 h zwischengespeichert; dann `/youtubei/v1/search`) → `parseSearch` →
  `[{videoId, title, channel, duration, thumbnail, isLive}]` → UI.
- **Abspielen:** UI → `BKYouTube resolve:` → JS `resolve(videoId)` → Client-Kette
  `visionos → ios → android_vr` (je: Player-Anfrage, Status prüfen, HLS-Master testweise laden) →
  `{url, kind:'hls'|'progressive', client, title, …}` → `BKPlayer play:` → `BKVideoSurface`.
- **Direkter Link:** `http(s)://…m3u8|mp4` → `BKPlayer` ohne JS.
- **Kanäle:** RSS → JS `parseFeed` → Liste.

### 4.3 Fehlerbehandlung

- Jeder Schritt liefert einen deutschen Grund („Video ist altersbeschränkt“, „YouTube verlangt
  Anmeldung“, „kein Netz“). UI zeigt Karte mit Grund + „Nochmal“.
- Die Client-Kette protokolliert jeden Versuch (Client, Status, Grund) in `BKLog`.
- `AVPlayerItem` schlägt fehl oder hängt 15 s → automatisch nächster Client.
- Extractor-Update kaputt (Selbsttest scheitert) → eingebaute Fassung bleibt.
- Ohne Netz bleiben Merkliste/Verlauf sichtbar.

### 4.4 Sicherheit und Recht

- Fahrsperre standardmäßig an; Ton läuft weiter. Abschalten ist Anthonys Verantwortung.
- Keine Zugangsdaten, kein Google-Login, keine Server von Dritten außer YouTube/GitHub.
- Nur die nötigen privaten Entitlements (Stark bzw. carplay-maps, no-container, platform-application).
- Repo öffentlich, enthält keine Geheimnisse. Nutzung privat.

## 5. Tests

- **JS (`node --test`)**: Zerlegen gegen echte Antworten (`test/fixtures/`: Startseite, Suche,
  Player-Antworten je Client, RSS), Client-Kette mit gefälschtem `host.fetch`
  (Fehlerfälle: LOGIN_REQUIRED, kein HLS, Netzfehler), Stream-Auswahl.
  Plus `npm run live`: echter Abruf gegen YouTube vom PC (Rauchtest, nicht in der Suite).
- **Build-Prüfung (`tools/check-deb.sh`)**: Pfade unter `/var/jb`, Binärdatei `arm64`,
  Entitlements eingebettet (`ldid -e`), Info.plist gültig (Python `plistlib`), `extractor.js`
  im Bündel.
- **Am Gerät (Anthony, Checkliste im README):** Handy (Suche, Abspielen am Handy, Einstellungen),
  Auto (beide Symbole, Diagnose: Testbild → Renderer A → Renderer B → Web-Modus).
- **Ausrollen:** `make deploy` per `iproxy` + SSH, wenn das iPhone am USB hängt und OpenSSH
  installiert ist; sonst `.deb` per HTTP im LAN für Sileo bereitstellen.

## 6. Nicht in v1 (YAGNI)

Google-Login/Abo-Abgleich, Kommentare, Shorts-Ansicht, DASH→HLS-Brücke, Relay über das Homelab,
Teilen-Erweiterung, Bild-in-Bild, Downloads.

## 7. Offene Risiken

1. Stark-Szene erscheint unter iOS 17 nicht → Variante Navi.
2. Videobild bleibt im Auto schwarz → Renderer B (Bildpumpe im eigenen Prozess).
3. YouTube ändert Clients → `extractor.js` über GitHub nachladen, ohne Neubau.
4. Gesperrtes Handy bremst die App → Hintergrund-Audio, `idleTimerDisabled`, „Handy abdunkeln“.
