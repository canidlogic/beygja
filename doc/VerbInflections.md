# Beygja verb inflection codes

Verb inflection forms in the Beygja database use a special short string code to identify exactly which part of a verb an inflected form represents.

Inflection codes are a sequence of US-ASCII alphanumerics (case sensitive) and the four symbols `.` `:` `,` `;`

There is always exactly one uppercase letter in each inflection code, which specifies the inflection class.  The uppercase letter is either the first or second character in the code.  It can only be the second character if it is preceded by one of the four symbols.

The order of characters within the code is as follows:

    1. (Prefix)        one of   .:,;
    2. (Class)         one of   FQIMRPS
    3. (Voice)         one of   am
    4. (Mood/Strength) one of   is
    5. (Tense)         one of   rp
    6. (Person/Gender) one of   123
    7. (Number)        one of   vwz
    8. (Case)          one of   4567

There must always be a Class character.  All other characters are optional.  When multiple characters appear, they must be in the order shown above.

## Prefixes

Prefixes are only allowed when the class is `F` (finite).  Each prefix indicates that there is something special about the subject:

    . means "dummy subject" (það)
    : means accusative subject
    , means dative subject
    ; means genitive subject

The rest of the inflection code after the prefix works exactly like the `F` finite class.  However, there are certain restrictions on which finite forms can be used with certain prefixes:

1. Genitive subject prefix can only be used with active voice
2. Accusative subject prefix can only be used with active voice
3. Dummy subject prefix can only be used with 3rd person singular

## Class

Each inflection code requires exactly one uppercase letter, which specifies the inflection class:

    F - finite
    Q - question-form
    I - infinitive
    M - imperative
    R - present participle
    P - past participle
    S - supine

The _question form_ is a special form defined in the DIM for 2nd-person questions where the pronoun fuses to the end of the verb form.  Question forms are not recognized in all Icelandic grammars.

The _past participle_ refers to the declined adjective forms of the past participle, while the _supine_ is the fixed form of the past participle used in compound tenses.

## Voice

Inflection classes `FQIMS` use the voice category:

    a - active voice
    m - middle voice

No other inflection classes may use the voice category.

## Mood and Strength

Inflection classes `F` and `Q` use the mood category:

    i - indicative mood
    s - subjunctive mood

In inflection class `P` (past participle adjective declension), the mood category is also used, but it has a different meaning:

    i - definite (weak) declension
    s - indefinite (strong) declension

No other inflection classes may use the mood category.

## Tense

Inflection classes `F` and `Q` use the tense category:

    r - present tense
    p - past tense

In inflection class `I` (infinitive), there is normally no tense category.  However, for a few exceptional cases, the past tense value may be added (but never the present tense).  The past tense value is only allowed when the voice is active.

No other inflection classes may use the tense category.

## Person and Gender

Inflection classes `F` and `Q` use the person category:

    1 - First person
    2 - Second person
    3 - Third person

In inflection class `P` (past participle adjective declension), the person category is also used, but it has a different meaning:

    1 - Masculine gender
    2 - Neuter gender
    3 - Feminine gender

No other inflection classes may use the person category.

## Number

Inflection classes `FQMP` use the number category:

    v - Singular number
    w - Plural number

In inflection class `M` (imperative), the number category also allows a third value:

    z - Clipped

The _clipped_ value means an abbreviated imperative form.  The clipped value may only be used in active voice.

No other inflection classes may use the number category.

## Case

In inflection class `P` (past participle adjective declension), the case category selects the case agreement:

    4 - Nominative case
    5 - Accusative case
    6 - Dative case
    7 - Genitive case

No other inflection classes may use the case category.
