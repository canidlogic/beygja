#!/usr/bin/env perl
use v5.14;
use warnings;

=head1 NAME

echolines.pl - Echo a subset of lines from a text file.

=head1 SYNOPSIS

  ./echolines.pl text.file 5
  ./echolines.pl text.file 1024 16

=head1 DESCRIPTION

Opens a text file at the path given in the first parameter.  The text
file must be UTF-8, with either LF or CR+LF line breaks.  Byte Order
Mark (BOM) is optional at the start of the first line, and skipped if it
is present.

After the text file is opened, this script skips to the line number
given as the second parameter.  Line 1 is the first line, so the second
parameter must be one or greater.  If the given line is not in range of
the text file, an error occurs.

Starting at the line given in the second parameter, this script outputs
either just that line (if no third parameter is given), or the number of
lines given in the third parameter if there is a third parameter.  The
third parameter must be one or greater.  At least one line will be
output, but less than the requested number may be output if the file
runs out of lines.

This script is useful for examining gigantic text files that are too
large open in a text editor.

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
(($#ARGV == 1) or ($#ARGV == 2)) or
  die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

my $start = shift @ARGV;
($start =~ /\A[0-9]+\z/) or die "Invalid line number '$start'!\n";
$start = int($start);
($start <= MAX_INTEGER) or die "Line number out of integer range!\n";
($start >= 1) or die "Line number must be at least one!\n";

my $count = 1;
if ($#ARGV >= 0) {
  $count = shift @ARGV;
  ($count =~ /\A[0-9]+\z/) or die "Invalid line count '$count'!\n";
  $count = int($count);
  ($count <= MAX_INTEGER) or die "Line count out of integer range!\n";
  ($count >= 1) or die "Line count must be at least one!\n";
}

# Open the file
#
open(my $fh, "< :encoding(UTF-8) :crlf", $path) or
  die "Failed to open '$path' for reading, stopped";
(defined $fh) or
  die "Failed to open '$path' for reading, stopped";

# Keep reading lines until we are at the requested line number
#
for(my $i = 1; $i < $start; $i++) {
  # Attempt to read a line
  my $ltext = readline($fh);
  
  # Handle cases where we failed to read a line
  unless (defined($ltext)) {
    if (eof($fh)) {
      # We failed because we ran out of lines to read
      die sprintf("Text file has only %d line(s)!\n", $i);
    } else {
      # We failed because of I/O error
      die "I/O error";
    }
  }
}

# Output the lines
#
for(my $i = 0; $i < $count; $i++) {
  # Attempt to read a line
  my $ltext = readline($fh);
  
  # Handle cases where we failed to read a line
  unless (defined($ltext)) {
    if (eof($fh)) {
      # We failed because we ran out of lines to read, so just write a
      # blank line and quit
      print "\n";
      return;
    } else {
      # We failed because of I/O error
      die "I/O error";
    }
  }
  
  # We got a line, so drop line break
  chomp $ltext;
  
  # If this is the very first line in the file, drop any BOM
  if (($i == 0) and ($start == 1)) {
    $ltext =~ s/\A\x{feff}//;
  }
  
  # Print the line
  print "$ltext\n";
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
