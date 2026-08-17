# Datenschutz

AutonomousAIChat ist eine lokale macOS-App. Sie betreibt keinen eigenen Telemetrie- oder Analyse-Dienst.

## Lokal gespeicherte Daten

- Gruppenchats, Sitzungsmetadaten und Langzeitgedächtnis liegen unter `~/Library/Application Support/AutonomousAIChat/`.
- Gemini- und Ollama-Web-Search-API-Keys werden im macOS-Schlüsselbund gespeichert.
- Diagnoseeinträge werden lokal erzeugt und nicht automatisch übertragen.
- Der temporäre 1:1-KI-Chat wird beim Wechsel oder Neustart bewusst verworfen.

## Externe Dienste

- Bei Gemini-Nutzung werden die für eine Antwort benötigten Chat- und Kontextdaten an die konfigurierte Google-Gemini-API übertragen.
- Lokale Ollama-Inferenz bleibt auf dem Mac.
- Bei aktivierter Webrecherche werden Suchanfragen und ausgewählte Seiten über die konfigurierte Ollama-Web-Search-/Web-Fetch-API verarbeitet.
- Die Sparkle-Updateprüfung ruft ausschließlich den öffentlichen Appcast und bei einem Update das verlinkte GitHub-Release-Archiv ab. Systemprofiling ist für Sparkle deaktiviert.

Welche Inhalte an externe Anbieter übertragen werden, hängt von der gewählten Funktion ab. Keine API-Schlüssel oder privaten Chatdateien gehören in öffentliche Issues oder Diagnoseberichte.
