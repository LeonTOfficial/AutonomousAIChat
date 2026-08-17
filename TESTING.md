# Testing v18.1.1

## Automatisierte Prüfung

```bash
for file in Sources/AutonomousAIChat/*.swift Tests/AutonomousAIChatTests/*.swift; do
  swiftc -parse "$file"
done
swift test
swift build -c release
./start.command --build-only
```

`start.command` verwendet für SwiftPM absichtlich einen isolierten Buildordner unter `${TMPDIR}`, damit synchronisierte Dokumentordner keine Builddatenbankfehler verursachen.

Abgedeckte Fälle:

- gültige, offene, verschachtelte, falsche und verwaiste Farbtags sowie unbekannte Tags
- Standard-Markdown-Tabellen, einzeiliger Pipe-Text und normale Sätze mit Pipe-Zeichen
- gültige und ungültige Chartdaten
- Aufgabenabsicht und Priorität von Recherche plus Rich-Ausgabe
- exakte Recherchebelege sowie erfundene Quellen-IDs und Zitate
- rückwärtskompatibles Dekodieren einer v17-Nachricht ohne v18-Metadaten
- deaktivierter Ollama-Denkmodus für sichtbare Qwen-Antworten
- kompakte Plaintext-Bubbles und bewusst breite Rich-Content-Bubbles
- gedrosselte Streaming-/Scroll-Aktualisierung, bereinigter Abbruchzustand und begrenzter Ollama-Kontext
- unvollständige Ollama-JSON-Hüllen werden nicht als Rohtext dargestellt
- Sparkle-Feed verwendet HTTPS und der eingebettete Ed25519-Public-Key ist exakt 32 Byte lang
- „Aktuelles Design“ bleibt Standard und die Modusauswahl wird dauerhaft gespeichert
- Transparent-Glass-Reset sowie sichere Grenzwerte für Deckkraft und Blur
- der leere KI-Chat blendet nur in Transparent Glass die Startkarte aus

## Manuelle Live-Abnahme

1. Qwen 3.5 9B auswählen und prüfen, dass es als empfohlen und passend markiert ist.
2. Qwen 3.5 35B auswählen und die rote Speicherwarnung prüfen; die Auswahl muss trotzdem möglich sein.
3. Einen Modelldownload starten: Fortschritt und Abbrechen müssen funktionieren.
4. `[red]Rot[/red]`, `[grün]Grün[/grün]`, verschachtelte Markierung, offenes Tag und verwaistes End-Tag testen.
5. „Mach eine Tabelle mit drei Produkten und Preisen“: native Tabelle statt Pipe-Rohtext.
6. „Zeige die Werte Januar 2, Februar 5, März 4 als Liniendiagramm“: natives Swift-Chart.
7. Mermaid-Ablaufdiagramm testen; bei fehlendem CDN muss ein verständlicher Fehlerzustand erscheinen.
8. Webrecherche mit gültigem Key: Quellenmarker an Aussagen und Status wie „5 Treffer gefunden · 3 Seiten gelesen“.
9. Recherche mit erfundener Quellen-ID oder nicht vorhandenem Zitat: unbelegte Aussagen dürfen nicht erscheinen.
10. Fehlenden Web-Key prüfen: transparenter Status statt erfundener Recherche.
11. Providerfehler auslösen: eine kompakte Fehlerkarte erscheint und die autonome Schleife pausiert bis Wiederholen oder Schließen.
12. Vorhandene v17-Sitzungsdatei öffnen und prüfen, dass `sessions-v13.pre-v18.json` vor dem ersten v18-Schreiben entsteht.
13. Gruppen- und KI-Chat, Neuer-Chat-Knopf, Antwortabbruch und Scrollen zur neuesten Nachricht prüfen.
14. Release-App auf beiden Displays kontrollieren.
15. Qwen 3.5 9B mit „Hallo“ testen: sichtbare Antwort statt leerem `content` nach reinem Denktext.
16. Während und nach der Schreibanzeige die CPU prüfen; nach dem Schließen des Fensters darf keine Animationsschleife weiterlaufen.
17. Kurze Nutzer- und KI-Nachrichten prüfen: Bubble ist inhaltsbreit, Zeit steht neben dem Namen und es gibt keine leere Fußzeile.
18. Während einer langen Antwort abbrechen, das Fenster schließen und erneut öffnen: die Teilantwort verschwindet und die nächste Nachricht erhält normal eine Antwort.
19. Eine längere Antwort streamen lassen: Scrollen und Eingabe bleiben flüssig; der Prozess darf im Leerlauf keine dauerhafte CPU-Last erzeugen.
20. Eine absichtlich zu lange Qwen-Antwort auslösen: statt JSON-Rohtext erscheint eine kompakte Fehlerkarte; danach müssen CPU und Speicher stabil bleiben.
21. Im App-Menü und unter Einstellungen → Allgemein „Nach Updates suchen …“ prüfen.
22. Bei einem absichtlich nicht erreichbaren Feed muss Sparkle einen verständlichen Fehler anzeigen und die Chat-Oberfläche danach weiter reagieren.
23. Unter Einstellungen → Design zwischen „Aktuelles Design“ und „Transparent Glass“ wechseln, die App neu starten und die persistierte Auswahl prüfen.
24. Transparent Glass mit Hintergrunddeckkraft 0 % und Blur 0 auf beiden Displays prüfen; Bubble, Eingabe, Fehlerkarte, Tabelle und Chart müssen lesbar bleiben.
25. Transparent Glass zurücksetzen und danach zu „Aktuelles Design“ wechseln; das bisherige Erscheinungsbild muss exakt wiederhergestellt werden.
26. macOS „Transparenz reduzieren“ und „Bewegung reduzieren“ aktivieren und den soliden, ruhigen Fallback ohne dauerhafte Animation prüfen.
27. In Transparent Glass einen leeren KI-Chat öffnen: keine Startkarte und kein erklärender Text; Header und Eingabebereich bleiben transparent, während Plus-, Personen- und Senden-Schaltflächen als Liquid Glass erkennbar sind.

## Veröffentlichung

- Keine Schlüssel, Sitzungsdaten, Logs, `.build`- oder `.app-build`-Ordner in der ZIP.
- `Info.plist` meldet v18.1.1 (Build 23) und enthält `SUFeedURL`, `SUPublicEDKey` sowie das tägliche Prüfintervall.
- `Info.plist` referenziert `AppIcon.icns`, das im App-Bundle vorhanden ist.
- `Sparkle.framework`, Updater, Downloader und Installer liegen im App-Bundle und bestehen `codesign --verify --deep --strict`.
- Das Update-Archiv wird erst nach menschlich kontrollierter EdDSA-Signatur in einen Appcast aufgenommen.
- Originalordner `AutonomousAIChat-v17-2` bleibt unverändert.
- ZIP-Integrität mit `unzip -t AutonomousAIChat-v18.zip` prüfen.
