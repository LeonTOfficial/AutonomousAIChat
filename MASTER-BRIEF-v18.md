# AutonomousAIChat v18 – Master-Brief

Stand: 17. August 2026  
Version: 18.1.0 (Build 22)  
Projekt: native macOS-App mit SwiftUI, Swift Charts und WebKit

## Ziel

v18 macht aus Modelltext verlässliche, native Chat-Inhalte. Tabellen, Charts, Farbtags und Recherchequellen werden nicht mehr ungeprüft als Rohtext angezeigt. Schwächere lokale Modelle erhalten enge strukturierte Vorgaben; die App validiert und rendert das Ergebnis selbst.

`AutonomousAIChat-v18` ist eine eigene Projektkopie. Die Quelle `AutonomousAIChat-v17-2` wurde nicht bearbeitet. Vorhandene v17-Sitzungen bleiben lesbar. Die während des früheren Audits erzeugte Alice-Nachricht wurde weder verändert noch gelöscht.

## Umgesetzte Architektur

### Rich-Rendering

- `ColoredTextParser` ist ein zustandsbasierter Token-Parser für `red`, `green`, `blue`, `yellow`, `purple` und `mark` samt deutschen Aliasen.
- Verschachtelung wird unterstützt. Offene Tags enden am Absatz. Verwaiste oder falsche bekannte End-Tags verschwinden. Unbekannte Tags bleiben normaler Text.
- `RichMessageParser` erkennt Markdown-Tabellen und reparierbaren einzeiligen Pipe-Text. Die Ausgabe erfolgt als SwiftUI-Grid mit Kopfzeile, alternierenden Zeilen, horizontalem Scrollen, Textauswahl und VoiceOver-Beschriftung.
- `ChartPayloadParser` akzeptiert das v18-Datenformat und kompatible ältere Chart.js-Konfigurationen. Balken-, Linien- und Flächendiagramme werden nativ über Swift Charts angezeigt.
- Mermaid bleibt für allgemeine Abläufe erhalten. Das WebKit-Navigation-Delegate entspricht Swift 6; CDN- oder Renderfehler erscheinen verständlich in der Bubble.

### Aufgabenabhängige Modellausgabe

- `ResponseIntent` unterscheidet normalen Text, farbigen Text, Tabelle, Chart und Recherche mit gewünschter Darstellung.
- Ollama erhält bei Tabellen und Charts ein strenges JSON-Schema, Temperatur `0` und begrenzten Kontext.
- Die App dekodiert die JSON-Hülle und wandelt sie in kanonische Markdown- beziehungsweise Chart-Blöcke um. Das Modell entscheidet nicht über die SwiftUI-Darstellung.
- Recherche-Charts werden ausschließlich aus Zahlen bereits validierter Aussagen gebaut. Die zitierten Aussagen bleiben zusätzlich sichtbar.

### Verlässliche Recherche

- Bis zu fünf eindeutige Suchtreffer werden gesammelt.
- Die drei besten Seiten werden zusätzlich über Ollama `web_fetch` gelesen; bei Fetch-Ausfall bleibt höchstens das Suchsnippet als Belegbasis.
- Jede `EvidenceClaim` braucht eine gültige Quellen-ID und ein hinreichend langes, im geladenen Inhalt tatsächlich vorkommendes Zitat.
- Bei ungültigem Modell-JSON oder falschen Belegen gibt es genau einen Reparaturversuch. Danach wird die unbelegte Antwort vollständig verworfen.
- Quellenmarker `[S1]`, `[S2]` usw. stehen direkt an den belegten Aussagen und sind anklickbar.
- Trefferanzahl und gelesene Seiten stammen aus `ResearchStatus` der App-Pipeline.
- Ohne Web-Key oder ohne belastbare Inhalte behauptet die App keine Live-Recherche.
- Gemini-Annotationen dekodieren `start_index` und `end_index` als UTF-8-Bytebereiche und setzen Quellenmarker an die zugehörige Textstelle.

### Datenmodell und Migration

