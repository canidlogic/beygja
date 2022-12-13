#!/usr/bin/env perl
use v5.14;
use warnings;

# Beygja imports
use Beygja::CSV;

# Core imports
use POSIX qw(floor);

=head1 NAME

beygja_iclass.pl - Generate subrange for inflections of a specific word
class.

=head1 SYNOPSIS

  ./beygja_iclass.pl data.csv 0 so > subrange.txt

=head1 DESCRIPTION

Scan records in a Beygja-format CSV file and compile a subrange that
only includes words of a specified word class.

The first parameter is the path to a CSV file to scan.  The
C<Beygja::CSV> parser will be used to read through it.  This script will
work on any CSV where the word class textual code is stored in the third
field.

The second parameter is the number of lines to skip at the start of the
file (if there are header lines), or zero if there are no header lines.

The third parameter is the word class abbreviated textual code, which
must be a sequence of one to eight lowercase US-ASCII letters.

The generated subrange will be in a format that can be fed into the
C<sublines.pl> script to generate another file containing only records
with the matching word class.

The process may take a long time.  Regular progress reports are issued
to standard error.

=cut

# =========
# Constants
# =========

# The total number of progress checks that will be made while parsing
# through the file.  However, progress checks will only be printed if
# STATUS_INTERVAL seconds have elapsed since the last progress check.
#
use constant STATUS_COUNT => 8192;

# The minimum number of records that need to be processed between
# progress checks.
#
use constant STATUS_FLOOR => 100;

# The number of seconds that must pass between progress checks.
#
use constant STATUS_INTERVAL => 5;

# ==========
# Local data
# ==========

# The last time at which a progress report was given, as determined by
# the time() function.
#
my $check_time = undef;

# The total number of lines in the CSV file.
#
my $total_lines = undef;

# The number of lines that have been read from the CSV file.
#
my $lines_read = 0;

# ===============
# Local functions
# ===============

# statusMessage($msg)
# ------------------
#
# Print the given $msg to standard error as a status update.
#
# The message may only use US-ASCII codepoints.
#
sub statusMessage {
  # Get parameter
  ($#_ == 0) or die;
  my $msg = shift;
  (not ref($msg)) or die;
  
  # Check parameter
  ($msg =~ /\A[\x{00}-\x{7f}]*\z/) or die;
  
  # Print message
  print { \*STDERR } "$msg";
}

# statusUpdate()
# --------------
#
# Give a status update if enough time has passed since the last update.
#
# $check_time, $total_lines, and $lines_read must all be defined.  The
# $check_time will be updated to the current time if a message is
# printed.  STATUS_INTERVAL determines the number of seconds that must
# elapse between status updates.
#
sub statusUpdate {
  # Check parameters
  ($#_ < 0) or die;
  
  # Check state
  ((defined $check_time) and (defined $total_lines) and
    (defined $lines_read)) or die;
  
  # Ignore if not enough time has passed
  my $current_time = time;
  unless ($current_time - $check_time >= STATUS_INTERVAL) {
    return;
  }
  
  # We are giving an update, so update the check time
  $check_time = $current_time;
  
  # Get tl as the minimum of total_lines and 1
  my $tl = int($total_lines);
  unless ($tl >= 1) {
    $tl = 1;
  }
  
  # Get lr as lines_read, clamped to [0, tl]
  my $lr = int($lines_read);
  unless ($lr >= 0) {
    $lr = 0;
  }
  unless ($lr <= $tl) {
    $lr = $tl;
  }
  
  # Get the progress in 1/10ths of a percent, rounded down, and clamped
  # to range [0, 1000]
  my $progress = floor(($lr / $tl) * 1000.0);
  unless ($progress >= 0) {
    $progress = 0;
  }
  unless ($progress <= 1000) {
    $progress = 1000;
  }
  
  # Convert progress into percent and also get the fractional digit
  my $progress_f = $progress % 10;
  $progress = floor($progress / 10);
  
  # Write progress
  statusMessage(
    sprintf("Progress: %3u.%u%% (line %u / %u)\n",
      $progress,
      $progress_f,
      $lr,
      $tl)
  );
}

# ==================
# Program entrypoint
# ==================

# Get arguments
#
($#ARGV == 2) or die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

my $skip_count = shift @ARGV;
($skip_count =~ /\A[0-9]+\z/) or die "Invalid skip count!\n";
$skip_count = int($skip_count);

my $wclass = shift @ARGV;
($wclass =~ /\A[a-z]{1,8}\z/) or die "Invalid word class code!\n";

# Open the CSV file
#
my $csv = Beygja::CSV->load($path);

# Scan to get the total line count
#
statusMessage("Scanning CSV file...\n");
$csv->scan;
statusMessage(sprintf("Total lines: %d\n", $csv->count));

# Initialize progress information
#
$check_time  = time;
$total_lines = $csv->count;
$lines_read  = 0;

# Based on STATUS_COUNT and STATUS_FLOOR, figure out after how many
# lines we need to perform a possible status update, and start countdown
# at that value
#
my $countdown_total = floor($csv->count / STATUS_COUNT);
unless ($countdown_total >= STATUS_FLOOR) {
  $countdown_total = STATUS_FLOOR;
}
my $countdown = $countdown_total;

# Skip lines at the beginning and update statistics
#
$csv->skip($skip_count);
$lines_read += $skip_count;

# The start_line, if defined, is the first line in the current subrange;
# if undefined, it means there is not a current subrange
#
my $start_line = undef;

# Go through all records and compile the subrange
#
for(my $rec = $csv->readRecord; defined $rec; $rec = $csv->readRecord) {
  # We read a line, so update statistics
  $lines_read++;
  
  # Decrement countdown; if countdown reaches zero then reset it and
  # call statusUpdate() to possibly give a status report
  $countdown--;
  unless ($countdown > 0) {
    $countdown = $countdown_total;
    statusUpdate();
  }
  
  # Make sure the record has enough fields
  (scalar(@$rec) >= 3) or
    die sprintf("CSV line %d: Record has too few fields!\n",
          $csv->number);
  
  # Check whether this is a matching record
  if ($rec->[2] eq $wclass) {
    # This is a matching record -- if no current subrange is open, then
    # open it
    unless (defined $start_line) {
      $start_line = $csv->number;
    }
    
  } else {
    # This is not a matching record -- if a current subrange is open,
    # then close it, and don't include the current line
    if (defined $start_line) {
      printf("%d %d\n",
        $start_line,
        $csv->number - $start_line);
      $start_line = undef;
    }
  }
}

# If a subrange is still open, output the last subrange
#
if (defined $start_line) {
  printf("%d %d\n",
      $start_line,
      $csv->count - $start_line);
  $start_line = undef;
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
