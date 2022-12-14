#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;

# Core imports
use Unicode::Collate::Locale;

=head1 NAME

beygja_verb_strong.pl - Create a list of all strong verbs.

=head1 SYNOPSIS

  ./beygja_verb_strong.pl

=head1 DESCRIPTION

Go through each verb in the verb database word table and get the
headword.  If the headword ends in "st" then it it is a middle verb;
else, it is an active verb.  Only verbs in the core set with the default
grade are considered.

For active verbs, look for any Faip3v (past singular 3rd person) forms,
including with any special verb code prefixes.  If there are any such
forms that do not end with "i" then the verb is a strong verb.

For middle verbs, look for any Fmip3v (middle past singular 3rd person)
forms, including with any special verb code prefixes.  If there are any
such forms that do not end with "ist" then the verb is a strong verb.

Compile a list of strong verbs.  Sort this list according to the
Icelandic locale and print it out.

The location of the verb database is determined by C<BeygjaConfig.pm>

=cut

# ==================
# Program entrypoint
# ==================

# Allow Unicode in standard output
#
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Check arguments
#
($#ARGV < 0) or die "Wrong number of program arguments!\n";

# Connect to verb database using the configured path
#
my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);

# Perform a work block that will contain all operations
#
my $dbh = $dbc->beginWork('r');
my $sth;
my $qr;

# Get an array of all core, default-grade verb headwords and their word
# keys
#
my @verb_array;

$sth = $dbh->prepare(
  "SELECT wlem, wid FROM word "
  . "INNER JOIN grade ON grade.gid = word.gid "
  . "WHERE grade.giv = 1 "
  . "AND word.wvs = 0");
$sth->execute;
for(my $rec = $sth->fetchrow_arrayref;
    defined $rec;
    $rec = $sth->fetchrow_arrayref) {
  push @verb_array, ([
    Beygja::DB->dbToString($rec->[0]),
    $rec->[1]
  ]);
}

# Go through the array and compile the list of strong verbs
#
my @strong_verbs;

for my $vrec (@verb_array) {
  # Get verb fields
  my $verb_lem = $vrec->[0];
  my $verb_wid = $vrec->[1];
  
  # Based on whether this is an active verb or a middle verb, figure out
  # the LIKE keyword we will be searching for as well as the middle flag
  my $like_key;
  my $middle;
  
  if ($verb_lem =~ /st\z/) {
    # Middle verb
    $like_key = "%Fmip3v";
    $middle   = 1;
  } else {
    # Active verb
    $like_key = "%Faip3v";
    $middle   = 0;
  }
  
  # Get any relevant inflection records
  $qr = $dbh->selectall_arrayref(
    "SELECT iform FROM infl WHERE wid=? AND icode LIKE ?", undef,
    $verb_wid, $like_key);
  
  # Strong flag starts clear
  my $is_strong = 0;
  
  # Go through the relevant records
  if (defined $qr) {
    for my $r (@$qr) {
      my $vf = Beygja::DB->dbToString($r->[0]);
      if ($middle) {
        # Middle verb, so check whether weak middle ending
        unless ($vf =~ /ist\z/) {
          $is_strong = 1;
          last;
        }
      } else {
        # Active verb, so check whether weak active ending
        unless ($vf =~ /i\z/) {
          $is_strong = 1;
          last;
        }
      }
    }
  }
  
  # If we identified a strong verb, add it to the array
  if ($is_strong) {
    push @strong_verbs, ($verb_lem);
  }
}

# If we got here, finish the work block successfully
#
$dbc->finishWork;

# Sort the strong verbs in Icelandic style and print them
#
my $col = Unicode::Collate::Locale->new(locale => 'is');
for my $vb ($col->sort(@strong_verbs)) {
  print "$vb\n";
}

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