- `ChatMessage.text` bleibt die kompatible Primärquelle.
- Optional ergänzt wurden `citations` und `researchStatus`.
- `AIReply` transportiert Text, Quellen, Quellenbereiche und Recherchemetadaten.
- Vor dem ersten v18-Schreiben wird neben einer vorhandenen `sessions-v13.json` einmalig `sessions-v13.pre-v18.json` erzeugt.
- Alte Nachrichten ohne die neuen optionalen Felder werden weiterhin dekodiert.

### UI und Modelle

- Rich-Inhalte nutzen die volle Bubble-Breite; bei normalen Nachrichten stehen Name und Zeit kompakt oberhalb der inhaltsbreiten Bubble.
- Provider-Hinweis und Fehler sind eine kompakte, aufklappbare Karte mit Kurztext, Details, Wiederholen und Schließen.
- Die autonome Schleife läuft nach einem Fehler nicht weiter, bis der Nutzer reagiert.
- Qwen 3.5 9B ist Standard und wird für einen 16-GB-Mac empfohlen.
- Qwen 3.5 35B bleibt auswählbar, erhält wegen ungefähr 24 GB Modellgröße aber eine rote Warnung.
- Modellgröße relativ zum physischen RAM: bis 50 % grün, 50–80 % gelb, darüber rot.
- Lokale Downloads liefern Status und Fortschritt und können abgebrochen werden.

### Design-Modi und Barrierefreiheit

- „Aktuelles Design“ bleibt als eigener Modus mit den bisherigen Farben, Deckkraftwerten, Materialien und Verläufen erhalten. Ein Wechsel zurück stellt exakt diesen Modus wieder her.
- „Transparent Glass“ ist separat auswählbar und speichert Hintergrundfarbe, Deckkraft von 0–100 % sowie Blur von 0–24 unabhängig vom bisherigen Design.
- Bei exakt 0 % und Blur 0 ist der Fensterhintergrund vollständig transparent; Chat-Bubbles, Eingabe, Fehlerkarten, Tabellen und Charts behalten eigene lesbare Materialflächen.
- Einstellungen bieten eine Live-Vorschau und einen Reset ausschließlich auf die Standardwerte von Transparent Glass.
- Es gibt keine dauerhaft laufende Designanimation und keine zeitgesteuerte Blur-Neuberechnung. „Transparenz reduzieren“ aktiviert einen soliden lesbaren Fallback; „Bewegung reduzieren“ unterbindet optionale Übergangsanimationen.

### Sparkle-Updates

- Sparkle 2.9.2 ist als geprüftes, lokal mitgeliefertes XCFramework eingebunden. Der normale Build benötigt keinen erneuten Framework-Download.
- „Nach Updates suchen …“ ist im App-Menü und unter Einstellungen → Allgemein verfügbar; geplante Prüfungen laufen einmal täglich.
- Der App-Bundle enthält den öffentlichen EdDSA-Schlüssel. Der private Schlüssel bleibt ausschließlich im macOS-Schlüsselbund und wird weder gelesen noch ausgeliefert.
- `start.command` bettet Sparkle unter `Contents/Frameworks` ein, ergänzt den passenden Runpath und verifiziert App, Framework, Updater und XPC-Dienste strikt.
- Das lokal startbare App-Bundle wird außerhalb des FileProvider-verwalteten Dokumentordners unter `${TMPDIR%/}/AutonomousAIChat-v18-app-build` zusammengesetzt. So kann macOS keine Finder-Metadaten an signierte Sparkle-Unterkomponenten hängen.
- `scripts/package_release.sh` erzeugt DMG, Sparkle-Update-ZIP und eine bereinigte Quell-ZIP.
- Der signierte GitHub-Appcast und das v18.1.0-Release sind öffentlich. Feed, Archivlänge, Versionsdaten und EdDSA-Signatur wurden nach der Veröffentlichung zurückgelesen und validiert.

## Tests

Das Swift-Testtarget `AutonomousAIChatTests` deckt 20 Fälle ab:

