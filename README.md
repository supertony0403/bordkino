# Bordkino 🎬🚗

YouTube und andere Videolinks auf dem **CarPlay-Display** – als eigene App für ein iPhone mit
**Dopamine-Jailbreak** (rootless). Videos laufen nativ über `AVPlayer`, ohne WebKit,
ohne Google-Konto, ohne API-Schlüssel.

> ⚠️ **Nur im Stand schauen.** Videos während der Fahrt anzusehen ist nach § 23 Abs. 1a StVO
> verboten. Die eingebaute **Fahrsperre** blendet ab etwa 10 km/h das Bild aus, der Ton läuft
> weiter (Nachrichten, Podcasts, Musik). Sie ist standardmäßig an.

## Zwei Varianten in einem Paket

| App | CarPlay-Weg | Bedienung im Auto |
|---|---|---|
| **Bordkino** | „Stark“: volles App-Fenster wie Apples eigene CarPlay-Apps | eigene Touch-Oberfläche mit Kacheln, deutscher Bildschirmtastatur, Kanälen und Diagnose |
| **Bordkino Navi** | Navigations-App mit CarPlay-Vorlagen | CarPlay-Suche mit Systemtastatur, Listen, Kartenknöpfe ⏪ ⏯ ⏩ ⏹ |

Welche Variante unter deinem iOS und in deinem Auto funktioniert, zeigt **eine Fahrt**: Beide
Symbole erscheinen auf dem CarPlay-Homescreen. Nimm die, die läuft.

## Funktionen

- YouTube-Suche, Kanäle (ohne Konto, über RSS), Merkliste, Verlauf, Weiterschauen ab letzter Position
- YouTube-Links und Video-IDs; außerdem direkte `.m3u8`/`.mp4`-Links („und so“)
- Bild bis 1080p (HLS), Qualität begrenzbar auf 720p/480p fürs mobile Datenvolumen
- Lenkradtasten: Play/Pause, Vor (+30 s), Zurück (−10 s); Now-Playing-Anzeige mit Vorschaubild
- CarPlay trennen → Wiedergabe pausiert
- Zwei Renderer: **A** (`AVPlayerLayer`) und **B** (Bildpumpe mit Metal im eigenen Prozess).
  Bleibt das Bild im Auto schwarz, im Player auf „A/B“ tippen.
- Diagnose im Auto und am Handy: Testbild, Apple-Testvideo mit Renderer A/B, Web-Modus, Protokoll
- Das YouTube-Modul (`js/extractor.js`) lädt sich täglich aus diesem Repo nach. Wenn YouTube etwas
  ändert, reicht ein Update dieser einen Datei, ohne neue App-Version.
- URL-Schema: `bordkino://play?v=VIDEO_ID` oder `bordkino://play?url=<Link>` (für Kurzbefehle)

## Installation

**Voraussetzung:** Dopamine (rootless) mit Sileo oder Zebra.

