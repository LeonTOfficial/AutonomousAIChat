# Updates

## v18.1.1 (Build 23)

- leere Startkarte samt überflüssigem Erklärungstext im Transparent-Glass-KI-Chat entfernt
- Header und Eingabebereich im zweiten Design ohne deckende Materialfläche dargestellt
- Liquid-Glass-Flächen auf interaktive Schaltflächen konzentriert und Textkontrast ohne undurchsichtigen Hintergrund abgesichert
- Live-Vorschau um den tatsächlich transparenten Eingabebereich ergänzt
- aktuelles Design und Gruppen-Startansicht unverändert bewahrt

## v18.1.0 (Build 22)

- offizielles Sparkle 2.9.2 als lokal geprüftes XCFramework integriert
- Menüeintrag und Einstellungsbereich für manuelle Updateprüfungen ergänzt
- automatische tägliche Prüfung und automatische Installation sicher signierter Updates aktiviert
- öffentlicher EdDSA-Schlüssel und vorgesehener HTTPS-Appcast im App-Bundle konfiguriert; private Schlüssel bleiben außerhalb des Projekts im Schlüsselbund
- reproduzierbares Release-Skript für DMG, Sparkle-Update-ZIP und uploadbare Quell-ZIP ergänzt
- App-Bundle bindet das Framework über `Contents/Frameworks` ein und prüft alle verschachtelten Sparkle-Komponenten mit strikter Codesign-Verifikation
- Framework-Download aus dem normalen Build entfernt; das offizielle Archiv wurde vor dem Vendoring gegen die von Sparkle veröffentlichte SHA-256-Prüfsumme geprüft
- eigenes macOS-App-Icon im Liquid-Glass-Stil ergänzt
- öffentliche Repository-Hygiene mit Datenschutztext, Security-Hinweisen, `.gitignore` und macOS-CI ergänzt
- lokaler SwiftPM-Buildcache aus dem FileProvider-verwalteten Projektordner nach `${TMPDIR}` verlegt, um sporadische SQLite-/Builddatenbank-I/O-Fehler zu vermeiden
- bisheriges Erscheinungsbild unverändert als auswählbares „Aktuelles Design“ bewahrt
- separaten Modus „Transparent Glass“ mit 0–100 % Hintergrunddeckkraft, Blur 0–24, Live-Vorschau, Reset und dauerhafter Speicherung ergänzt
- lesbare Materialflächen bei vollständig transparentem Fenster sowie Fallbacks für „Transparenz reduzieren“ und „Bewegung reduzieren“ ergänzt
- Design-Persistenz, Reset und Grenzwertbereinigung mit automatisierten Tests abgesichert

## v18.0.2 (Build 21)

- Fensterwechsel und Abbrechen räumen alle ausstehenden Antwortzustände auf, sodass der nächste Chat nicht unbemerkt blockiert wird
- die simulierte Textausgabe reagiert sofort auf Task-Abbruch und entfernt unvollständige Nachrichten sauber
- Scroll-Aufträge werden zusammengefasst statt bei jedem kleinen Textblock die Main-Queue zu füllen
- Rich-Text-Blöcke werden begrenzt zwischengespeichert; kurze Bubbles verwenden nur noch einen Renderer statt zwei paralleler Layoutvarianten
- Ollama-Modellprüfung endet nach sieben Sekunden, normale lokale Antworten nach 55 Sekunden und Recherche nach 90 Sekunden
- lokaler Prompt ist auf 28 Nachrichten und 18.000 Zeichen begrenzt; Recherche nutzt höchstens 16K Kontext und kleinere Quellenblöcke
- abgeschnittene Qwen-JSON-Hüllen werden als Fehler behandelt statt als riesiger Rohtext gerendert
- dynamische Chat-Bubbles nutzen eine stabile Materialfläche, nachdem natives Liquid Glass bei sehr hohen Textansichten messbar CPU und Speicher anwachsen ließ

## v18.0.1 (Build 20)

- Qwen 3.5 antwortet sichtbar, weil Ollamas versteckter Denkmodus für Chat-Ausgaben deaktiviert wird
- kurze Nachrichten erhalten wieder kompakte, inhaltsabhängige Chat-Bubbles
- Zeitstempel steht platzsparend neben dem Namen statt in einer erzwungen breiten Fußzeile
- Tabellen und Charts behalten bewusst eine breite Rich-Content-Bubble
- Providerfehler erscheint als kompakte Glass-Karte statt als durchgehender Balken
- dauernde Timeline-Animation und wiederholte Fensterkonfiguration entfernt, um hohe CPU-Last und Hänger zu verhindern

