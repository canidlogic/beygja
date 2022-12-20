#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;
use Beygja::Util qw(
  isInteger
  isIcelandic
  stemSyllables
  stemUShift
  verbParadigm
  findMixedVerb
  isStrongVerb
  isSpecialVerb
  wordList
);

# Core imports
use Unicode::Collate::Locale;

=head1 NAME

beygja_verb_finite.pl - Check finite forms of regular verbs.

=head1 SYNOPSIS

  ./beygja_verb_finite.pl strict
  ./beygja_verb_finite.pl loose -A +F_ip__

=head1 DESCRIPTION

Go through all verbs in the core list defined by C<wordList()> in the
C<Beygja::Util> module.  For each verb, load the verb paradigm using the
C<verbParadigm()> function.

The first program argument is either C<strict> or C<loose>.  This
argument only applies when for a specific verb form, there are more
inflection records than predictions.  If C<strict> is on, matching fails
if for any specific verb form present in both the inflection records and
the predictions, the set of forms is not exactly the same.  If C<loose>
is on, matching is allowed to pass if the predictions are a subset of
the inflection records.

Any program arguments after the first program argument control which
predicted forms are examined.  By default, all predicted forms are
examined.  The filter arguments are processed from left to right, with
arguments beginning with C<-> removing predicted forms and arguments
beginning with C<+> adding predicted forms.  You can use an underscore
C<_> in the predicted form to match any single symbol in the inflection
code.  The special inflection code C<A> matches all inflection codes, so
that C<-A> removes all inflected forms and C<+A> adds all inflected
forms.

Only certain verbs are considered by this script.  Using functions from
the C<Beygja::Util> module, all verbs matching C<isSpecialVerb()>,
C<isStrongVerb()>, and C<findMixedVerb()> are filtered out, so that only
weak verbs are considered.

For verbs that are not filtered out, the first step is to get the
principal parts.  The first principal part is the headword, which
represents the active infinitive, or the middle infinitive if the verb
lacks active voice.  The second principal part is the past tense.  This
is the C<Faip3v> form unless the headword ends in I<st>, in which case
the second principal part is the C<Fmip3v> form.  The past tense form
must exist and there may not be variants, or else the verb will be
reported as non-conforming.

The location of the verb database is determined by C<BeygjaConfig.pm>

=cut

# ===============
# Local functions
# ===============

