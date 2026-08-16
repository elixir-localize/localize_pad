Locale: `en`

```
# Money, rates and tax

# Percentages, without remembering which way round

30% of 700
200 + 10%
200 - 10%

// A percentage of a percentage stays a
// percentage.
10% + 20%

# Tax, added or removed

// The rate is yours to state. There is no
// default and no setting — rates differ by
// country and by US state, so a sheet carries
// its own and means the same thing to whoever
// opens it. Change this line and every answer
// below it follows.
VAT = 15%

// `on` adds tax to a net figure. `of` takes it
// out of a gross one. They are different
// questions and they give different answers.
VAT on $300
VAT of $300

// So removing tax from a total is a division, not
// a subtraction.
$300 - VAT

# Asking it backwards

// When you cannot remember which way the
// operation goes, say what you know and put
// `what` where the answer should be.

180 is what % off 200
180 is what % of 200
220 is what % more than 200

// Those are three different questions about the
// same two numbers, which is exactly why guessing
// between them is a bad idea.

20 is 10% of what

# Borrowing

monthly repayment on $10,000 over 6 years at 6%
interest on $10,000 over 6 years at 6%

# Rates

$99 per week
$99 per week to months
$30/day is what per year

# Converting currency

// Rates are fetched once a day and cached, so a
// sheet full of conversions costs one request
// between updates. Where no rates are configured
// these lines say they have none rather than
// inventing a number.
200 EUR in AUD

// The name works as well as the code — in your
// own language, singular or plural.
200 EUR in Australian dollars

// Or ask for your own currency without naming it.
// The territory in your locale decides which that
// is, the same way it decides miles or kilometres.
// Switch the locale above to en-AU and watch this
// line change.
200 EUR in preferred currency
```
