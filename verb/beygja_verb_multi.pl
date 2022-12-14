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

beygja_verb_multi.pl - Create a list of all verbs with inflectional
variants.

=head1 SYNOPSIS

  ./beygja_verb_multi.pl

=head1 DESCRIPTION

Go through each verb in the verb database word table and get the
headword.  Only verbs in the core set with a default grade are
considered.

For each verb, go through all the associated inflections that have a
default grade.  It any inflection code has more than one form with a
default code, then the verb has inflectional variants.

Compile a list of all verbs with inflectional variants.  Sort this list
according to the Icelandic locale and print it out.

For each verb on the list, report all of the inflection codes that have
variants.

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

# Figure out the default grade
#
$qr = $dbh->selectrow_arrayref("SELECT gid FROM grade WHERE giv = 1");
(defined $qr) or die "Can't find default grade!\n";
my $default_grade = $qr->[0];

# Get an array of all core, default-grade verb headwords and their word
# keys
#
my @verb_array;

$sth = $dbh->prepare(
  "SELECT wlem, wid FROM word WHERE gid = ? AND wvs = 0");
$sth->bind_param(1, $default_grade);
$sth->execute;
for(my $rec = $sth->fetchrow_arrayref;
    defined $rec;
    $rec = $sth->fetchrow_arrayref) {
  push @verb_array, ([
    Beygja::DB->dbToString($rec->[0]),
    $rec->[1]
  ]);
}

# Go through the array and compile the list of verbs with inflectional
# variants
#
my @multi_verbs;

for my $vrec (@verb_array) {
  # Get verb fields
  my $verb_lem = $vrec->[0];
  my $verb_wid = $vrec->[1];
  
  # Start the inflection map empty and the multi-field map empty, and
  # clear the multi_flag to begin with; imap maps inflection codes to
  # the first form read; fmap maps inflection codes to an array of two
  # or more forms, including the first one that was read
  my $imap = {};
  my $fmap = {};
  my $multi_flag = 0;
  
  # Go through all inflections for this word that have a default grade
  $qr = $dbh->selectall_arrayref(
        "SELECT icode, iform FROM infl WHERE wid = ? AND gid = ?",
        undef,
        $verb_wid, $default_grade);
  if (defined $qr) {
    for my $rec (@$qr) {
      # Get current textual code and inflectional form
      my $icode = $rec->[0];
      my $iform = Beygja::DB->dbToString($rec->[1]);
      
      # Check whether textual code already defined for this verb
      if (defined $imap->{$icode}) {
        # Already defined, so set the multi_flag and add this field to
        # the variant field set if not already there
        $multi_flag = 1;
        unless (defined $fmap->{$icode}) {
          $fmap->{$icode} = [$imap->{$icode}];
        }
        push @{$fmap->{$icode}}, ($iform);
        
      } else {
        # Not defined, so add it to the map
        $imap->{$icode} = $iform;
      }
    }
  }
  
  # If multi_flag set, add this verb and its mapping of inflection codes
  # to the multi_verb array
  if ($multi_flag) {
    push @multi_verbs, ([$verb_lem, $fmap]);
  }
}

# If we got here, finish the work block successfully
#
$dbc->finishWork;

# Sort the selected verbs in Icelandic style and print them
#
my $col = Unicode::Collate::Locale->new(locale => 'is');
for my $vb (sort { $col->cmp($a->[0], $b->[0]) } @multi_verbs) {
  printf "%s\n", $vb->[0];
  for my $vf (sort keys %{$vb->[1]}) {
    printf "  %s -", $vf;
    for my $fm (@{$vb->[1]->{$vf}}) {
      print " $fm";
    }
    print "\n";
  }
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
