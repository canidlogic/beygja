#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

=head1 NAME

beygja_itag_parse.pl - Analyze all component elements of a list of
inflection tags.

=head1 SYNOPSIS

  ./beygja_itag_parse.pl < input.txt

=head1 DESCRIPTION

The input is a UTF-8 text file, LF or CR+LF line breaks, Byte Order Mark
(BOM) optional at start of first line.  Each line is either blank or
contains a single inflectional tag, possibly surrounded on either side
by tabs and spaces.

For each encountered tag, this script first of all drops any decimal
integer suffix from the end of the tag.  The tag must not be empty after
dropping the decimal integer suffix.

Then, this script parses the tag into one or more elements, where
elements are separated from each other by hyphens.

Each unique element (case sensitive) is stored, and then a list is
printed of all unique elements in sorted order.

=cut

# ==================
# Program entrypoint
# ==================

# Set input to UTF-8 (CR+)LF mode, and output to UTF-8
#
binmode(STDIN, ':encoding(UTF-8) :crlf') or
  die "Failed to set Unicode input!\n";
binmode(STDOUT, ':encoding(UTF-8)') or 
  die "Failed to set Unicode output!\n";

# Check arguments
#
($#ARGV < 0) or die "Not expecting program arguments!\n";

# Processing loop
#
my $line_number = 0;
my %elements;

while (1) {
  # Attempt to read a line
  my $ltext = readline(STDIN);
  
  # Handle cases where we failed to read a line
  unless (defined($ltext)) {
    if (eof(STDIN)) {
      # We failed because we ran out of lines to read, so done
      last;
    } else {
      # We failed because of I/O error
      die "I/O error";
    }
  }
  
  # We got a line, so increase line number and drop line break
  $line_number++;
  chomp $ltext;
  
  # If this is first line, drop any byte order mark at start
  if ($line_number == 1) {
    $ltext =~ s/\A\x{feff}//;
  }
  
  # Skip line if blank
  if ($ltext =~ /\A\s*\z/) {
    next;
  }
  
  # We got a record line, so trim leading and trailing whitespace
  $ltext =~ s/\A\s+//;
  $ltext =~ s/\s+\z//;
  
  # Drop any final decimal integers
  $ltext =~ s/[0-9]+\z//;
  
  # We should have at least one character
  (length($ltext) > 0) or
    die sprintf("Line %d: Invalid tag!\n", $line_number);
  
  # Split into elements and record unique ones
  my @elist = split /\-/, $ltext;
  for my $e (@elist) {
    if ((defined $e) and (length($e) > 0)) {
      $elements{$e} = 1;
    }
  }
}

# Output unique elements
#
for my $key (sort keys %elements) {
  print "$key\n";
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
