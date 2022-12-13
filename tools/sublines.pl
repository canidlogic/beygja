#!/usr/bin/env perl
use v5.14;
use warnings;

=head1 NAME

sublines.pl - Derive a text file from a subset of lines from another.

=head1 SYNOPSIS

  ./sublines.pl source.txt < subset.txt > target.txt

=head1 DESCRIPTION

The parameter is the path to an existing text file in UTF-8 format with
either LF or CR+LF line breaks.  On standard input, the script reads a
sequence of instructions indicating which lines of the input file to
output.  On standard output, the selected subset of lines of the source
file is written.

The subset file read on standard input has one instruction per line,
with blank lines consisting just of tabs and whitespaces ignored.  The
instruction format is like this:

  542 16

The first decimal integer is the line number at which a range begins,
while the second decimal integer is the number of lines in that range.
At least one tab or space character must separate the two decimal
integers.  The first line in the source file is line 1.

Ranges must be ordered such that each range begins with a higher line
number than the previous, and there is no overlap between ranges.

=cut

# =========
# Constants
# =========

# The maximum integer value that can be safely represented by double
# precision floating point.
#
use constant MAX_INTEGER => 9007199254740991;

# ==================
# Program entrypoint
# ==================

# Set output to UTF-8
#
binmode(STDOUT, ':encoding(UTF-8)') or 
  die "Failed to set Unicode output!\n";

# Get arguments
#
($#ARGV == 0) or die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

# Open the file
#
open(my $fh, "< :encoding(UTF-8) :crlf", $path) or
  die "Failed to open '$path' for reading, stopped";
(defined $fh) or
  die "Failed to open '$path' for reading, stopped";

# line_ptr is the number of the next line we are about to read from the
# source file, where line 1 is the first line
#
my $line_ptr = 1;

# Processing loop
#
while (1) {
  # Attempt to read a line from standard input
  my $itext = readline(STDIN);
  
  # Handle cases where we failed to read a line
  unless (defined $itext) {
    if (eof(STDIN)) {
      # We failed to read line because we are at end of file, so leave
      # the loop
      last;
    } else {
      # We failed because of I/O error
      die "I/O error";
    }
  }
  
  # If we read a blank line, skip it
  if ($itext =~ /\A\s*\z/) {
    next;
  }
  
  # Non-blank line, so drop line break parse as instruction
  chomp $itext;
  ($itext =~ /\A\s*([0-9]+)\s+([0-9]+)\s*\z/) or
    die "Invalid instruction";
  
  my $start = int($1);
  my $count = int($2);
  
  ($start <= MAX_INTEGER) or die "Line number out of integer range!\n";
  ($count <= MAX_INTEGER) or die "Count out of integer range!\n";
  
  ($start > 0) or die "Line number must be greater than zero!\n";
  ($count > 0) or die "Count must be greater than zero!\n";
  
  ($start >= $line_ptr) or die "Overlapping line ranges!\n";

  # Keep skipping lines until we are at the requested line number
  while($line_ptr < $start) {
    # Attempt to read a line
    my $ltext = readline($fh);
    
    # Handle cases where we failed to read a line
    unless (defined($ltext)) {
      if (eof($fh)) {
        # We failed because we ran out of lines to read
        die "Source file doesn't have enough lines!\n";
      } else {
        # We failed because of I/O error
        die "I/O error";
      }
    }
    
    # Increment the line pointer
    $line_ptr++;
  }

  # Copy the requested number of lines to standard output
  for(my $i = 0; $i < $count; $i++) {
    # Attempt to read a line
    my $ltext = readline($fh);
    
    # Handle cases where we failed to read a line
    unless (defined($ltext)) {
      if (eof($fh)) {
        # We failed because we ran out of lines to read
        die "Source file doesn't have enough lines!\n";
      } else {
        # We failed because of I/O error
        die "I/O error";
      }
    }
    
    # We got a line, so drop line break and increment line pointer
    chomp $ltext;
    $line_ptr++;
    
    # Print the line
    print "$ltext\n";
  }
}

# Close the file
#
close($fh) or warn "Failed to close file.\n";

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