- gültige, offene, verschachtelte, falsche und verwaiste Farbtags
- unbekannte Tags und Absatzgrenzen
- Standard-Markdown-Tabelle und einzeilige Modell-Tabelle
- Pipe-Zeichen in normalem Text
- gültiges Chart und ungleiche Datenlängen
- Intent-Priorität
- gültige Recherchebelege
- erfundene Quelle oder erfundenes Zitat
- natives Chart aus validierten Recherchewerten
- v17-Nachricht ohne v18-Metadaten
- Qwen-Laufzeitregel gegen reine Denktext-Antworten
- kompakte Plaintext- und breite Rich-Content-Bubble-Regel
- sichere Ablehnung einer abgeschnittenen Ollama-JSON-Hülle
- HTTPS-Updatefeed und Länge des eingebetteten Ed25519-Public-Keys
- Standardwert und dauerhafte Auswahl beider Design-Modi
- Reset und Grenzwertbereinigung für Transparent-Glass-Deckkraft und Blur

Veröffentlichungsbefehle:

```bash
swift test
swift build -c release
./start.command --build-only
./scripts/package_release.sh
```

## Bekannte Grenzen

- Semantische Widersprüche innerhalb einer realen Quelle werden nicht durch einen Faktenchecker aufgelöst; v18 garantiert zunächst die Quellenbindung und das Vorkommen des Belegs.
- Recherche-Charts benötigen mindestens zwei belegte Aussagen mit erkennbaren Zahlen. Andernfalls bleibt die sichere zitierte Textantwort stehen.
- Mermaid benötigt für die Bibliothek weiterhin eine Netzwerkverbindung zum konfigurierten CDN; ohne Netz erscheint der neue Fehlerzustand.
- Die tatsächliche Qualität lokaler Antworten hängt weiterhin vom installierten Modell ab. Die strukturierte Pipeline begrenzt Formatfehler, ersetzt aber kein leistungsfähigeres Modell.
- API-Verfügbarkeit, Kontingente und Änderungen externer Anbieter lassen sich nur live prüfen.
- Die bereits installierte v18.0.2 besitzt noch keinen Updater. Deshalb ist eine letzte manuelle Installation der Sparkle-fähigen DMG nötig.
- Das öffentlich verteilte Bundle ist mangels lokal verfügbarem Developer-ID-Zertifikat ad-hoc signiert und nicht notarisiert. Sparkles EdDSA-Signatur schützt das Updatearchiv unabhängig davon; für eine warnungsfreie Erstinstallation außerhalb dieses Macs bleibt Developer-ID-Signierung plus Apple-Notarisierung der nächste Release-Schritt.

## Stabilitätskorrektur 18.0.1

- Qwen 3.5 gab bei kleinem Ausgabelimit nur sein internes `thinking` zurück und ließ `content` leer. Ollama-Anfragen setzen deshalb nun `think: false`; die strukturierte Validierung bleibt vollständig aktiv.
- Eine dauerhaft aktualisierte `TimelineView(.animation)` und wiederholte Fensterkonfiguration verursachten bis zu 100 % CPU. Die Schreibanzeige ist nun statisch und die Fensterkonfiguration läuft nur einmal pro Fenster.
- Normale Chat-Bubbles verwenden ihre natürliche Inhaltsbreite. Nur Tabellen, Charts, Code und Mermaid erhalten weiterhin bewusst die breite Rich-Darstellung.

## Resilienzkorrektur 18.0.2

- Abbruch, Fensterwechsel und Hintergrundzustand löschen ausstehende Antwortmarker vollständig. Eine unterbrochene Anfrage kann den nächsten Chat dadurch nicht mehr still blockieren.
- Simuliertes Streaming prüft Task-Abbruch bei jedem Schritt, entfernt Teilantworten und veröffentlicht deutlich weniger View-Aktualisierungen.
- Scroll-Ereignisse werden entprellt und ersetzen einen älteren noch ausstehenden Auftrag. Die Main-Queue kann sich bei langen Antworten nicht mehr mit Scroll-Kommandos füllen.
- Rich-Parsing nutzt einen begrenzten, threadsicheren Cache. Das Bubble-Layout erzeugt nur noch einen Inhaltsbaum und berechnet für normalen Text eine deterministische kompakte Breite.
- Ollama-Aufrufe besitzen gestaffelte Zeitlimits. Prompt und Recherchekontext sind begrenzt, damit lange Sitzungen und Webinhalte das lokale Modell nicht unnötig in Speicher- oder Latenzspitzen treiben.
- Unvollständige Qwen-JSON-Hüllen werden nicht mehr als sichtbarer Rohtext übernommen. Dynamische Chat-Bubbles verwenden eine stabile Materialfläche, weil ein Live-Test bei einer sehr hohen Textansicht im nativen Liquid Glass eine reproduzierbare CPU-/Speicher-Wachstumsschleife gezeigt hat.

