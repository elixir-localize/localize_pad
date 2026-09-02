Locale: `fr`

```
# Une feuille française

// La même machine, les mêmes nombres — en
// français cette fois. Les questions sont
// traduites autant que les réponses.

# Les nombres se lisent en français

1 234,5 + 1

// La virgule est la virgule décimale, et
// l'espace sépare les milliers. Dans une feuille
// anglaise, ce serait un tout autre nombre.

# Les unités viennent de CLDR

3 mètres en pieds
100 kilomètres en miles
1234,5 mètres en kilomètres

# Pourcentages

20 % de 700

# Dates qui reviennent

chaque lundi
chaque dernier vendredi
dernier jour ouvrable de chaque mois

# Le nombre de l'ordinal

// Les ordinaux sortent des jeux de règles RBNF
// de la locale, pas d'une liste écrite à la
// main. Le singulier et le pluriel sont donc
// compris tous les deux, sans qu'aucun des deux
// ait été écrit ici.
le premier lundi de septembre
tous les premiers lundis
quatrième jeudi de novembre
quatrièmes jeudi de novembre

// Les mêmes jeux de règles donnent `première`
// et `dernières`. Rien ici ne les appelle : en
// français, tous les noms de jours sont
// masculins. Elles sont comprises quand même —
// une liste écrite à la main aurait le même trou
// sans que personne s'en aperçoive.

// `second` et `deuxième` disent la même chose,
// et le premier ne se déduit pas du second. Il
// est écrit à la main, et c'est l'exception.
chaque deuxième mardi
chaque second mardi

# Jours relatifs

// `aujourd'hui` et `demain` viennent des champs
// de dates relatives de CLDR — avec
// `après-demain` et `avant-hier`, qui manquent
// presque toujours dans une liste écrite à la
// main.
aujourd’hui
après-demain
avant-hier
maintenant

// Et ils comptent comme n'importe quelle date.
après-demain + 3 jours
aujourd’hui vers après-demain
3 semaines après le 14 mars 2026

# Jours ouvrables

le 3 juillet 2026 est-il ouvrable
3 jours ouvrables après le 24 décembre 2026
quel jour de la semaine est le 24/01/1984

# Les unités d'ici

// `local` demande les unités qu'on écrit ici.
// Mettez en-US en haut, et les mêmes lignes
// répondent en miles et en livres.
42,195 km local
70 kg local

// L'usage compte aussi : une taille ne s'écrit
// pas comme une distance.
1,8 m en taille locale

# Un voyage se planifie en français

// Le mot qui ouvre un voyage, celui qui le
// termine et l'unité des étapes sont français.
// Les dates de chaque étape sortent du format
// d'intervalle de CLDR.
voyage du 3 mars 2026 au 22 mars 2026
3 nuits à Tokyo
5 nuits à Kyoto
4 nuits à Osaka

# Les étiquettes aussi

// Un #mot dit de quelle sorte est une ligne.
// N'importe laquelle des six fonctions peut
// ensuite rendre compte de cette étiquette
// plutôt que du bloc au-dessus d'elle.
Vols : 1 850 € #transport
Train : 435 € #transport
Hôtels : 2 420 € #séjour
Repas : 1 200 € #repas
somme
somme #transport
moyenne #transport
```