1. Die `.deb` aus dem [neuesten Release](https://github.com/supertony0403/bordkino/releases/latest)
   am iPhone in Safari laden.
2. In Dateien antippen → „Teilen“ → **Sileo** (oder mit Filza öffnen) → Installieren.
3. Auf dem Homescreen erscheinen **Bordkino** und **Bordkino Navi**.
4. Beim ersten Start den Standortzugriff erlauben („Beim Verwenden der App“) – nur für die Fahrsperre.

Mit Kabel vom Linux-PC (OpenSSH aus Sileo installiert): `tools/deploy.sh`

## Erste Fahrt – Checkliste

Am Handy (ohne Auto):
- [ ] Suche „tagesschau“ → Video antippen → läuft am Handy mit Bild und Ton
- [ ] Einstellungen → „Testvideo am Handy (Apple)“ läuft
- [ ] Einstellungen → YouTube-Modul zeigt eine Version

Im Auto (stehend):
- [ ] Erscheinen **Bordkino** und/oder **Bordkino Navi** auf dem CarPlay-Schirm?
- [ ] **Bordkino**: Diagnose → **Testbild**. Siehst du die Farbbalken, kann die App aufs Autodisplay zeichnen.
- [ ] Diagnose → **Testvideo A**. Bild da? Wenn schwarz: **Testvideo B**.
- [ ] Suche (eigene Tastatur) → Video starten. Lenkradtasten testen.
- [ ] **Bordkino Navi**: „Suche“ oben links → Video wählen → läuft unter den Kartenknöpfen?
- [ ] Losfahren: Bild verschwindet, Ton läuft weiter. Anhalten: Bild kommt nach ~5 s zurück.
- [ ] CarPlay-Kabel ziehen: Wiedergabe pausiert.

Wenn etwas nicht geht: Einstellungen → Diagnose → **Protokoll anzeigen** → Teilen.
Das Protokoll enthält die Szenen-Rolle, den YouTube-Client und alle Fehler.

## Fehlersuche

| Symptom | Wahrscheinliche Ursache / Abhilfe |
|---|---|
| App fehlt auf dem CarPlay-Schirm | Nach der Installation iPhone einmal neu mit CarPlay verbinden. Steht im Protokoll keine „Szene mit Rolle …“, hat CarPlay die App nicht gestartet → die andere Variante probieren. |
| Testbild ja, Video schwarz | Renderer B einstellen (Player-Knopf „A/B“ oder Einstellungen). |
| „YouTube verlangt eine Anmeldung (Bot-Prüfung)“ | YouTube hat Clients geändert → Einstellungen → YouTube-Modul → „Jetzt aktualisieren“. Hilft das nicht: Issue anlegen. |
| Bild verschwindet im Stand | Fahrsperre misst GPS-Tempo; in Tiefgaragen ohne Empfang bleibt der letzte Zustand. Notfalls Fahrsperre kurz aus. |
| Video stoppt, wenn das Handy sperrt | Einstellungen → „Handy wach & dunkel“ einschalten. |

## Aufbau

```
js/extractor.js        YouTube-Logik (läuft in JavaScriptCore und Node)
Sources/Core           Protokoll, Bibliothek, JS-Brücke (host.fetch → NSURLSession), YouTube-Fassade
Sources/Player         AVPlayer-Engine, Renderer A/B, Fahrsperre, Player-Oberfläche
Sources/Phone          Handy-Oberfläche
Sources/Car            Stark-Oberfläche fürs Auto + Diagnose
Sources/Navi           Vorlagen-Variante
docs/superpowers       Design-Spec und Umsetzungsplan
```

**YouTube-Abruf:** Startseite → `VISITOR_DATA` → `/youtubei/v1/player` mit dem Client
`visionos` (HLS bis 1080p), Rückfall auf `ios` und `android_vr`. Jede HLS-Liste wird vor dem
Abspielen geprüft; scheitert die Wiedergabe, versucht der Player automatisch den nächsten Client.

## Bauen (Linux)

```bash
# einmalig: Theos + Linux-Toolchain + SDK
git clone --recursive https://github.com/theos/theos.git ~/theos
mkdir -p ~/theos/toolchain/linux/iphone
curl -fsSL https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz \
  | tar -xJ -C ~/theos/toolchain/linux/iphone --strip-components=2
# iPhoneOS16.5.sdk aus https://github.com/theos/sdks nach ~/theos/sdks/

export THEOS=~/theos
make package FINALPACKAGE=1      # → packages/de.benzsw.bordkino_<version>_iphoneos-arm64.deb
bash tools/check-deb.sh          # Paketprüfung: Pfade, arm64, Entitlements, Plists
npm test                         # 28 Tests für das YouTube-Modul
npm run live                     # Rauchtest gegen das echte YouTube
```

Nur `arm64`: clang 11 aus der Linux-Toolchain erzeugt die alte arm64e-ABI, die iOS 17 ablehnt.
Für eine App ist das egal, `arm64` läuft nativ auf allen A12+-Geräten.

## Grenzen

- Ohne Jailbreak geht das nicht. Die privaten Entitlements (`SBStarkCapable`,
  `com.apple.developer.carplay-maps`) werden nur dank Dopamine akzeptiert.
- Kein Google-Login, also keine Abos/Empfehlungen aus dem Konto. Kanäle merkst du lokal.
- YouTube ändert seine Schnittstellen regelmäßig. Dann muss `js/extractor.js` nachgezogen werden.
- Privates Projekt, nicht mit YouTube, Google oder Apple verbunden.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
