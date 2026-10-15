# AutonomousAIChat

![Illustration des autonomen KI-Gruppenchats](Assets/social-preview.png)

Native macOS-SwiftUI-App mit zwei getrennten Modi:

- **Gruppe:** Alice und Bob reagieren auf dich und können anschließend autonom weiterreden.
- **KI-Chat:** ein temporärer 1:1-Chat mit dem gewählten Gemini- oder Ollama-Modell.

## Ein Gespräch, das weiterdenkt

Wirf eine Idee in den Raum und schau zu, wie sich die KIs darüber unterhalten. Im Gruppenchat sprechen sie nach deiner ersten Nachricht selbstständig miteinander weiter – mit eigenen Perspektiven, Fragen und Antworten.

Du entscheidest, wie viel du steuerst: Gib nur einen Impuls und lass die Unterhaltung laufen, setze ein Thema, oder steig jederzeit mit einer Nachricht wieder ein. So wird aus einem normalen Chat ein kleiner Raum für Gedanken, Diskussionen und überraschende Richtungen.

Zusätzlich enthält die Entwicklungsfassung einen eigenen **Agent-Arbeitsbereich**. Er verwendet ein lokal installiertes Ollama-Modell, startet immer in einem app-eigenen Sandkasten und kann optional einen ausdrücklich gewählten Ordner untersuchen. Schreiben und Finder-Aktionen erfolgen niemals ohne eine sichtbare Freigabe.

## Agent-Arbeitsbereich (v19.0.5-Vorschau)

- Umschalten über „Chat | Agent | Gruppe“ direkt im Hauptfenster; „Chat“ öffnet den 1:1-Chat und „Gruppe“ den autonomen Gruppenchat.
- Ein Zahnrad oben rechts öffnet die vorhandenen Einstellungen in jedem Bereich.
- Der Agent startet ohne Einrichtung in seinem lokalen `Agent-Sandkasten`. Ein externer Arbeitsordner kann weiterhin ausschließlich über den nativen macOS-Ordnerdialog gewählt werden.
- Unter **Einstellungen → KI → Agent – Modell** ist der Anbieter pro Agentenlauf auswählbar: lokal **Ollama** oder **Gemini**. Das jeweilige Modell wird direkt darunter gewählt; Gemini verwendet den bereits in den Einstellungen hinterlegten API-Key.
- Eingaben und direkte Agentenantworten erscheinen als Gesprächsbubbles im Agentenbereich. Ein abgebrochener oder zu langsamer Lauf bleibt als verständliche Statusmeldung mit „Erneut versuchen“ sichtbar, statt dass die Anfrage lautlos verschwindet.
- Typisierte Werkzeuge für Ordnerlisten, UTF-8-Textdateien, Schreibvorschläge und „Im Finder zeigen“; kein allgemeines Shell- oder Terminalwerkzeug.
- Kanonische Pfadprüfung blockiert absolute Pfade, `..`, versteckte/sensible Pfade und Symlinks aus dem Arbeitsordner heraus.
- Schreibvorschläge zeigen Ziel, Begründung und vollständigen Inhalt. Erst „Schreiben freigeben“ führt die atomische Änderung aus.
- Eine Datei wird nicht überschrieben, wenn sie seit der Vorschau extern verändert wurde.
- Live-Plan, Aktivitätskarten, nachgewiesene Werkzeugresultate, Fehlerstatus und Stop-Schaltfläche statt nicht überprüfbarer Modellbehauptungen.
- Begrenzte Modellschritte, Ausgabelimits, ein Abbruchknopf und längere, harte Netzwerk-Timeouts verhindern Endlosschleifen und blockierende Agentenläufe.

Die Kopfzeile bleibt dabei bewusst schlicht: ein kompakter Umschalter für Chat, Agent und Gruppe, ein gemeinsames Aktionsmenü sowie ein Zahnrad für die Einstellungen.

Beispiel: „Erstelle `Geschichte.txt` mit einer kurzen Geschichte und zeige die Datei danach im Finder.“ Der lokale Agent bereitet den Inhalt vor; erst nach der Freigabe wird die Datei geschrieben und im Finder markiert.