# filterMatch(pattern, str)
# -------------------------
#
# Check whether a pattern passed through the program arguments matches a
# given string.
#
# pattern is the pattern to check.  If it is just 'A' then it always
# matches.  Otherwise, check for a specific match to str, with
# underscores in the pattern meaning any one character allowed at that
# position.
#
sub filterMatch {
  # Get parameters
  ($#_ == 1) or die;
  
  my $pattern = shift;
  my $str     = shift;
  
  ((not ref($pattern)) and (not ref($str))) or die;
  
  # If pattern is 'A' then match
  if ($pattern eq 'A') {
    return 1;
  }
  
  # If we got here, make sure length of pattern equals length of str,
  # else no match
  (length($pattern) == length($str)) or return 0;
  
  # If we got here, then get locations of underscores in the pattern
  my @uloc;
  while ($pattern =~ /_/g) {
    push @uloc, (pos($pattern) - 1);
  }
  
  # Replace all the underscore locations in the match string with
  # underscores
  for my $ui (@uloc) {
    substr($str, $ui, 1, '_');
  }
  
  # Check whether strings now match
  if ($pattern eq $str) {
    return 1;
  } else {
    return 0;
  }
}

# allVerbCodes()
# --------------
#
# Return an array in list context of all inflection codes supported by
# this script.
#
sub allVerbCodes {
  # Check parameters
  ($#_ < 0) or die;
  
  # Result starts empty
  my @result;
  
  # Add all finite codes
  for my $voice ('a', 'm') {
    for my $mood ('i', 's') {
      for my $tense ('r', 'p') {
        for my $person ('1', '2', '3') {
          for my $number ('v', 'w') {
            push @result, (sprintf(
              "F%s%s%s%s%s",
              $voice, $mood, $tense, $person, $number
            ));
          }
        }
      }
    }
  }
  
  # @@TODO:
  
  # Return result
  return @result;
}

# regularVerbPrincipals($headword, \%paradigm)
# --------------------------------------------
#
# Given a verb headword and its conjugated paradigm, return in list
# context an array of two values.  The first value is the (possibly
# artificial) infinitive and the second value is an array reference
# storing one or more (possibly artificial) past singular principal
# part variants.  All principal parts are in active voice, even if the
# verb is a middle voice verb that does not exist in active voice.
#
# If the headword ends in "st" then the verb is assumed to be a middle
# voice verb.  The returned active-voice principal parts will be
# artificial in that case.
#
# If the headword does not end in "st" then first a check is made
# whether a Faip3v form exists.  If it does not exist, then this
# function will recursively call through to itself with the same
# parameters, except "st" will be suffixed to the headword.  Otherwise,
# the first value will match the headword and the second value will be
# the Faip3v form.
#
# If the process fails, undef is returned for both values.  The process
# will fail if the paradigm lacks forms for Faip3v (or Fmip3v for middle
# verbs).  The process will also fail if any past singular principal
# part would not end in "i", indicating a strong verb that is not
# handled by this function.
#
sub regularVerbPrincipals {
  # Get parameters
  ($#_ == 1) or die;
  
  my $headword = shift;
  isIcelandic($headword) or die;
  
  my $vpara = shift;
  (ref($vpara) eq 'HASH') or die;
  
  # Handle the regular and middle-voice cases
  if ($headword =~ /st\z/) { # =========================================
    # Middle-voice headword, so we need to get Fmip3v forms
    (defined $vpara->{'Fmip3v'}) or return (undef, undef);
    
    my @mvpast;
    if (ref($vpara->{'Fmip3v'})) {
      @mvpast = map { $_ } @{$vpara->{'Fmip3v'}};
    } else {
      push @mvpast, ( $vpara->{'Fmip3v'} );
    }
    
    # Drop the -st middle ending from the headword and the middle past
    # forms to get the artificial forms, and check that none of the past
    # forms indicate a strong verb
    my $art_hw = $headword;
    $art_hw    =~ s/st\z//;
    
    for my $vf (@mvpast) {
      $vf =~ s/st\z//;
      ($vf =~ /i\z/) or return (undef, undef);
    }
    
    # Return the artificial forms
    return ($art_hw, \@mvpast);
    
  } else { # ===========================================================
    # Active-voice headword -- if there are no Faip3v forms, then
    # recursively call through with a middle-voice headword
    (defined $vpara->{'Faip3v'})
      or return regularVerbPrincipals($headword . 'st', $vpara);
    
    my @p_past;
    if (ref($vpara->{'Faip3v'})) {
      @p_past= map { $_ } @{$vpara->{'Faip3v'}};
    } else {
      push @p_past, ( $vpara->{'Faip3v'} );
    }
    
    # Check that this isn't a strong verb
    for my $vf (@p_past) {
      ($vf =~ /i\z/) or return (undef, undef);
    }
    
    # Return the principal parts
    return ($headword, \@p_past);
  }
}

# regularVerbFinite($inf, $past, $sycount)
# ----------------------------------------
#
# Given the active infinitive principal part, the past singular
# principal part, and the number of stem syllables, return a hash in
# list context that maps verb conjugation forms to their predicted
# values according to regular verb conjugation rules.
#
# The past form must end in -i because strong verbs are not supported by
# this function.
#
sub regularVerbFinite {
  # Get parameters
  ($#_ == 2) or die;
  
  my $inf = shift;
  isIcelandic($inf) or die;
  
  my $past = shift;
  isIcelandic($past) or die;
  
  my $sycount = shift;
  (isInteger($sycount) and ($sycount > 0)) or die;
  
  # Start the prediction empty
  my %vp;
  
  # Make sure we didn't get a strong verb
  ($past =~ /i\z/) or die;
  
  # First, we need to get the stem from the infinitive; if the
  # infinitive does not end in -a then the stem is equivalent to the
  # infinitive; else, the stem is equivalent to the infinitive if the
  # past principal part ends in -aði or drops the final -a in all other
  # cases
  my $inf_stem;
  if ($inf =~ /a\z/) {
    # Infinitive ends in -a; check whether past ends in -aði
    if ($past =~ /aði\z/) {
      # Past ends in -aði so infinitive stem keeps the -a
      $inf_stem = $inf;
    } else {
      # Past doesn't end in -aði so infinitive stem loses the -a
      $inf_stem = $inf;
      $inf_stem =~ s/a\z//;
    }
    
  } else {
    # Infinitive does not end in -a so infinitive stem is equivalent
    $inf_stem = $inf;
  }
  
  # The v_stem is the infinitive stem with a final -a dropped if present
  my $v_stem = $inf_stem;
  $v_stem =~ s/a\z//;
  
  # The u_stem is the U-shifted v_stem
  my $u_stem = stemUShift($v_stem, $sycount);
  
  # The vj_stem is the v_stem with the j-rule applied
  my $vj_stem = $v_stem;
  $vj_stem =~ s/([gkæý])j\z/$1/;
  $vj_stem =~ s/eyj\z/ey/;
  
  # Add the present singular forms
  if (($inf_stem =~ /a\z/) or ($inf eq 'meina')) {
    # If infinitive stem ends in -a, use -ar conjugation
    # EXCEPTION: meina always uses -ar conjugation
    $vp{'Fair1v'} = $v_stem . 'a';
    $vp{'Fair2v'} = $v_stem . 'ar';
    $vp{'Fair3v'} = $v_stem . 'ar';
  } else {
    # If infinitive stem ends in -i, use -ir conjugation
    # EXCEPTION: meina never uses -ir conjugation
    $vp{'Fair1v'} = $vj_stem . 'i';
    $vp{'Fair2v'} = $vj_stem . 'ir';
    $vp{'Fair3v'} = $vj_stem . 'ir';
  }
  
  # Add the present plural forms
  $vp{'Fair1w'} =  $u_stem . 'um';
  $vp{'Fair2w'} = $vj_stem . 'ið';
  $vp{'Fair3w'} = $inf;
  
  # Add the present subjunctive forms
  $vp{'Fasr1v'} = $vj_stem . 'i' ;
  $vp{'Fasr2v'} = $vj_stem . 'ir';
  $vp{'Fasr3v'} = $vj_stem . 'i' ;
  $vp{'Fasr1w'} =  $u_stem . 'um';
  $vp{'Fasr2w'} = $vj_stem . 'ið';
  $vp{'Fasr3w'} = $vj_stem . 'i' ;
  
  # The past stem is the past principal part with the final i dropped
  my $past_stem = $past;
  $past_stem =~ s/i\z//;
  
  # The past stem syllable count is the same as the verb stem syllable
  # count, except one greater if the past stem ends in "að"
  my $past_count = $sycount;
  if ($past_stem =~ /að\z/) {
    $past_count++;
  }
  
  # Past plural stem is u-shifted past singular
  my $past_plural = stemUShift($past_stem, $past_count);
  
  # Add the past singular and plural forms
  $vp{'Faip1v'} = $past_stem . 'i';
  $vp{'Faip2v'} = $past_stem . 'ir';
  $vp{'Faip3v'} = $past_stem . 'i';
  $vp{'Faip1w'} = $past_plural . 'um';
  $vp{'Faip2w'} = $past_plural . 'uð';
  $vp{'Faip3w'} = $past_plural . 'u';
  
  # For regular verbs, the past subjunctive equals past indicative
  $vp{'Fasp1v'} = $vp{'Faip1v'};
  $vp{'Fasp2v'} = $vp{'Faip2v'};
  $vp{'Fasp3v'} = $vp{'Faip3v'};
  $vp{'Fasp1w'} = $vp{'Faip1w'};
  $vp{'Fasp2w'} = $vp{'Faip2w'};
  $vp{'Fasp3w'} = $vp{'Faip3w'};
  
  # @@TODO:
  
  # Return the prediction
  return %vp;
}

# ==================
# Program entrypoint
# ==================

# Allow Unicode in standard output
#
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Get first argument
#
($#ARGV >= 0) or die "Wrong number of program arguments!\n";

my $strict_match = shift @ARGV;
if ($strict_match eq 'strict') {
  $strict_match = 1;
} elsif ($strict_match eq 'loose') {
  $strict_match = 0;
} else {
  die "Unknown matching mode '$strict_match'!\n";
}

# Start list of verb codes out with all verb codes
#
my %allowed_codes;
for my $code (allVerbCodes()) {
  $allowed_codes{$code} = 1;
}

# Process any remaining arguments as filters on the list of allowed verb
# codes
#
while ($#ARGV >= 0) {
  # Get next filter code
  my $fcode = shift @ARGV;
  
  # Parse the filter code
  unless ($fcode =~ /\A([\-+])(.+)\z/) {
    die "Invalid filter code '$fcode'!\n";
  }
  my $fmode = $1;
  my $fpat  = $2;
  
  # Handle filter code according to mode
  if ($fmode eq '+') { # ===============================================
    # Additive, so first build a list of all matching codes in the set
    # of all possible codes
    my @matches;
    for my $code (allVerbCodes()) {
      if (filterMatch($fpat, $code)) {
        push @matches, ($code);
      }
    }
    
    # Now add all the matched codes to the allowed list
    for my $match (@matches) {
      $allowed_codes{$match} = 1;
    }
    
  } elsif ($fmode eq '-') { # ==========================================
    # Subtractive, so first build a list of all matching codes currently
    # in the allowed codes
    my @matches;
    for my $code (keys %allowed_codes) {
      if (filterMatch($fpat, $code)) {
        push @matches, ($code);
      }
    }
    
    # Now drop all the matched codes
    for my $match (@matches) {
      delete $allowed_codes{$match};
    }
    
  } else { # ===========================================================
    die;
  }
}

# Connect to verb database using the configured path and wrap all in a
# single transaction
#
my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);
my $dbh = $dbc->beginWork('r');
my $qr;

# Get the core wordlist
#
my @wlist = wordList($dbc, "core");

# Get an Icelandic collator
#
my $col = Unicode::Collate::Locale->new(locale => 'is');

# Look for any irregular verbs
#
for my $rec (@wlist) {  
  # Conjugate the current verb and get headword and stem syllables
  my %conj = verbParadigm($dbc, $rec->[1]);
  my $headword = $rec->[0];
  my $sycount = stemSyllables($dbc, $rec->[1]);
  
  # If stem syllables undefined, assume one
  unless (defined $sycount) {
    $sycount = 1;
  }
  
  # If verb is a special verb (preterite-present or vera), or a strong
  # verb, or a mixed verb, then skip this record
  if (isSpecialVerb($headword)
        or isStrongVerb(\%conj)
        or (defined findMixedVerb($dbc, $headword))) {
    next;
  }
  
  # We need to get the principal parts
  my ($p_inf, $p_past) = regularVerbPrincipals($headword, \%conj);
  unless (defined $p_inf) {
    printf "Failed to get principal parts for '%s' (key %d)!\n",
            $headword, $rec->[1];
    next;
  }
  
  # Start an empty predicted conjugation
  my %prediction;
  
  # Add predicted values using all possibilities for the the past
  # singular principal part; also, filter out all predictions except
  # those for codes on the allowed list
  for my $ppart (@$p_past) {
    # Get a prediction for this past principal part
    my %pred = regularVerbFinite($p_inf, $ppart, $sycount);
    
    # Merge this prediction into the predicted conjugation, applying
    # prediction filtering
    for my $k (keys %pred) {
      # Skip if key is not in allowed list
      (defined $allowed_codes{$k}) or next;
      
      # Check whether key exists in prediction
      if (defined $prediction{$k}) {
        # Key exists in prediction, so check whether new predicted value
        # is already in list
        my $already_present = 0;
        if (ref($prediction{$k})) {
          for my $apv (@{$prediction{$k}}) {
            if ($apv eq $pred{$k}) {
              $already_present = 1;
              last;
            }
          }
          
        } else {
          if ($prediction{$k} eq $pred{$k}) {
            $already_present = 1;
          }
        }
        
        # Proceed only if new predicted value not already in list
        unless ($already_present) {
          # Convert to array value if not already converted
          unless (ref($prediction{$k})) {
            $prediction{$k} = [ $prediction{$k} ];
          }
          
          # Add this prediction to the list of forms
          push @{$prediction{$k}}, ( $pred{$k} );
        }
        
      } else {
        # Key does not exist in prediction, so copy the scalar
        # prediction value over
        $prediction{$k} = $pred{$k};
      }
    }
  }
  
  # For any values in the prediction that are arrays, collate the
  # entries according to Icelandic rules
  for my $k (keys %prediction) {
    if (ref($prediction{$k})) {
      my @sorted = $col->sort(@{$prediction{$k}});
      $prediction{$k} = \@sorted;
    }
  }
  
  # For all predicted keys that exist in the actual paradigm, check that
  # they equal the prediction or else clear the match flag
  my $match_flag = 1;
  for my $k (keys %prediction) {
    # Skip this key if it is not in the actual paradigm
    (defined $conj{$k}) or next;
    
    # Get sets of all paradigm values and all predicted values
    my %para_vals;
    my %pred_vals;
    
    if (ref($prediction{$k})) {
      for my $v (@{$prediction{$k}}) {
        $pred_vals{$v} = 1;
      }
    } else {
      $pred_vals{$prediction{$k}} = 1;
    }
    
    if (ref($conj{$k})) {
      for my $v (@{$conj{$k}}) {
        $para_vals{$v} = 1;
      }
    } else {
      $para_vals{$conj{$k}} = 1;
    }
    
    # Check that each predicted value is in paradigm
    for my $v (keys %pred_vals) {
      unless (defined $para_vals{$v}) {
        $match_flag = 0;
        last;
      }
    }
    $match_flag or last;
    
    # If strict matching requested, make sure predicted and paradigm
    # have same number of keys
    if ($strict_match) {
      unless (scalar(keys %pred_vals) == scalar(keys %para_vals)) {
        $match_flag = 0;
        last;
      }
    }
  }
  
  # Report the headword and ID if no match
  unless ($match_flag) {
    printf "Misprediction: '%s' %d\n", $headword, $rec->[1];
  }
}

# Finish transaction
#
$dbc->finishWork;

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
