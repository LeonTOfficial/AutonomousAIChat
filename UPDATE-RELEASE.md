# Sparkle-Release-Ablauf

## Aktueller Stand

AutonomousAIChat v18.1.0 enthält Sparkle 2.9.2, den öffentlichen EdDSA-Schlüssel und den vorgesehenen HTTPS-Feed. Diese erste Sparkle-fähige Version muss noch einmal per DMG installiert werden. Für spätere Updates kann die App den Download selbst übernehmen.

Der Feed zeigt auf:

`https://raw.githubusercontent.com/LeonTOfficial/AutonomousAIChat/main/appcast.xml`

Das zugehörige öffentliche Repository und der Appcast sind noch nicht veröffentlicht. Ohne diesen bewusst ausstehenden externen Schritt meldet eine manuelle Updateprüfung einen nicht erreichbaren Feed.

## Sicherheitsregeln

- Der private EdDSA-Schlüssel bleibt ausschließlich im macOS-Schlüsselbund.
- Private Schlüssel, API-Keys, Sitzungsdaten, Diagnose-Logs und Build-Caches dürfen nie in Repository, ZIP, DMG oder Appcast gelangen.
- Release-Artefakte werden erst veröffentlicht, nachdem App-Bundle, Signatur, Archiv und Appcast lokal geprüft wurden.
- Das Sparkle-Archiv wird mit `generate_appcast` beziehungsweise `sign_update` aus der offiziellen Sparkle-Distribution signiert. Die Signatur wird nicht von Hand erfunden oder kopiert.
- Veröffentlichung, Git-Push, Tag oder GitHub-Release erfolgen erst nach ausdrücklicher Freigabe des Besitzers.

## Lokale Vorbereitung

```bash
./scripts/package_release.sh
```

Das erzeugt im übergeordneten `outputs`-Ordner:

- `AutonomousAIChat-v18.1.0.dmg` für die einmalige manuelle Installation
- `AutonomousAIChat-v18.1.0-update.zip` als späteres Sparkle-Enclosure
- `AutonomousAIChat-v18.zip` als uploadbare Quellkopie ohne Build-Caches

Danach müssen mindestens folgende Prüfungen erfolgreich sein:

```bash
swift test
swift build -c release
codesign --verify --deep --strict --verbose=2 "${TMPDIR%/}/AutonomousAIChat-v18-app-build/Autonomer KI-Gruppenchat.app"
hdiutil verify "../../outputs/AutonomousAIChat-v18.1.0.dmg"
unzip -tq "../../outputs/AutonomousAIChat-v18.1.0-update.zip"
```

## Veröffentlichung eines Folgeupdates

1. Version und Buildnummer erhöhen.
2. Tests und Release-Paketierung ausführen.
3. Das Update-ZIP mit den offiziellen Sparkle-Werkzeugen und dem Schlüsselbund-Schlüssel signieren.
4. Einen Appcast mit Download-URL, Dateilänge, Versionsdaten und EdDSA-Signatur erzeugen.
5. Appcast und Release-Archiv vor der Veröffentlichung mit SparkleReleaseKit beziehungsweise dem offiziellen Sparkle-Validator prüfen.
6. Erst nach Freigabe Repository, Appcast und Release-Artefakt veröffentlichen.
7. Von einer älteren installierten App aus „Nach Updates suchen …“ ausführen und den vollständigen Download-, Installations- und Neustartpfad abnehmen.

SparkleReleaseKit ist für die Appcast- und Release-Validierung sinnvoll. Seine lokale Arbeitskopie ist jedoch ein getrenntes Projekt und wird von AutonomousAIChat weder verändert noch als Abhängigkeit eingebaut.