## Neu in v18

- **Colored Text Parser 2.0:** tolerante Farben, deutsche Aliase, Markierungen, Verschachtelung und automatische Bereinigung fehlerhafter Tags.
- **Native Tabellen:** Markdown-Tabellen und reparierbarer Pipe-Text werden als zugängliche SwiftUI-Tabellen gerendert.
- **Native Charts:** strukturierte Zahlenreihen erscheinen mit Swift Charts als Balken-, Linien- oder Flächendiagramm.
- **Aufgabenabhängige Ausgabe:** Tabellen und Charts werden über strenge Ollama-JSON-Schemas erzeugt und von der App in kanonische Chat-Blöcke umgewandelt.
- **Strenge Webrecherche:** bis zu fünf eindeutige Treffer, bis zu drei gelesene Seiten, Belegprüfung und Quellen direkt an Aussagen. Nicht belegbare Modellantworten werden verworfen.
- **Gemini-Quellenbereiche:** Bytebereiche aus Grounding-Annotationen werden als Quellenmarker an den passenden Textstellen dargestellt.
- **Transparenter Status:** Treffer- und Seitenanzahl stammen aus der App-Pipeline, nicht aus Behauptungen des Modells.
- **Kompakte Fehlerkarte:** Kurztext, Details, Wiederholen und Schließen. Nach einem Fehler pausiert die autonome Schleife.
- **Modellberatung:** Qwen 3.5 9B ist der Standard für einen 16-GB-Mac. Qwen 3.5 35B bleibt auswählbar, wird wegen seines Speicherbedarfs aber rot gewarnt.
- **Sichere Migration:** bestehende `sessions-v13.json` bleiben lesbar; vor dem ersten v18-Schreiben wird einmalig `sessions-v13.pre-v18.json` angelegt.
- **Sitzungswiederherstellung:** Vor jedem neuen Speichern wird die zuletzt gültige Sitzungsdatei atomisch als `sessions-v13.last-good.json` gesichert. Eine beschädigte Hauptdatei fällt beim nächsten Start auf diese Sicherung zurück.
- **Stabilitätsfix 18.0.1:** Qwen-Denkmodus blockiert die sichtbare Antwort nicht mehr; Chat-Bubbles passen sich wieder dem Inhalt an und eine dauerhaft laufende SwiftUI-Animationsschleife wurde entfernt.
- **Resilienzfix 18.0.2:** Abgebrochene Antworten hinterlassen keinen blockierenden Zustand mehr; Streaming und Scrollen werden gedrosselt, Rich-Inhalte gecacht und lokale Modellanfragen erhalten klare Zeit- und Kontextgrenzen. Unvollständige JSON-Hüllen gelangen nicht mehr in die Bubble; dynamische Nachrichten verwenden eine stabile Liquid-Glass-nahe Materialfläche.
- **Sparkle-Updates:** Seit v18.1.0 enthält die App Sparkle 2.9.2, prüft einmal täglich auf signierte Updates und bietet „Nach Updates suchen …“ im App-Menü sowie in den Einstellungen. Das geprüfte Framework wird lokal mitgeliefert, damit der Build nicht von einem erneuten Download abhängt.
- **Eigene App-Identität:** Ein neues Liquid-Glass-Chat-Icon ersetzt das generische macOS-Programmsymbol.
- **Zwei getrennte Designs:** „Aktuelles Design“ bewahrt das bisherige Erscheinungsbild unverändert. „Transparent Glass“ besitzt eigene dauerhaft gespeicherte Regler für 0–100 % Hintergrunddeckkraft und 0–24 Blur, eine Live-Vorschau und einen separaten Reset.
- **Barrierefreies Glas:** Bei „Transparenz reduzieren“ verwendet Transparent Glass automatisch solide lesbare Flächen; „Bewegung reduzieren“ deaktiviert optionale UI-Animationen. Tabellen, Charts, Fehlerkarten und Eingabe bleiben auch bei 0 % Fensterhintergrund lesbar.
- **Transparent-Glass-Polish 18.1.1:** Der leere KI-Chat zeigt keine unnötige Startkarte mehr. Header und Eingabe-Chrome sind im zweiten Design wirklich transparent; nur interaktive Schaltflächen behalten eine klar erkennbare Liquid-Glass-Fläche. Ein kontrastierender Texthalo erhält die Lesbarkeit ohne deckenden Hintergrund.
- **Version:** v18.1.1 (Build 23).

