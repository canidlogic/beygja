#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;
use Beygja::Util qw(verbParadigm wordList);

=head1 NAME

beygja_verb_multi.pl - Create a list of all verbs with inflectional
variants.

=head1 SYNOPSIS

  ./beygja_verb_multi.pl

=head1 DESCRIPTION

Go through each verb in the core set defined by the C<wordList()>
function of C<Beygja::Util>.

For each verb, fetch the paradigm using the C<verbParadigm()> function
in the C<Beygja::Util> module.

Compile a list of all verbs that have inflectional variants in their
paradigms.  Print this list out, along with details for each verb
regarding what the variants are.

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
$dbc->beginWork('r');

# Get the core wordlist
#
my @wlist = wordList($dbc, "core");

# Compile the list of verbs with variants
#
for my $vrec (@wlist) {
  # Get verb fields
  my $verb_lem = $vrec->[0];
  my $verb_wid = $vrec->[1];
  
  # Conjugate this verb
  my %conj = verbParadigm($dbc, $verb_wid);
  
  # The verb report flag starts out clear
  my $verb_reported = 0;
  
  # Go through all conjugated fields and look for variants
  for my $k (sort keys %conj) {
    # Only do something with key if it has variants
    if (ref($conj{$k})) {
      # Variants found, so if verb hasn't been reported yet, report the
      # verb headword and set the verb reported flag
      unless ($verb_reported) {
        $verb_reported = 1;
        printf "%s\n", $verb_lem;
      }
      
      # Report this field name
      printf "  %s -", $k;
      
      # Report all variant values for this field
      for my $fm (@{$conj{$k}}) {
        print " $fm";
      }
      
      # Finish the line
      print "\n";
    }
  }
}

# If we got here, finish the work block successfully
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
