package Beygja::Util;
use v5.14;
use warnings;
use utf8;

use parent qw(Exporter);

# Beygja imports
use Beygja::DB;

# Core imports
use Scalar::Util qw(looks_like_number);
use Unicode::Collate::Locale;

=head1 NAME

Beygja::Util - Beygja utility functions.

=head1 SYNOPSIS

  use Beygja::Util qw(
    isInteger
    isIcelandic
    stemSyllables
    stemUShift
    wordList
    verbParadigm
    findMixedVerb
    isStrongVerb
    isSpecialVerb
    dimToVerbCode
  );
  
  # Some functions require a database connection
  use Beygja::DB;
  use BeygjaConfig qw(beygja_dbpath);
  my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);
  
  # Check whether a value is an integer
  if (isInteger($val)) {
    ...
  }
  
  # Check whether a value is a non-empty string in lowercase Icelandic
  if (isIcelandic($str)) {
    ...
  }
  
  # Figure out how many stem syllables for a given word ID
  my $sylcount = stemSyllables($dbc, $word_key);
  if (defined $sylcount) {
    ...
  }
  
  # Apply U-shift to a stem
  my $ushifted = stemUShift($stem, $stem_syllable_count);
  
  # Go through a sorted and vetted word list
  my @wlist = wordList($dbc, 'core');
  for my $rec (@wlist) {
    my $lemma   = $rec->[0];
    my $wordkey = $rec->[1];
    ...
  }
  
  # Build a verb paradigm given a word key
  my %vpara = verbParadigm($dbc, $word_key);
  my $active_infinitive = $vpara{"Ia"};
  if (ref($vpara{"Faip3v"})) {
    # Multiple variants get an array reference with choices
    for my $variant (@{$vpara{"Faip3v"}}) {
      ...
    }
  }
  
  # Check whether verb is mixed and get base mixed infinitive if it is
  my $mixed_inf = findMixedVerb($dbc, $infinitive);
  if (defined $mixed_inf) {
    ...
  }
  
  # Check a verb paradigm to see if the verb is a strong verb
  if (isStrongVerb(\%vpara)) {
    ...
  }
  
  # Check an infinitive to see if a verb is one of the special verbs
  if (isSpecialVerb($infinitive)) {
    ...
  }
  
  # Convert a DIM tag to a verb code and order number
  my ($verb_code, $order_number) = dimToVerbCode("GM-BH-ST2");

=head1 DESCRIPTION

Provides various utility functions.  See the function documentation for
details.

=cut

# ==========
# Local data
# ==========

# The primary key for the default grade in the grade table, or undef if
# this hasn't been cached yet.
#
my $cache_default_grade = undef;

# Cache of mappings from inflection values to their primary keys in the
# database.
#
my %cache_ivalue;

# The Icelandic collation object, or undef if this hasn't been cached
# yet.
#
my $cache_iscol = undef;

# ===============
# Local functions
# ===============