## v18.0 (Build 19)

- toleranter Colored Text Parser 2.0 mit Aliasen, Verschachtelung und Fehlerbereinigung
- native SwiftUI-Tabellen und Swift-Charts statt Pipe- oder Code-Rohtext
- aufgabenabhängige, strukturierte Ollama-Ausgabe mit Temperatur 0
- strenge Webrecherche mit deduplizierten Treffern, gelesenen Seiten und Belegprüfung
- Quellenmarker an einzelnen Aussagen für Ollama und Gemini
- transparenter Recherche-Pipelinestatus
- kompakte, aufklappbare Provider-/Fehlerkarte und pausierende autonome Schleife
- Qwen 3.5 9B als Standard; Speicherwarnung für Qwen 3.5 35B
- Downloadfortschritt und Abbrechen für lokale Modelle
- v17-kompatible Sitzungsdaten mit automatischer Sicherung vor dem ersten v18-Schreiben
- neues Swift-Testtarget für Rich-Rendering, Recherche und Kompatibilität

## v17.0 (Build 18)

- Hover-Neuer-Chat-Button im KI-Chat
- dynamischere Typing-Animation
- robustes Ollama-JSON-Unwrapping
- Webantworten stärker zusammenfassen statt Rohdaten auszugeben
- sichere Farbtags
- Mermaid-/Chart.js-Rich-Blocks in Chat-Bubbles
- WebKit als isolierte, nicht persistente Vorschau

# Updates

## v16.0
- Neuer-Chat-Knopf direkt oben rechts im KI-Chat.
- Persistenz-Dateischreiben vom MainActor entkoppelt.
- Schutz gegen veraltete Speichervorgänge.
- Zeitlimits für lange Gemini-/Ollama-Anfragen.
- Laufende Antwort kann über das X neben „… schreibt“ abgebrochen werden.
- Diverse Stabilitäts- und Responsiveness-Fixes.

# Updates – v15.0

## Behoben

- KI-Chat startet beim Öffnen/Wechsel immer leer.
- „Alice“ wird im 1:1-KI-Chat durch den tatsächlichen Modell-/Anbieternamen ersetzt.
- Gesprächsthema aus dem Haupt-Header entfernt und in das Chat-/Teilnehmer-Menü verschoben.
- Ollama-Cloud-Auswahlen entfernt/migriert, um wiederkehrende 403-Subscription-Schleifen zu verhindern.
- Gemini 3.1 Pro Preview aus der normalen Free-Auswahl entfernt; vorhandene Auswahl wird auf `gemini-3.7-flash` migriert.
- Veraltete Gemini-2.x-Modelle werden migriert; 404-Modellfehler können automatisch auf das empfohlene Flash-Modell wechseln.
- Internet-Follow-up „schau im Internet nach“ verwendet die vorherige Nutzerfrage als Suchkontext.
- DuckDuckGo-Instant-Answer-Platzhalter durch Ollamas offizielle Web Search API ersetzt.
- Ollama-Antwortstil für natürliches Hochdeutsch verschärft.
- Diagnose erkennt Web-Search-Key, lokale Modellverfügbarkeit und ältere Llama-3-Auswahl.
- Diagnose testet die tatsächlich ausgewählten Gemini-Modelle live, statt nur das Vorhandensein des API-Keys zu prüfen.
- Ollama-Fallback ignoriert Cloud- und Embedding-Modelle, damit als Notfallmodell wirklich ein lokales Chat-Modell gewählt wird.
- Modellkatalog markiert einige kompakte lokale Chat-Modelle als Empfehlung.

## Neu

- Separater Ollama Web Search API-Key im Schlüsselbund.
- Provider-unabhängige Web-Suche mit Ollama Web Search: echte Quellen-Chips für lokale Ollama-Modelle und auf Wunsch auch Gemini.
- Gemini fällt bei nicht verfügbarem Search Grounding kontrolliert auf eine transparente Antwort ohne Live-Daten zurück, statt die komplette Chat-Antwort mit einem API-Fehler zu blockieren.
- KI-Chat ist absichtlich temporär; Gruppen-Chats bleiben persistent.

## Version

`15.0 (Build 16)`
