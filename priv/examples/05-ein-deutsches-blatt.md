Locale: `de`

```
# Ein deutsches Blatt

// Dieselbe Maschine, dieselben Zahlen — nur
// diesmal auf Deutsch. Nicht nur die Antworten
// sind übersetzt, sondern auch die Fragen.

# Zahlen werden deutsch gelesen

1.234,5 + 1

// In einem englischen Blatt wäre das eine ganz
// andere Zahl. Der Punkt ist hier das
// Tausendertrennzeichen, das Komma das Komma.

# Einheiten kommen aus CLDR

3 Meter in Fuß
100 Kilometer in Meilen
1.234,5 Meter in Kilometer

# Prozent

20 % von 700

# Termine

jeden Montag
jeden letzten Freitag

# Fälle, ohne Wörterbuch

// Die Ordnungszahlen stammen aus CLDRs
// Regelsätzen, nicht aus einer Liste. Damit
// kennt das Blatt das ganze Paradigma — `erste`,
// `ersten`, `erster`, `erstem`, `erstes` —
// obwohl keines dieser Wörter hier
// aufgeschrieben wurde.
jeden ersten Montag
jeder erste Montag
jedem ersten Montag

// Dreimal dieselbe Antwort: der Fall ändert die
// Endung, nicht das Ergebnis. Eine
// handgeschriebene Liste hätte die Formen, an
// die jemand gedacht hat.
jeden zweiten Freitag
jedem zweiten Freitag

# Relative Tage

// `heute` und `morgen` stehen in CLDRs Feldern
// für relative Datumsangaben — und mit ihnen
// `übermorgen` und `vorgestern`, die in einer
// handgeschriebenen Liste fast immer fehlen.
heute
übermorgen
vorgestern
jetzt

// Und sie rechnen wie jedes andere Datum.
übermorgen + 3 Tage
heute bis übermorgen

# Werktage

ist der 3. Juli 2026 ein Werktag
3 Werktage nach dem 24. Dezember 2026
welcher Wochentag ist der 24.01.1984

# Datumsrechnung

16.05.2026 + 3 Wochen
10.01.2027 - 05.02.2027

# Ortsübliche Einheiten

// `lokal` fragt nach den Einheiten, die hier
// üblich sind. In Deutschland ändert sich dabei
// wenig — und genau das ist der Punkt. Stellen
// Sie oben en-US ein, und dieselben Zeilen
// antworten in Meilen und Pfund.
42,195 km lokal
70 kg lokal

// Wozu die Größe dient, entscheidet mit: eine
// Körpergröße schreibt man anders als eine
// Entfernung.
1,8 m in lokale Größe
```
