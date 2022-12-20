#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;
use Beygja::Util qw(isInteger verbParadigm);

=head1 NAME

beygja_verb_conj.pl - List all the filtered conjugated forms of a given
verb.

=head1 SYNOPSIS

  ./beygja_verb_conj.pl 3716

=head1 DESCRIPTION

Using the C<verbParadigm()> function from C<Beygja::Util>, report all
the filtered conjugated forms of the verb with a given word ID.  See the
documentation of C<verbParadigm()> for further information about the
conjugation filtering.

The given word ID is the primary key within the Beygja database, I<not>
the DMII ID/BIN.ID.

The location of the verb database is determined by C<BeygjaConfig.pm>

=cut

# ==================
# Program entrypoint
# ==================

# Allow Unicode in standard output
#
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Get arguments
#
($#ARGV == 0) or die "Wrong number of program arguments!\n";

my $wordkey = shift @ARGV;
($wordkey =~ /\A[0-9]+\z/) or die "Invalid word key argument!\n";

$wordkey = int($wordkey);
isInteger($wordkey) or die "Invalid word key argument!\n";

# Connect to verb database using the configured path
#
my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);

# Build a verb paradigm for the given word key
#
my %vpara = verbParadigm($dbc, $wordkey);

# Print all the forms
#
for my $iform (sort keys %vpara) {
  # Get the value of this form
  my $val = $vpara{$iform};
  
  # Print the form header
  printf "%s -", $iform;
  
  # Print all forms
  if (ref($val)) {
    # Multiple values
    for my $v (@$val) {
      printf " %s", $v;
    }
    
  } else {
    # Single scalar value
    printf " %s", $val;
  }
  
  # Line break
  print "\n";
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
