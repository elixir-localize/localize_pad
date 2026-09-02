Locale: `en`

```
# Dinner for four

// Every line carries whoever ordered it. A tag
// reaches back to the previous heading and no
// further, so the whole dinner is one section:
// the courses in the order they came, and the
// totals at the end of it.

// Starters
Calamari: 18 #ann
Bread and olives: 9 #bob
Soup: 11 #cara
Arancini: 14 #dan

// Mains
Sea bass: 42 #ann
Pasta: 28 #bob
Ribeye: 46 #cara
Risotto: 31 #dan

// The table as a whole. With no tag, a function
// reports on the block above it — the eight lines
// back to the heading.
sum
average
count

// Now by tag. These reach back over the whole
// section, past the three answers above, and pick
// out only the lines carrying the name.
sum #ann
sum #bob
sum #cara
sum #dan

// Any of the six functions takes a tag, not only
// the sum.
count #ann
max #cara

// Ten per cent for service on the bill above, and
// the wine the table shared, split four ways.
service = 10% of @24
wine = 68
(wine + service) / 4
```