## Wichtige Dateien

- `Sources/AutonomousAIChat/RichMessageContent.swift` – Parser und native Renderer
- `Sources/AutonomousAIChat/ResponseFormatting.swift` – Intent, Schemas und Belegvalidierung
- `Sources/AutonomousAIChat/AIService.swift` – Provider-, Recherche- und Strukturpipeline
- `Sources/AutonomousAIChat/Models.swift` – kompatibles Nachrichtenmodell
- `Sources/AutonomousAIChat/ContentView.swift` – Bubble-, Quellen- und Fehler-UI
- `Sources/AutonomousAIChat/SettingsView.swift` – Modellstatus, Speicherberatung, Downloads und beide Design-Modi
- `Sources/AutonomousAIChat/AppUpdater.swift` – langlebiger Sparkle-Controller und Updatekanal
- `Sources/AutonomousAIChat/ConversationStore.swift` – v18-Sicherung
- `Tests/AutonomousAIChatTests/RichContentTests.swift` – automatisierte Tests
- `UPDATE-RELEASE.md` – sicherer Release- und Appcast-Ablauf

## Direkt kopierbarer Auftrag für normales ChatGPT

```text
Ich arbeite an AutonomousAIChat v18, einer nativen macOS-SwiftUI-App. Im Anhang befindet sich AutonomousAIChat-v18.zip. Lies zuerst README.md, MASTER-BRIEF-v18.md, TESTING.md und Package.swift. Prüfe anschließend die vorhandene Implementierung, bevor du Änderungen vorschlägst.

Wichtige Regeln:
1. AutonomousAIChat-v17-2 ist die unveränderte Ausgangsversion und darf nicht bearbeitet werden.
2. Bestehende v17-Sitzungen und die zusätzlich vorhandene Alice-Nachricht dürfen nicht verändert oder gelöscht werden.
3. Bewahre „Aktuelles Design“ unverändert als eigenen Modus. „Transparent Glass“ ist ein separater Modus mit eigenen persistenten Werten und darf das bisherige Design nicht ersetzen.
4. Rechercheantworten dürfen ausschließlich belegte Informationen aus tatsächlich geladenen Quellen zeigen. Keine erfundenen Quellen oder Browserbehauptungen.
5. Tabellen, Charts und Farbtags müssen über die vorhandenen nativen Parser/Renderer laufen, nicht als roher Pipe-Text oder ausführbarer Modellcode.
6. Qwen 3.5 9B ist der lokale Standard; 35B bleibt optional mit Speicherwarnung.
7. Keine Schlüssel, Sitzungsdaten, Logs oder Build-Caches in Lieferdateien aufnehmen.
8. Vor einer Änderung den Ist-Stand und die Tests prüfen. Danach mindestens swift test und swift build -c release ausführen.
9. Der private Sparkle-Schlüssel bleibt im macOS-Schlüsselbund. Veröffentlichungen, Tags, Releases und Appcast-Änderungen brauchen meine ausdrückliche Freigabe.

Aktueller Stand: Colored Text Parser 2.0, native Tabellen, native Swift-Charts, ResponseIntent, strikte Ollama-JSON-Schemas, Belegvalidator, Gemini-Quellenbereiche, Recherche-Pipelinestatus, kompakte Fehlerkarte, pausierende autonome Schleife, Modellgrößenberatung, Downloadfortschritt, v17-Migrationssicherung, zwei getrennte Design-Modi und Sparkle 2.9.2 sind implementiert. Lies den Master-Brief und UPDATE-RELEASE.md für Architektur, Tests, Grenzen und Release-Ablauf.

Bitte beginne mit einem kurzen Audit der ZIP und nenne konkrete Risiken oder Verbesserungsvorschläge mit Dateibezug. Implementiere erst, wenn ich dich ausdrücklich dazu auffordere.
```
