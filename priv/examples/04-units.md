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
```
