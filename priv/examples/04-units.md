Locale: `en`

```
# Units

// Around 2,760 units, from CLDR and from the GNU
// units database.

# Converting

42.195 km to miles
3 meters to feet
100 kg to pounds
25 celsius to fahrenheit

# Compound units, assembled as you write them

60 mph to km/h
100 kg * 9.8 m/s^2

// Juxtaposition binds tighter than an explicit
// divide, so this reads as (kg × m) / s² — the
// same rule GNU units follows.

# Mixing units in one sum

12 ft + 3 in
1 hour + 45 minutes

# Data

500 GB to TB
1.5 MB per second to GB per hour

# Whatever your part of the world measures in

// `local units` asks for the answer the way a
// reader here would write it, and CLDR decides
// what that means from the territory in your
// locale — not from the language.
//
// Switch the locale to en-AU and this stays in
// kilometres. Switch to en-US and it becomes
// miles. en-GB gets miles too, and yet keeps
// Celsius below, because that is what Britain
// actually does.
42.195 km in local units
70 kg in local units
25 celsius in local units

// The word can follow the value directly, which
// is the natural order in most languages.
42.195 km locally

# What the quantity is for

// `preferred units` is usually all you need. The
// unit says which kind of measure it is and the
// territory says how that kind is written, so
// nothing else has to be spelled out. `local
// units` says the same thing.
70 kg in preferred units
2 metres in preferred units

// What neither can know is what the number is
// *for*. 70 kg is stone if it is a person and
// pounds if it is a sack of cement. Litres could
// be a drink, a dam, or someone's blood — so the
// answer without a usage is deliberately the
// plain one rather than a guess. Say what the
// number is for and it changes.
70 kg in preferred weight units
1.8 m in preferred height units
2 litres in preferred fluid units

// Switch the locale to en-GB to see why it earns
// its keep: the weight comes back in stone, and
// the drink in imperial fluid ounces.

// These words only count directly after
// `preferred`, so `height` is still yours to use
// as a name.
height = 1.8 m
height * 2
```
