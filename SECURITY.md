# Sicherheitsrichtlinie

## Unterstützte Version

Sicherheitskorrekturen werden für die jeweils neueste veröffentlichte Version bereitgestellt.

## Problem vertraulich melden

Bitte für Sicherheitsprobleme die private Schwachstellenmeldung des GitHub-Repositories verwenden. Keine API-Schlüssel, privaten Chats, Sitzungsdateien oder vollständigen Diagnose-Logs in öffentliche Issues einfügen.

Eine gute Meldung enthält:

- betroffene App-Version und macOS-Version
- reproduzierbare Schritte mit unkritischen Testdaten
- erwartetes und tatsächliches Verhalten
- mögliche Auswirkungen

## Update-Vertrauen

Sparkle-Updates müssen eine zum eingebetteten öffentlichen EdDSA-Schlüssel passende Signatur besitzen. Der private Signierschlüssel bleibt außerhalb von Repository, App-Bundle und Release-Artefakten im macOS-Schlüsselbund.
