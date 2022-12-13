#!/usr/bin/env perl
use v5.14;
use warnings;

# Beygja imports
use BeygjaConfig;
use Beygja::CSV;
use Beygja::DB;

# Core imports
use POSIX qw(floor);

=head1 NAME

beygja_extra_itags.pl - Find missing inflectional tags.

=head1 SYNOPSIS

  ./beygja_extra_itags.pl Storasnid_beygm.csv 0

=head1 DESCRIPTION

Scan records from the Comprehensive Format inflections CSV file and
report all inflectional tags that are present in the CSV but not in the
database.

The location of the database is determined by C<BeygjaConfig.pm>

The first parameter is the path to the CSV file in Comprehensive Format
for inflectional forms.  The second parameter is the number of lines to
skip at the start of the file (if there are header lines), or zero if
there are no header lines.

The Beygja database must already have been constructed.  The tables
C<wclass> and C<itag> should be filled in.  Their contents will be
loaded into memory by this script.  Missing word classes will cause the
script to fail, but the script will store a list of all missing
inflectional tags and report them at the end.

The C<word> table should also be filled in already.  If any inflected
forms refer to words that have no record in the C<word> table, the
script will fail.

The process may take a long time.  Regular progress reports are issued.
A summary of all missing tags that were found is printed to standard
output at the end.

=cut

# =========
# Constants
# =========

# The total number of progress checks that will be made while parsing
# through the file.  However, progress checks will only be printed if
# STATUS_INTERVAL seconds have elapsed since the last progress check.
#
use constant STATUS_COUNT => 8192;

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

# Will be filled in with a read-write database handle to use during the
# start of the program.
#
my $dbh = undef;

# Reverse mapping of numeric word class keys to their abbreviated codes.
# This will be loaded from the database.
#
my $rwclass_map = undef;

# Mapping of word class + inflection tag abbreviated codes to the
# numeric keys used in the database.  Since the inflection tags are only
# unique within the word class, the numeric key for the word class as a
# decimal integer is prefixed to the tag, followed by a comma, then the
# inflection tag.  This will be loaded from the database.
#
my $itag_map = undef;

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

# rwclassCache()
# --------------
#
# Cache the reverse word class mapping from the database in rwclass_map.
#
# Has no effect if rwclass_map is already defined.
#
sub rwclassCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $rwclass_map)) or return;
  
  # Query the database and fill the cache
  $rwclass_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT cid, ctx FROM wclass");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_tx = Beygja::DB->dbToString($rec->[1]);
      
      $rwclass_map->{$val_id} = $val_tx;
    }
  }
}

# itagCache()
# -----------
#
# Cache the inflection tag mapping from the database in itag_map.
#
# Has no effect if itag_map is already defined.
#
sub itagCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $itag_map)) or return;
  
  # Query the database and fill the cache
  $itag_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT mid, cid, mtx FROM itag");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_wc = int($rec->[1]);
      my $val_tx = Beygja::DB->dbToString($rec->[2]);
      
      my $key = sprintf("%d,%s", $val_wc, $val_tx);
      
      $itag_map->{$key} = $val_id;
    }
  }
}

# ==================
# Program entrypoint
# ==================

# Allow Unicode in error reports and standard output
#
binmode(STDERR, ":encoding(UTF-8)") or die;
binmode(STDOUT, ":encoding(UTF-8)") or die;

# Get arguments
#
($#ARGV == 1) or die "Wrong number of program arguments!\n";

my $path = shift @ARGV;
(-f $path) or die "Can't find file '$path'!\n";

my $skip_count = shift @ARGV;
($skip_count =~ /\A[0-9]+\z/) or die "Invalid skip count!\n";
$skip_count = int($skip_count);

# Connect to database using the configured path
#
my $dbc = Beygja::DB->connect(CONFIG_DBPATH, 0);

# Perform a read-only work block that will contain all operations
#
$dbh = $dbc->beginWork('r');

# Cache mappings
#
statusMessage("Caching mappings...\n");

rwclassCache();
   itagCache();

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

# Based on STATUS_COUNT, figure out after how many lines we need to
# perform a possible status update, and start countdown at that value
#
my $countdown_total = floor($csv->count / STATUS_COUNT);
unless ($countdown_total > 0) {
  $countdown_total = 1;
}
my $countdown = $countdown_total;

# Skip lines at the beginning and update statistics
#
$csv->skip($skip_count);
$lines_read += $skip_count;

# The missing tags set starts out empty; each missing tag will have a
# key that is the composite key and a value that is one
#
my %missing;

# Go through all records and look for missing inflectional tags, giving
# status updates along the way because this is a long operation
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
  (scalar(@$rec) >= 5) or
    die sprintf("CSV line %d: Record has too few fields!\n",
          $csv->number);
  
  # Get the relevant fields from this record
  my $r_id    = $rec->[ 1];
  my $r_infl  = $rec->[ 3];
  my $r_itag  = $rec->[ 4];
  
  # Make sure ID is an unsigned decimal integer and convert to integer
  ($r_id =~ /\A[0-9]+\z/) or
    die sprintf("CSV line %d: Invalid ID field!\n", $csv->number);
  $r_id = int($r_id);
  
  # Look up the word record and figure out the numeric word class and
  # the numeric key for the word
  my $qr = $dbh->selectrow_arrayref(
              "SELECT wid, cid FROM word WHERE wbid=?", undef,
              $r_id);
  (defined $qr) or
    die sprintf("CSV line %d: Can't find matching word '%d'\n",
                  $csv->number, $r_id);
  
  my $w_id = $qr->[0];
  my $w_wc = $qr->[1];
  
  # Use the numeric word class together with the inflection tag to look
  # up the inflection tag numeric key; if it is not present, then we may
  # have to add it to the map
  my $itag_key = sprintf("%d,%s", $w_wc, $r_itag);
  unless (defined $itag_map->{$itag_key}) {
    # We have a missing tag -- only do something if not yet recorded
    unless (defined $missing{$itag_key}) {
      # Brand-new tag, so add it
      $missing{$itag_key} = 1;
      
      # Report its occurrence
      warn sprintf("Found: '%s' for word '%d'\n", $itag_key, $w_id);
    }
  }
}

# If we got here, finish the work block successfully
#
$dbc->finishWork;

# Now go through the missing list and report in order
#
print "Missing tags that were found:\n";
for my $k (sort keys %missing) {
  # Parse key
  ($k =~ /\A([0-9]+),(.*)\z/) or die;
  my $wc_id = $1;
  my $tag_name = $2;
  
  (defined $rwclass_map->{$wc_id}) or die;
  my $wclass = $rwclass_map->{$wc_id};
  printf "%s %s\n", $wclass, $tag_name;
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
