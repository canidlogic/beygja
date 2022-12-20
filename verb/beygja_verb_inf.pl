#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;
use Beygja::Util qw(verbParadigm wordList);

# Core imports
use Unicode::Collate::Locale;

=head1 NAME

beygja_verb_inf.pl - Create a list of infinitives sorted from the back
of the infinitive to the front.

=head1 SYNOPSIS

  ./beygja_verb_inf.pl active
  ./beygja_verb_inf.pl middle
  ./beygja_verb_inf.pl past

=head1 DESCRIPTION

Go through all infinitives of the given type.  C<active> is active-voice
infinitives, C<middle> is middle-voice infinitives, and C<past> are the
exceptional active-voice past-tense infinitives (of which there are only
a handful).

Print a list of all the distinct infinitives sorted from the end of the
infinitive to the front according to the Icelandic locale.

The location of the verb database is determined by C<BeygjaConfig.pm>

=cut

# ==================
# Program entrypoint
# ==================

# Allow Unicode in standard output
#
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Get argument
#
($#ARGV == 0) or die "Wrong number of program arguments!\n";

my $itype = shift @ARGV;
if ($itype eq 'active') {
  $itype = 'Ia';
} elsif ($itype eq 'middle') {
  $itype = 'Im';
} elsif ($itype eq 'past') {
  $itype = 'Iap';
} else {
  die "Unknown infinitive type '$itype'!\n";
}

# Connect to verb database using the configured path and wrap all in a
# single transaction
#
my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);
$dbc->beginWork('r');

# Get the core wordlist
#
my @wlist = wordList($dbc, "core");

# Compile a set of all unique infinitives for the given class
#
my %iset;

for my $rec (@wlist) {
  # Conjugate the current verb
  my %conj = verbParadigm($dbc, $rec->[1]);
  
  # If this verb has the desired type of infinitive, make sure it is in
  # the set
  if (defined $conj{$itype}) {
    my $val = $conj{$itype};
    if (ref($val)) {
      for my $v (@$val) {
        $iset{$v} = 1;
      }
    } else {
      $iset{$val} = 1;
    }
  }
}

# Finish transaction
#
$dbc->finishWork;

# Get an array of all the unique infinitives that were found
#
my @iarr = keys %iset;

# For sorting purposes, temporarily reverse all strings
#
for my $inf (@iarr) {
  $inf = reverse($inf);
}

# Sort the reversed entries in Icelandic style
#
my $col = Unicode::Collate::Locale->new(locale => 'is');
my @isort = $col->sort(@iarr);

# Re-reverse the entries to get their proper appearance back and print
# each
#
for my $inf (@isort) {
  $inf = reverse($inf);
  print "$inf\n";
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