# getDefaultGrade(dbc)
# --------------------
#
# Get the primary key for the default grade in the grade table.
#
# If this value has been cached, the cached value is returned
# immediately.
#
# If this value hasn't been cached, the provided database connection is
# used to read the value, cache it, and return it.
#
sub getDefaultGrade {
  # Get parameters
  ($#_ == 0) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  # Fill cache if necessary
  unless (defined $cache_default_grade) {
    # Open read block
    my $dbh = $dbc->beginWork('r');
    my $qr;
    
    # Get the default grade code
    $qr = $dbh->selectrow_arrayref(
            "SELECT gid FROM grade WHERE giv=?", undef,
            1);
    (defined $qr) or die "Can't find default grade!\n";
    $cache_default_grade = int($qr->[0]);
    
    # Finish read block
    $dbc->finishWork;
  }
  
  # Return the cache
  return $cache_default_grade;
}

# getInflectionValue(dbc, str)
# ----------------------------
#
# Get the primary key for an inflection value record with the given
# abbreviated code.
#
# If this value has been cached, the cached value is returned
# immediately.
#
# If this value hasn't been cached, the provided database connection is
# used to read the value, cache it, and return it.
#
sub getInflectionValue {
  # Get parameters
  ($#_ == 1) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  my $str = shift;
  (not ref($str)) or die;
  
  # Fill cache if necessary
  unless (defined $cache_ivalue{$str}) {
    # Open read block
    my $dbh = $dbc->beginWork('r');
    my $qr;
    
    # Get the requested inflection value
    $qr = $dbh->selectrow_arrayref(
            "SELECT jid FROM ival WHERE jtx=?", undef,
            Beygja::DB->stringToDB($str));
    (defined $qr) or die "Can't find inflection value '$str'!\n";
    $cache_ivalue{$str} = int($qr->[0]);
    
    # Finish read block
    $dbc->finishWork;
  }
  
  # Return the cache
  return $cache_ivalue{$str};
}

# getIcelandicCollator()
# ----------------------
#
# Return an Icelandic collator, using a cached instance if available,
# else filling the cache and returning the new instance.
#
sub getIcelandicCollator {
  # Check parameters
  ($#_ < 0) or die;
  
  # Fill cache if necessary
  unless (defined $cache_iscol) {
    $cache_iscol = Unicode::Collate::Locale->new(locale => 'is');
  }
  
  # Return the cached object
  return $cache_iscol;
}

=head1 FUNCTIONS

=over 4

=item B<isInteger(val)>

Check whether a given value is an integer.

This succeeds only if C<val> passes C<looks_like_number> from
<Scalar::Util> and its absolute value does not exceed C<2^53 - 1> (the
largest integer that can be exactly stored within a double-precision
floating point value).

=cut

use constant MAX_INTEGER => 9007199254740991;
use constant MIN_INTEGER => -9007199254740991;

sub isInteger {
  # Get parameter
  ($#_ == 0) or die;
  my $val = shift;
  
  # Check that it is a number
  looks_like_number($val) or return 0;
  
  # Check that it is in range
  if (($val >= MIN_INTEGER) and ($val <= MAX_INTEGER)) {
    return 1;
  } else {
    return 0;
  }
}

=item B<isIcelandic(val)>

Check whether a given value is a non-empty string that only contains
codepoints within the set of lowercase Icelandic letters.

=cut

sub isIcelandic {
  # Get parameter
  ($#_ == 0) or die;
  my $val = shift;
  
  # Check that it is a scalar
  (not ref($val)) or return 0;
  
  # Check that it is a non-empty lowercase Icelandic string
  if ($val =~ /\A[a-záéíóúýðþæö]+\z/) {
    return 1;
  } else {
    return 0;
  }
}

=item B<stemSyllables(dbc, wordkey)>

Figure out the number of stem syllables that are recorded for a word in
a Beygja database.

C<dbc> is the C<Beygja::DB> connection.  All types of Beygja databases
are supported by this function.

C<wordkey> is the primary key of the word to query.

The return value is either an integer greater than zero that counts the
number of stem syllables, or C<undef> if the stem syllable count is not
available in the database for that word.

=cut

sub stemSyllables {
  # Get parameters
  ($#_ == 1) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  my $wordkey = shift;
  (isInteger($wordkey)) or die;
  
  # Perform query
  my $dbh = $dbc->beginWork('r');
  my $qr = $dbh->selectrow_arrayref(
              "SELECT wsy FROM word WHERE wid=?", undef,
              $wordkey);
  
  (defined $qr) or die "Failed to query word ID '$wordkey'";
  my $result = $qr->[0];
  isInteger($result) or
    die "Word ID '$wordkey' has invalid syllable count";
  
  # If result is less than one, set to undef
  unless ($result >= 1) {
    $result = undef;
  }
  
  # Return result
  return $result;
}

=item B<stemUShift(stem, syl_count)>

Given a stem and a stem syllable count, return the U-shifted stem.

C<stem> is the stem to shift.  It must pass C<isIcelandic()>.  The stem
should not have any inflectional endings.  For infinitive stems that end
in "a" you should probably I<not> include that final "a" in the stem
you pass to this function.

C<syl_count> is an integer greater than zero that indicates how many
syllables are in the stem.  This is used to determine the first vowel in
the passed stem that is subject to U-shift.  If the passed count is
greater than the number of syllables in the stem, it will be clamped to
the total number of syllables in the stem.

=cut

sub stemUShift {
  # Get parameters
  ($#_ == 1) or die;
  
  my $v_stem = shift;
  isIcelandic($v_stem) or die;
  
  my $sycount = shift;
  (isInteger($sycount) and ($sycount > 0)) or die;
  
  # Replace digraphs au, ei, ey with 1, 2, 3 respectively; since we
  # checked that stem passes isIcelandic(), these numbers are not in the
  # passed stem already
  my $va_stem = $v_stem;
  
  $va_stem =~ s/au/1/g;
  $va_stem =~ s/ei/2/g;
  $va_stem =~ s/ey/3/g;
  
  # If there are no standalone a vowels in altered stem, nothing to do
  unless ($va_stem =~ /a/) {
    return $v_stem;
  }
  
  # Build an index of all vowels and dipthongs in the altered v-stem
  my @vloc;
  while ($va_stem =~ /[aeiouyáéíóúýæö123]/g) {
    push @vloc, (pos($va_stem) - 1);
  }
  
  # Count backwards using the syllable count to find the base stem
  # syllable
  my $base_index = scalar(@vloc) - $sycount;

  # Make sure base stem syllable is at least zero
  unless ($base_index >= 0) {
    $base_index = 0;
  }
  
  # Split altered stem into unshifted prefix, base vowel, and a suffix
  # that comes after the initial stem a
  my $prefix = substr($va_stem, 0, $vloc[$base_index]);
  my $base_v = substr($va_stem, $vloc[$base_index], 1);
  my $suffix = substr($va_stem, $vloc[$base_index] + 1);

  # If base vowel is "a" change to 'ö'
  if ($base_v eq 'a') {
    $base_v = 'ö';
  }

  # Shift all a vowels in suffix to u
  $suffix =~ s/a/u/g;
  
  # Rejoin the U-shifted stem
  $va_stem = $prefix . $base_v . $suffix;
  
  # Substitute digraphs back in for numbers
  $va_stem =~ s/1/au/g;
  $va_stem =~ s/2/ei/g;
  $va_stem =~ s/3/ey/g;
  
  # Return altered stem
  return $va_stem;
}

=item B<wordList(dbc, setcode)>

Compile a sorted list of a subset of words in the database.  This works
with all types of Beygja databases.

C<dbc> is a C<Beygja::DB> instance.  This function will use a read-only
work block to read information from the database.

C<setcode> indicates the subset of words you want.  Currently, only the
value C<core> is supported.  In the C<core> subset, the word grade must
indicate a universally accepted word, the visibility must indicate the
word is part of the DMII Core, there must not be any proper name
semantic domains associated with the word, and there must not be any
language register markings on the word.

The return value is an array in list context holding the word list.
Each array element is a subarray reference that contains two values, the
first being the headword as a Unicode string and the second being the
word key in the database.  (The word key is the primary key used in the
database, I<not> the DMII ID or BIN.ID.)

The returned list has the headwords sorted in proper Icelandic order.
Note that headwords are I<not> guaranteed to be unique in the list,
though the word keys I<are> unique.

=cut

sub wordList {
  # Get parameters
  ($#_ == 1) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  my $setcode = shift;
  (not ref($setcode)) or die;
  
  # Get database handle
  my $dbh = $dbc->beginWork('r');
  my $qr;
  my $sth;
  
  # Start result list empty
  my @results;
  
  # Retrieve the appropriate set
  if ($setcode eq 'core') { # ==========================================
    # Get the default grade code
    my $default_grade = getDefaultGrade($dbc);
    
    # Prepare query that retrieves the subset of words
    $sth = $dbh->prepare(
      "SELECT wid, wlem FROM word "
      . "WHERE gid=? "
      . "AND wvs=? "
      . "AND wid NOT IN (SELECT wid FROM wreg) "
      . "AND wid NOT IN ("
      .   "SELECT wid FROM wdom "
      .   "INNER JOIN dom ON dom.did = wdom.did "
      .   "WHERE dom.dlv=?"
      . ")");
    $sth->bind_param(1, $default_grade);
    $sth->bind_param(2, 0);
    $sth->bind_param(3, 2);
    
    # Run the query and build the result list
    $sth->execute;
    for(my $rec = $sth->fetchrow_arrayref;
        defined $rec;
        $rec = $sth->fetchrow_arrayref) {
      push @results, ([
        Beygja::DB->dbToString($rec->[1]),
        $rec->[0]
      ]);
    }
    
  } else { # ===========================================================
    die "Unsupported word list set code '$setcode'!\n";
  }
  
  # Finish work block
  $dbc->finishWork;
  
  # Sort the result list according to headword using the proper 
  # Icelandic collation order, and return the sorted list
  my $col = getIcelandicCollator();
  return sort { $col->cmp($a->[0], $b->[0]) } @results;
}

=item B<verbParadigm(dbc, wordkey)>

Compile a sorted list of a subset of words in the database.  This works
only with the Beygja verb database.

C<dbc> is a C<Beygja::DB> instance.  This function will use a read-only
work block to read information from the database.

C<wordkey> is the integer word record primary key of the verb to load a
paradigm for.  (The primary key used in the database, I<not> the DMII ID
or BIN.ID.)

The return value is a hash in list context holding the mapping of verb
inflection codes to their forms.  When there is only one form for an
inflection code, the value of the mapping is a scalar.  When there is
more than one form for an inflection code, the value of the mapping is
an array reference holding two or more forms, sorted in Icelandic
collation order.  If no forms are documented for a particular inflection
code, there will be no mapping for that inflection code in the returned
hash.

See C<VerbInflections.md> for the format of the verb inflection codes.

B<Note:> This function will collapse all prefixed verb inflection codes
(representing impersonal verbs) into an unprefixed finite form that
adjusts the person and number to C<3v> (since impersonals are always
inflected as though they were 3rd-person singular).  As a result, the
returned hash will never have any keys that use prefixes.

Filtering is applied so that only certain records will be consulted to
build the paradigm.  Only inflection records with a grade indicating the
form is universally accepted will be consulted.  No forms that have an
associated language register will be consulted.  No forms that have the
inflectional value of C<OSB> (indicating they are only used in idioms or
fixed expressions) will be consulted.

If a specific inflection form ends up with multiple values even after
filtering, this function will attempt to choose a preferred form.  If
exactly one of the variants has the inflection value C<RIK> (dominant
form), then that variant will be selected and all the other variants
will be dropped.  Otherwise, multiple variants are reported for the
form, and the variants are sorted in Icelandic collation order.

=cut

sub verbParadigm {
  # Get parameters
  ($#_ == 1) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  my $wordkey = shift;
  isInteger($wordkey) or die;
  
  # Get database handle
  my $dbh = $dbc->beginWork('r');
  my $qr;
  my $sth;
  
  # The intermediate map is like the result map, except all map values
  # are array references and these array references have subarray
  # elements that store the form along with a flag indicating whether
  # the form is marked RIK (dominant)
  my %imap;
  
  # Get the default grade code and the OSB and RIK inflection value
  # primary keys
  my $default_grade = getDefaultGrade($dbc);
  my $ival_OSB = getInflectionValue($dbc, 'OSB');
  my $ival_RIK = getInflectionValue($dbc, 'RIK');
  
  # Prepare query that retrieves the filtered set of inflectional
  # records for this word
  $sth = $dbh->prepare(
    "SELECT infl.icode, infl.iform, t2.nid "
    . "FROM infl "
    . "LEFT OUTER JOIN iflag AS t2 "
    .   "ON ((t2.iid = infl.iid) AND (t2.jid = ?)) "
    . "LEFT OUTER JOIN iflag AS t3 "
    .   "ON ((t3.iid = infl.iid) AND (t3.jid = ?)) "
    . "WHERE wid=? "
    . "AND gid=? "
    . "AND infl.iid NOT IN (SELECT iid FROM ireg) "
    . "AND t3.nid ISNULL");
  $sth->bind_param(1, $ival_RIK);
  $sth->bind_param(2, $ival_OSB);
  $sth->bind_param(3, $wordkey);
  $sth->bind_param(4, $default_grade);
    
  # Run the query and build the intermediate map
  $sth->execute;
  for(my $rec = $sth->fetchrow_arrayref;
      defined $rec;
      $rec = $sth->fetchrow_arrayref) {
    
    # Get the fields
    my $r_icode = Beygja::DB->dbToString($rec->[0]);
    my $r_iform = Beygja::DB->dbToString($rec->[1]);
    my $r_rik   = Beygja::DB->dbToString($rec->[2]);
    
    # Replace r_rik with a flag indicating whether it is defined
    if (defined $r_rik) {
      $r_rik = 1;
    } else {
      $r_rik = 0;
    }
    
    # If inflection code doesn't begin with capital letter, then it has
    # a prefix so drop the prefix, replace person with 3rd and replace
    # number with singular
    unless ($r_icode =~ /\A[A-Z]/) {
      $r_icode = substr($r_icode, 1);
      $r_icode =~ s/[1-3]/3/;
      $r_icode =~ s/[vw]/v/;
    }
    
    # If inflection code not yet defined, add an empty array for it
    unless (defined $imap{$r_icode}) {
      $imap{$r_icode} = [];
    }
    
    # If this form already defined, skip this record
    my $already_defined = 0;
    for my $vf (@{$imap{$r_icode}}) {
      if ($vf->[0] eq $r_iform) {
        $already_defined = 1;
        last;
      }
    }
    (not $already_defined) or next;
    
    # Add this form along with its RIK flag
    push @{$imap{$r_icode}}, ([
      $r_iform,
      $r_rik
    ]);
  }
  
  # Finish work block
  $dbc->finishWork;
  
  # Now build the final result hash, collapsing single-element value
  # arrays into the scalar forms, and either picking a single RIK scalar
  # value out of multi-value arrays or providing an array of scalar
  # forms sorted in proper collation order
  my %results;
  for my $iform (keys %imap) {
    # Get value array
    my $varr = $imap{$iform};
    
    # If value array has more than one element, set sel_index either to
    # the single form that has its RIK flag set or else to -1 indicating
    # a full array; if only a single element, set sel_index to that lone
    # element index
    my $sel_index;
    if (scalar(@$varr) > 1) {
      # Multiple elements; start with sel_index at -1
      $sel_index = -1;
      
      # Scan elements and see if there is a unique element with RIK flag
      # set
      for(my $i = 0; $i < scalar(@$varr); $i++) {
        if ($varr->[$i]->[1]) {
          # Current element has RIK flag set
          if ($sel_index < 0) {
            # No selected element yet, so set this element as the
            # selected one
            $sel_index = $i;
            
          } else {
            # Another element was selected so there are multiple RIK
            # flag elements; set sel_index to -1 and leave loop
            $sel_index = -1;
            last;
          }
        }
      }
      
    } elsif (scalar(@$varr) == 1) {
      # Only a single element, so select that
      $sel_index = 0;
      
    } else {
      die;
    }
    
    # Handle the different selection cases
    if ($sel_index >= 0) {
      # We have a single selected element, so in the result, map this
      # inflection code to a scalar having that form
      $results{$iform} = $varr->[$sel_index]->[0];
      
    } else {
      # We have multiple elements, so add each form into a new array
      my $form_list = [];
      for my $e (@$varr) {
        push @$form_list, ($e->[0]);
      }
      
      # Sort the form list
      my $col = getIcelandicCollator();
      my @sort_list = $col->sort(@$form_list);
      
      # Add the sorted form list to the results
      $results{$iform} = \@sort_list;
    }
  }
  
  # Return the paradigm
  return %results;
}

=item B<findMixedVerb(dbc, infinitive)>

Given an infinitive and a Beygja verb database connection, figure out
whether a verb is mixed, and find its base mixed infinitive if it is.

C<dbc> is a C<Beygja::DB> instance that must refer to the verb database.
It is only used in the first call to this function.  The first call will
cache the whole mixed verb table in memory and use the cache for all
subsequent calls.

C<infinitive> is the infinitive of the verb to check.  If a middle
infinitive is passed, it will be converted to an active infinitive by
this function.  Once the active infinitive is obtained, this function
will check whether the ending of the active infinitive matches any of
the mixed infinitives in the C<mixverb> table.  If a match is found, the
matching mixed infinitive is returned.  Else, C<undef> is returned if
the given infinitive is not for a mixed verb.

The passed infinitive must pass C<isIcelandic()>.

If a defined value is returned by this function, it will match a
substring of the passed infinitive that starts at the last letter if the
passed infinitive was active, or immediately before the "st" suffix if
the passed infinitive was middle.

=cut

# The minimum and maximum lengths of a key in MIXVERB_SET.
#
# These are filled in when the mixed verbs are first cached in memory.
#
my $MIXVERB_MAXLEN = undef;
my $MIXVERB_MINLEN = undef;

# The set of mixed verbs.
#
# This is loaded from the mixverb table in the database.  Keys are
# infinitives and values just map to 1.  This set is only valid when
# MIXVERB_MAXLEN is defined.
#
my %MIXVERB_SET;

# The public function
#
sub findMixedVerb {
  # Get parameters
  ($#_ == 1) or die;
  
  my $dbc = shift;
  (ref($dbc) and $dbc->isa("Beygja::DB")) or die;
  
  my $inf = shift;
  isIcelandic($inf) or die;
  
  # Cache the mixed verb set if not already cached
  unless (defined $MIXVERB_MAXLEN) {
    # Open read work block
    my $dbh = $dbc->beginWork('r');
    my $qr;
    
    # Query the mixed verb infinitives
    $qr = $dbh->selectall_arrayref('SELECT mixverb_inf FROM mixverb');
    if (defined $qr) {
      for my $rec (@$qr) {
        # Get the current mixed verb infinitive and add it to set
        my $vi = Beygja::DB->dbToString($rec->[0]);
        $MIXVERB_SET{$vi} = 1;
        
        # Update length statistics
        if (defined $MIXVERB_MAXLEN) {
          # Statistics defined, so update them
          if (length($vi) > $MIXVERB_MAXLEN) {
            $MIXVERB_MAXLEN = length($vi);
          }
          
          if (length($vi) < $MIXVERB_MINLEN) {
            $MIXVERB_MINLEN = length($vi);
          }
          
        } else {
          # Statistics not defined yet, so initialize them
          $MIXVERB_MAXLEN = length($vi);
          $MIXVERB_MINLEN = $MIXVERB_MAXLEN;
        }
      }
    }
    
    # If we didn't have any records, set the lengths to zero
    unless (defined $MIXVERB_MAXLEN) {
      $MIXVERB_MAXLEN = 0;
      $MIXVERB_MINLEN = 0;
    }
    
    # If we got here, successfully close the read work block
    $dbc->finishWork;
  }
  
  # If we were passed a middle infinitive that ends in -st, drop the
  # final -st to get the active infinitive
  $inf =~ s/st\z//;
  
  # Let $max_compare be the minimum of MIXVERB_MAXLEN and the length of
  # the active infinitive
  my $max_compare = length($inf);
  unless ($max_compare <= $MIXVERB_MAXLEN) {
    $max_compare = $MIXVERB_MAXLEN;
  }
  
  # Start with mixed_verb undefined
  my $mixed_verb = undef;
  
  # Look for matches at the end of the given infinitive
  for(my $i = $max_compare; $i >= $MIXVERB_MINLEN; $i--) {
    # Get the current ending
    my $ce = substr($inf, 0 - $i);
    
    # Check whether in the set
    if (defined $MIXVERB_SET{$ce}) {
      $mixed_verb = $ce;
      last;
    }
  }
  
  # Return result
  return $mixed_verb;
}

=item B<isStrongVerb(paradigm)>

Given a reference to a verb paradigm map, check whether the verb is a
strong verb.

C<paradigm> is a reference to a hash containing a verb paradigm, such as
is returned by the C<verbParadigm()> function.

If the verb has any C<Faip3v> form that does not end with an "i" or it
has any C<Fmip3v> form that does not end with an "ist" then the verb is
a strong verb.  In all other cases, the verb is not a strong verb.

=cut

sub isStrongVerb {
  # Get parameter
  ($#_ == 0) or die;
  my $vp = shift;
  (ref($vp) eq 'HASH') or die;
  
  # Start with strong flag clear
  my $strong_flag = 0;
  
  # Check both Faip3v and Fmip3v for strong forms
  for my $iform ('Faip3v', 'Fmip3v') {
    # Proceed only if form is defined
    if (defined $vp->{$iform}) {
      # Check scalar or array value
      if (ref($vp->{$iform})) {
        # Array value, so check each
        for my $vf (@{$vp->{$iform}}) {
          # Check for appropriate ending
          if ($iform eq 'Faip3v') {
            unless ($vf =~ /i\z/) {
              $strong_flag = 1;
              last;
            }
          
          } elsif ($iform eq 'Fmip3v') {
            unless ($vf =~ /ist\z/) {
              $strong_flag = 1;
              last;
            }
          
          } else {
            die;
          }
        }
        
        # If strong flag now set, leave loop
        (not $strong_flag) or last;
        
      } else {
        # Scalar, so check for appropriate ending
        if ($iform eq 'Faip3v') {
          unless ($vp->{$iform} =~ /i\z/) {
            $strong_flag = 1;
            last;
          }
          
        } elsif ($iform eq 'Fmip3v') {
          unless ($vp->{$iform} =~ /ist\z/) {
            $strong_flag = 1;
            last;
          }
          
        } else {
          die;
        }
      }
    }
  }
  
  # Return resulting strong flag
  return $strong_flag;
}

=item B<isSpecialVerb(infinitive)>

Given an infinitive, check whether it is one of the 11 highly irregular
"special" verbs.

The special verbs include the 10 preterite-present verbs as well as the
copular verb C<vera>.

The passed infinitive must pass C<isIcelandic()>.

=cut

# Set of the headwords for all preterite-present verbs plus vera.
#
my %SPECIAL_VERBS = (
  "eiga"  => 1,
  "kunna" => 1,
  "mega"  => 1,
  "muna"  => 1,
  "munu"  => 1,
  "skulu" => 1,
  "unna"  => 1,
  "vera"  => 1,
  "vilja" => 1,
  "vita"  => 1,
  "þurfa" => 1
);

# The public function
#
sub isSpecialVerb {
  # Get parameter
  ($#_ == 0) or die;
  my $inf = shift;
  isIcelandic($inf) or die;
  
  # Check whether the verb is in the set
  if (defined $SPECIAL_VERBS{$inf}) {
    return 1;
  } else {
    return 0;
  }
}

=item B<dimToVerbCode(str)>

Parse an inflection tag from the DIM data into a Beygja verb inflection
code and an order number.

Returns two values.  The first is the Beygja verb inflection code as a
string and the second is the order number as an integer.  If the
conversion fails, C<undef> is returned for both values.

See the C<VerbInflections.md> documentation file for details about how
the Beygja verb inflection codes work.

DIM data allows for a decimal integer suffix at the end of the
inflection code to indicate variants.  If there is no decimal integer
suffix, the default order number of 1 will be returned.  Otherwise, the
returned order number will match the decimal integer suffix.

This function uses an internal cache to speed things up.  If C<str> has
already been queried, this returns the cached response instead of
recomputing it.  C<str> values that don't successfully convert are
I<not> cached, however.

=cut

# Cache of input strings to array references storing the translated
# Beygja inflection code and the inflection order.
#
my %verbcode_cache;

# Mapping of DIM elements within the inflection tags to the equivalent
# Beygja verb inflection codes.
#
# All DIM elements used for verbs should be keys in the this map.
# However, note that the mapping is not one-to-one!  Sometimes multiple
# DIM elements map to the same Beygja value, sometimes a single DIM
# element maps to more than one Beygja value (indicated by a string
# value with more than one character), and sometimes a single DIM
# element maps to no Beygja values (indicated by an empty string value).
#
my %VERBCODE_MAPPING = (
  'GM'    => 'a',
  'MM'    => 'm',
  'FH'    => 'i',
  'VH'    => 's',
  'NT'    => 'r',
  'ÞT'    => 'p',
  'ET'    => 'v',
  'FT'    => 'w',
  '1P'    => '1',
  '2P'    => '2',
  '3P'    => '3',
  'NH'    => 'I',
  'BH'    => 'M',
  'LHNT'  => 'R',
  'LHÞT'  => 'P',
  'SAGNB' => 'S',
  'SB'    => 's',
  'VB'    => 'i',
  'KK'    => '1',
  'HK'    => '2',
  'KVK'   => '3',
  'NFET'  => 'v4',
  'ÞFET'  => 'v5',
  'ÞGFET' => 'v6',
  'EFET'  => 'v7',
  'NFFT'  => 'w4',
  'ÞFFT'  => 'w5',
  'ÞGFFT' => 'w6',
  'EFFT'  => 'w7',
  'OP'    => '',
  'það'   => '.',
  'ÞF'    => ':',
  'ÞGF'   => ',',
  'EF'    => ';',
  'SP'    => 'Q',
  'ST'    => 'z'
);

# Maps each character in the Beygja verb code alphabet to its order
# category, with lower order categories appearing before higher ones.
#
# It is an error for a Beygja verb code to have multiple characters in
# the same order category, but it is allowed to have empty order
# categories.
#
my %VERBCODE_ORDER = (
  '.' => 0,
  ':' => 0,
  ',' => 0,
  ';' => 0,
  'F' => 1,
  'Q' => 1,
  'I' => 1,
  'M' => 1,
  'R' => 1,
  'P' => 1,
  'S' => 1,
  'a' => 2,
  'm' => 2,
  'i' => 3,
  's' => 3,
  'r' => 4,
  'p' => 4,
  '1' => 5,
  '2' => 5,
  '3' => 5,
  'v' => 6,
  'w' => 6,
  'z' => 6,
  '4' => 7,
  '5' => 7,
  '6' => 7,
  '7' => 7
);

# This array has one record for each of the order values defined in the
# VERBCODE_ORDER map.
#
# Each record in this array is a hash reference to a set of inflection
# class codes that have a value in this category.
#
# This does not include the exceptional past-tense active infinitive,
# nor does it include the restriction that only active imperatives may
# have the clipped value for number, nor the restrictions that the
# different prefixes impose.
#
my @VERBCODE_ALLOW = (
  {'F' => 1},
  {'F' => 1,'Q' => 1,'I' => 1,'M' => 1,'R' => 1,'P' => 1,'S' => 1},
  {'F' => 1,'Q' => 1,'I' => 1,'M' => 1,'S' => 1},
  {'F' => 1,'Q' => 1,'P' => 1},
  {'F' => 1,'Q' => 1},
  {'F' => 1,'Q' => 1,'P' => 1},
  {'F' => 1,'Q' => 1,'M' => 1,'P' => 1},
  {'P' => 1},
);

# The public function
#
sub dimToVerbCode {
  # Get parameter
  ($#_ == 0) or die;
  my $str = shift;
  (not ref($str)) or die;
  
  # If cached response, return that
  if (defined $verbcode_cache{$str}) {
    my $cr = $verbcode_cache{$str};
    return ($cr->[0], $cr->[1]);
  }
  
  # Store original string for caching purposes
  my $original_input = $str;
  
  # Extract the order number first
  my $order_number = 1;
  if ($str =~ /([0-9]+)\z/) {
    $order_number = int($1);
    $str =~ s/[0-9]+\z//;
  }
  
  # String shouldn't be empty now or fail
  (length($str) > 0) or return (undef, undef);
  
  # Start an array of eight elements that will be used to store each of
  # the eight orders for the verb code
  my @varr = (undef, undef, undef, undef, undef, undef, undef, undef);
  
  # Go through each elemental tag in the string
  for my $el (split /\-/, $str) {
    # Skip if this element is not defined or empty
    (defined $el) or next;
    (length($el) > 0) or next;
    
    # Find the verb code mapping
    (defined $VERBCODE_MAPPING{$el}) or return (undef, undef);
    my $vcm = $VERBCODE_MAPPING{$el};
    
    # Go through each character in the verb code mapping
    for my $c (split //, $vcm) {
      # Get the order of this character
      my $vco = $VERBCODE_ORDER{$c};
      
      # Make sure order hasn't been defined yet and then add it
      (not defined $varr[$vco]) or return (undef, undef);
      $varr[$vco] = $c;
    }
  }
  
  # If the inflection class is missing, set it to default F
  unless (defined $varr[1]) {
    $varr[1] = 'F';
  }
  
  # Get the inflection class
  my $iclass = $varr[1];
  
  # Get the combined verb inflection code
  my $vic = '';
  for my $ve (@varr) {
    if (defined $ve) {
      $vic = $vic . $ve;
    }
  }
  
  # Allow the exceptional past-tense infinitive
  if ($vic eq 'Iap') {
    $verbcode_cache{$original_input} = ['Iap', $order_number];
    return ('Iap', $order_number);
  }
  
  # Go through and make sure all categories match what is needed for the
  # inflection class
  for(my $i = 0; $i <= $#varr; $i++) {
    if (defined $varr[$i]) {
      # Category is defined, so make sure it is allowed for this class
      unless (defined $VERBCODE_ALLOW[$i]->{$iclass}) {
        return (undef, undef);
      }
      
    } else {
      # Category is not defined, so make sure it is not allowed for this
      # class; except, skip this check for order 0 (prefixes optional)
      if ($i > 0) {
        if (defined $VERBCODE_ALLOW[$i]->{$iclass}) {
          return (undef, undef);
        }
      }
    }
  }
  
  # The "z" clipped number may only appear for "Maz"
  if ($vic =~ /z/) {
    if ($vic eq 'Maz') {
      $verbcode_cache{$original_input} = ['Maz', $order_number];
      return ('Maz', $order_number);
    } else {
      return (undef, undef);
    }
  }
  
  # If a prefix is defined, check the restrictions
  if (defined $varr[0]) {
    if ($varr[0] eq '.') {
      # Dummy subject can only be used with 3rd person singular
      (($varr[5] eq '3') and ($varr[6] eq 'v')) or
        return (undef, undef);
      
    } elsif (($varr[0] eq ':') or ($varr[0] eq ';')) {
      # Accusative and genitive subject can only be used with active
      # voice
      ($varr[2] eq 'a') or return (undef, undef);
    }
  }
  
  # If we got here, return the conversion
  $verbcode_cache{$original_input} = [$vic, $order_number];
  return ($vic, $order_number);
}

=back

=cut

# ==============
# Module exports
# ==============

our @EXPORT_OK = qw(
  isInteger
  isIcelandic
  stemSyllables
  stemUShift
  wordList
  verbParadigm
  findMixedVerb
  isStrongVerb
  isSpecialVerb
  dimToVerbCode
);

=head1 AUTHOR

Noah Johnson E<lt>noah.johnson@loupmail.comE<gt>

=head1 COPYRIGHT

Copyright 2022 Multimedia Data Technology, Inc.

This program is free software.  You can redistribute it and/or modify it
under the same terms as Perl itself.

This program is also dual-licensed under the MIT license:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

# End with something that evaluates to true
1;
