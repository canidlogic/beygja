#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use Beygja::CSV;

# Core imports
use POSIX qw(floor);

=head1 NAME

beygja_csv_unique.pl - Get unique values within a specified CSV field.

=head1 SYNOPSIS

  ./beygja_csv_unique.pl data.csv 0 0 scalar 1024
  ./beygja_csv_unique.pl data.csv 0 5 array 1024

=head1 DESCRIPTION

Scan records in a Beygja-format CSV file and compile a list of all
unique values that are used within those fields.

The first parameter is the path to a CSV file to scan.  The
C<Beygja::CSV> parser will be used to read through it.

The second parameter is the number of lines to skip at the start of the
file (if there are header lines), or zero if there are no header lines.

The third parameter is the index of the CSV field to scan.  It must be
zero or greater, where index zero is the first field, index one is the
second field, and so forth.  An error occurs if any CSV record does not
have the requested field.

The fourth parameter is either C<scalar> or C<array>.  If it is
C<scalar> then the field is interpreted as a whole scalar value.  If it
is C<array> then the field is parsed with C<Beygja::CSV->array()> and
the individual array elements are counted as unique.

The fifth parameter is an integer greater than zero that specifies the
maximum number of unique elements before the script will fail.  The
script keeps all unique elements in memory, so there should be a limit
to how much it is allowed to load.

The process may take a long time.  Regular progress reports are issued
to standard error.  At the end, a report is printed to standard output.
The first line of the report indicates the path and the field index that
was examined, as well as whether a null or empty value was ever
encountered in the field.  After the first line, all the unique values
are listed in sorted order.

For arrays, a null or empty value encountered means that there was an
array of at least two elements where one of the elements was empty, as
determined by comma placement.  Empty arrays of no values do not count
as a null or empty value.

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

# Allow Unicode in standard output
#
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Get arguments
#
($#ARGV == 4) or die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

my $skip_count = shift @ARGV;
($skip_count =~ /\A[0-9]+\z/) or die "Invalid skip count!\n";
$skip_count = int($skip_count);

my $field_index = shift @ARGV;
($field_index =~ /\A[0-9]+\z/) or die "Invalid field index!\n";
$field_index = int($field_index);

my $field_type = shift @ARGV;
(($field_type eq 'scalar') or ($field_type eq 'array')) or
  die "Invalid field type, expecting 'scalar' or 'array'!\n";

my $record_limit = shift @ARGV;
($record_limit =~ /\A[0-9]+\z/) or die "Invalid record limit!\n";
$record_limit = int($record_limit);
($record_limit > 0) or die "Record limit must be at least one!\n";

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

# The null_flag will be set to 1 if any blank or empty records are
# encountered; the value_map contains the unique values, each mapped to
# 1; the value_count is the number of unique values that have been
# stored
#
my $null_flag = 0;
my %value_map;
my $value_count = 0;

# Go through all records and compile the report information
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
  (scalar(@$rec) > $field_index) or
    die sprintf("CSV line %d: Record has too few fields!\n",
          $csv->number);
  
  # Get the desired field from this record
  my $r_value = $rec->[$field_index];
  
  # Different handling depending on field type
  if ($field_type eq 'scalar') { # =====================================
    # Scalar value, so check if this is blank
    if (length($r_value) > 0) {
      # Non-blank value, so check if we need to add it
      unless (defined $value_map{$r_value}) {
        # We need to add it, so increment value_count, watching for the
        # limit
        ($value_count < $record_limit) or
          die "Limit on unique field values was exceeded!\n";
        $value_count++;
        
        # Add to the map
        $value_map{$r_value} = 1;
      }
      
    } else {
      # Blank value, so update the null_flag
      $null_flag = 1;
    }
    
  } elsif ($field_type eq 'array') { # =================================
    # Array value, so parse as array
    my @ivals;
    eval {
      @ivals = Beygja::CSV->array($r_value);
    };
    if ($@) {
      warn sprintf("CSV line %d array parsing:\n", $csv->number);
      die $@;
    }
    
    # Update statistics according to array elements
    for my $iv (@ivals) {
      # Different handling for null elements and non-null elements
      if (length($iv) > 0) {
        # Non-blank value, so check if we need to add it
        unless (defined $value_map{$iv}) {
          # We need to add it, so increment value_count, watching for
          # the limit
          ($value_count < $record_limit) or
            die "Limit on unique field values was exceeded!\n";
          $value_count++;
          
          # Add to the map
          $value_map{$iv} = 1;
        }
        
      } else {
        # Blank value, so update the null_flag
        $null_flag = 1;
      }
    }
    
  } else { # ===========================================================
    die;
  }
}

# Give the report
#
printf "CSV '%s' field index #%d", $path, $field_index;
if ($null_flag) {
  print " null values present, unique values:\n";
} else {
  print " null values absent, unique values:\n";
}

for my $key (sort keys %value_map) {
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