## Automatische Updates

Diese Version ist die erste Ausgabe mit eingebautem Sparkle. Sie muss daher noch einmal manuell per DMG installiert werden. Ab der darauffolgenden veröffentlichten Version kann die App Updates selbst laden und installieren.

Der veröffentlichte Feed ist `https://raw.githubusercontent.com/LeonTOfficial/AutonomousAIChat/main/appcast.xml`; Downloads und Versionshinweise stehen unter [GitHub Releases](https://github.com/LeonTOfficial/AutonomousAIChat/releases). Private Signierschlüssel gehören ausschließlich in den macOS-Schlüsselbund und niemals in dieses Projekt oder eine ZIP-Datei. Der genaue Release-Ablauf steht in `UPDATE-RELEASE.md`.

## Internetzugriff

### Ollama lokal

Lokale Inferenz benötigt keinen API-Key. Live-Recherche verwendet separat die Ollama Web Search API. Ohne gültigen Web-Key führt v18 keine angebliche Live-Recherche durch, sondern zeigt einen transparenten Status.

Für eine Recherche werden höchstens fünf eindeutige Suchtreffer gesammelt und die besten drei Seiten zusätzlich gelesen. Eine Modellbehauptung erscheint nur, wenn ihre Quellen-ID gültig ist und ihr Beleg tatsächlich im abgerufenen Inhalt vorkommt.

### Gemini

Mit Ollama-Web-Key kann Gemini denselben überprüften Web-Kontext nutzen. Andernfalls versucht Gemini bei passenden Fragen Google Search Grounding. Quellen werden anhand der gelieferten Textbereiche direkt an Aussagen gebunden.

## Ollama-Modelle

- `qwen3.5:9b` – Standard und für diesen Mac empfohlen, ungefähr 6,6 GB
- `qwen3.5:35b` – auswählbar, ungefähr 24 GB; auf 16 GB RAM deutlich zu groß

Die App vergleicht die Modellgröße mit dem physischen Speicher: bis 50 % grün, bis 80 % gelb, darüber rot. Eine bewusste Auswahl wird nicht blockiert. Downloads zeigen Fortschritt und können abgebrochen werden.

## Start

```bash
cd ~/Downloads/AutonomousAIChat-v18
chmod +x start.command
./start.command
```

Nur bauen und die `.app` erzeugen, ohne sie zu öffnen:

```bash
./start.command --build-only
```

Eine lokale DMG, eine Sparkle-Update-ZIP und die uploadbare Quell-ZIP werden mit folgendem Befehl erzeugt:

```bash
./scripts/package_release.sh
```

## Tests

```bash
swift test
swift build -c release
./start.command --build-only
```

Die vollständige Prüfliste steht in `TESTING.md`.

## Lokale Daten und Datenschutz

- Gemini- und Ollama-Web-Key liegen im macOS-Schlüsselbund.
- Gruppen-Chats und Gedächtnis liegen lokal in `~/Library/Application Support/AutonomousAIChat/`.
- Der KI-Chat ist temporär und startet beim Öffnen leer.
- Lokale Ollama-Inferenz bleibt lokal.
- Bei Websuche wird die Suchanfrage an die konfigurierte Such-API gesendet; gelesene Inhalte werden nur für die aktuelle Antwort verwendet.

Weitere Einzelheiten stehen in `PRIVACY.md`. Sicherheitsprobleme bitte nicht zusammen mit API-Schlüsseln oder privaten Chatdaten in ein öffentliches Issue kopieren; siehe `SECURITY.md`.
