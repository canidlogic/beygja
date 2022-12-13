#!/usr/bin/env perl
use v5.14;
use warnings;

# Beygja imports
use Beygja::CSV;

=head1 NAME

gentags.pl - Generate database script record commands for the
inflectional tags table based on a CSV file.

=head1 SYNOPSIS

  ./gentags.pl tags.csv 3

=head1 DESCRIPTION

Reads through the C<tags.csv> data file and reformats each record into a
C<txc> command that can then be included in the database creation
script.  Each line has four non-blank fields (possibly followed by blank
fields).

Script takes a two arguments.  The first is the path to the C<tags.csv>
data file, and the second is the number of lines to skip at the start of
the file, which must be zero or greater.

=cut

# ==================
# Program entrypoint
# ==================

# Set output to UTF-8
#
binmode(STDOUT, ':encoding(UTF-8)') or 
  die "Failed to set Unicode output!\n";

# Get arguments
#
($#ARGV == 1) or die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

my $scount = shift @ARGV;
($scount =~ /\A[0-9]+\z/) or die "Invalid skip count '$scount'!\n";
$scount = int($scount);

# Open the parser
#
my $csv = Beygja::CSV->load($path);

# Skip the header lines
#
$csv->skip($scount);

# Keep reading record lines
#
for(my $rec = $csv->readRecord; defined $rec; $rec = $csv->readRecord) {
  # Make sure at least four fields
  (scalar(@$rec) >= 4) or
    die sprintf("Line %d: Not enough fields!\n", $csv->number);
  
  # Make sure any fields after the fourth are blank
  for(my $j = 4; $j < scalar(@$rec); $j++) {
    ($rec->[$j] eq '') or
      die sprintf("Line %d: Too many fields!\n", $csv->number);
  }
  
  # Check each field does not contain any backslash characters or any
  # ASCII control codepoints
  for my $str (@$rec) {
    (not ($str =~ /\\/)) or
      die sprintf("Line %d: Fields may not have backslashes!\n",
            $csv->number);
    (not ($str =~ /[\x{0}-\x{1f}\x{7f}]/)) or
      die sprintf("Line %d: Fields may not have ASCII controls!\n",
            $csv->number);
  }
  
  # Output the formatted record
  printf("\"%s\" \"%s\"\n  \"%s\"\n  \"%s\"\n    txc\n\n",
          $rec->[0], $rec->[1], $rec->[2], $rec->[3]);
}

# Close the parser
#
$csv->unload;

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
