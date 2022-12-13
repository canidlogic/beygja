#!/usr/bin/env perl
use v5.14;
use warnings;

# Use UTF-8 in string literals
use utf8;

# Beygja imports
use BeygjaConfig;
use Beygja::CSV;
use Beygja::DB;

# Core imports
use POSIX qw(floor);

=head1 NAME

beygja_words.pl - Import records from the Comprehensive Format word CSV
file into the Beygja database.

=head1 SYNOPSIS

  ./beygja_words.pl Storasnid_ord.csv 0

=head1 DESCRIPTION

Fill a Beygja database with word records from the Comprehensive Format.
The location of the database is determined by C<BeygjaConfig.pm>

The first parameter is the path to the CSV file in Comprehensive Format
for words.  The second parameter is the number of lines to skip at the
start of the file (if there are header lines), or zero if there are no
header lines.

The Beygja database must already have been constructed.  The tables
C<wclass>, C<dom>, C<grade>, C<reg>, and C<gflag> should be filled in.
Their contents will be loaded into memory by this script and if any
record in the CSV file is encountered that refers to records that are
missing from these auxiliary tables, the script will fail.

The C<word>, C<wdom>, C<wreg>, and C<wflag> tables must be empty when
this script runs.  They will be filled in by this script.

The process may take a long time.  Regular progress reports are issued.

=cut

# =========================
# Typo correction functions
# =========================

# correctGflag($gf)
# -----------------
#
# Given a grammar flag textual code, return either as-is or a corrected
# form.
#
sub correctGflag {
  # Get parameter
  ($#_ == 0) or die;
  my $val = shift;
  (not ref($val)) or die;
  
  # Perform corrections
  if ($val eq 'Í-I') {
    $val = 'I-Í';
  }
  
  # Return corrected value
  return $val;
}

# =========
# Constants
# =========

# The total number of progress checks that will be made while parsing
# through the file.  However, progress checks will only be printed if
# STATUS_INTERVAL seconds have elapsed since the last progress check.
#
use constant STATUS_COUNT => 1024;

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

# Mapping of word class abbreviated codes to the numeric keys used in
# the database.  This will be loaded from the database.
#
my $wclass_map = undef;

# Mapping of semantic domain abbreviated codes to the numeric keys used
# in the database.  This will be loaded from the database.
#
my $dom_map = undef;

# Array mapping DIM grade codes 0-5 to their numeric keys used in the
# database.  The array index is the DIM grade code.  This will be loaded
# from the database.  Values of undef are filled in if a given array
# index doesn't correspond to anything.
#
my $grade_array = undef;

# Mapping of language register abbreviated codes to the numeric keys
# used in the database.  This will be loaded from the database.
#
my $reg_map = undef;

# Mapping of grammatical flag abbreviated codes to the numeric keys used
# in the database.  This will be loaded from the database.
#
my $gflag_map = undef;

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

# wclassCache()
# -------------
#
# Cache the word class mapping from the database in wclass_map.
#
# Has no effect if wclass_map is already defined.
#
sub wclassCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $wclass_map)) or return;
  
  # Query the database and fill the cache
  $wclass_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT cid, ctx FROM wclass");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_tx = Beygja::DB->dbToString($rec->[1]);
      
      $wclass_map->{$val_tx} = $val_id;
    }
  }
}

# domCache()
# ----------
#
# Cache the semantic domain mapping from the database in dom_map.
#
# Has no effect if dom_map is already defined.
#
sub domCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $dom_map)) or return;
  
  # Query the database and fill the cache
  $dom_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT did, dtx FROM dom");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_tx = Beygja::DB->dbToString($rec->[1]);
      
      $dom_map->{$val_tx} = $val_id;
    }
  }
}

# gradeCache()
# ------------
#
# Cache the grade array from the database in grade_array.
#
# Has no effect if grade_array is already defined.
#
sub gradeCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $grade_array)) or return;
  
  # Query the database and fill the cache
  $grade_array = [];
  
  my $qr = $dbh->selectall_arrayref(
    "SELECT gid, giv FROM grade ORDER BY giv ASC");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_gr = int($rec->[1]);
      
      ($val_gr >= 0) or die "Negative DIM grade codes not allowed!\n";
      ($val_gr >= scalar(@$grade_array)) or
        die "Duplicate DIM grade codes!\n";
      ($val_gr <= 1024) or die "DIM grade code too high!\n";
      
      until (scalar(@$grade_array) == $val_gr) {
        push @$grade_array, (undef);
      }
      push @$grade_array, ($val_id);
    }
  }
}

# regCache()
# ----------
#
# Cache the language register mapping from the database in reg_map.
#
# Has no effect if reg_map is already defined.
#
sub regCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $reg_map)) or return;
  
  # Query the database and fill the cache
  $reg_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT rid, rtx FROM reg");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_tx = Beygja::DB->dbToString($rec->[1]);
      
      $reg_map->{$val_tx} = $val_id;
    }
  }
}

# gflagCache()
# ------------
#
# Cache the grammatical flag mapping from the database in gflag_map.
#
# Has no effect if gflag_map is already defined.
#
sub gflagCache {
  # Check parameters and state
  ($#_ < 0) or die;
  (defined $dbh) or die;
  
  # Ignore if already cached
  (not (defined $gflag_map)) or return;
  
  # Query the database and fill the cache
  $gflag_map = {};
  
  my $qr = $dbh->selectall_arrayref("SELECT fid, ftx FROM gflag");
  if (defined $qr) {
    for my $rec (@$qr) {
      my $val_id = int($rec->[0]);
      my $val_tx = Beygja::DB->dbToString($rec->[1]);
      
      $gflag_map->{$val_tx} = $val_id;
    }
  }
}

# isTableEmpty($table_name)
# -------------------------
#
# Given a table name, check whether the table is empty and contains no
# records.
#
sub isTableEmpty {
  # Get parameter
  ($#_ == 0) or die;
  my $table_name = shift;
  
  (not ref($table_name)) or die;
  ($table_name =~ /\A[A-Za-z_][A-Za-z_0-9]*\z/) or die;
  
  # Check state
  (defined $dbh) or die;
  
  # Check whether table is empty
  my $qr = $dbh->selectrow_arrayref("SELECT * FROM " . $table_name);
  if (defined($qr) and (scalar(@$qr) > 0)) {
    return 0;
  } else {
    return 1;
  }
}

# ==================
# Program entrypoint
# ==================

# Allow Unicode in error reports
#
binmode(STDERR, ":encoding(UTF-8)") or die;

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

# Perform a work block that will contain all operations
#
$dbh = $dbc->beginWork('rw');

# Make sure that the target tables are empty
#
isTableEmpty("word" ) or die "word table is not empty!\n";
isTableEmpty("wdom" ) or die "wdom table is not empty!\n";
isTableEmpty("wreg" ) or die "wreg table is not empty!\n";
isTableEmpty("wflag") or die "wflag table is not empty!\n";

# Cache mappings
#
statusMessage("Caching mappings...\n");

wclassCache();
   domCache();
 gradeCache();
   regCache();
 gflagCache();

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

# Word table is empty so first ID we will assign is 1
#
my $next_word_id = 1;

# Go through all records and add them to the database, giving status
# updates along the way because this is a long operation
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
  (scalar(@$rec) >= 13) or
    die sprintf("CSV line %d: Record has too few fields!\n",
          $csv->number);
  
  # Get the relevant fields from this record
  my $r_word   = $rec->[ 0];
  my $r_id     = $rec->[ 1];
  my $r_wclass = $rec->[ 2];
  my $r_cmpd   = $rec->[ 3];
  my $r_dom    = $rec->[ 4];
  my $r_grade  = $rec->[ 5];
  my $r_reg    = $rec->[ 6];
  my $r_gflags = $rec->[ 7];
  my $r_vis    = $rec->[ 8];
  my $r_syl    = $rec->[12];
  
  # Make sure ID is an unsigned decimal integer and convert to integer
  ($r_id =~ /\A[0-9]+\z/) or
    die sprintf("CSV line %d: Invalid ID field!\n", $csv->number);
  $r_id = int($r_id);
  
  # Make sure ID has not been defined yet
  my $qr = $dbh->selectrow_arrayref(
            "SELECT wid FROM word WHERE wbid=?", undef, $r_id);
  (not defined $qr) or
    die sprintf("CSV line %d: Duplicate ID field!\n", $csv->number);
  
  # Look up the word class and replace it with the numeric key
  (defined $wclass_map->{$r_wclass}) or
    die sprintf("CSV line %d: Unrecognized word class '%s'!\n",
                  $csv->number, $r_wclass);
  $r_wclass = $wclass_map->{$r_wclass};
  
  # Replace compound flag with 1 if compound, 0 if not
  if ($r_cmpd eq 'g') {
    $r_cmpd = 0;
  } elsif ($r_cmpd eq 's') {
    $r_cmpd = 1;
  } else {
    die sprintf("CSV line %d: Unrecognized word formation '%s'!\n",
                  $csv->number, $r_cmpd);
  }
  
  # Parse the semantic domains as an array
  my @doms;
  eval {
    @doms = Beygja::CSV->array($r_dom);
  };
  if ($@) {
    warn sprintf("CSV line %d domain field:\n", $csv->number);
    die $@;
  }
  
  # Look up each domain and replace with numeric key
  for my $dm (@doms) {
    (defined $dom_map->{$dm}) or
      die sprintf("CSV line %d: Unrecognized domain '%s' for '%s'!\n",
                    $csv->number, $dm, $r_word);
    $dm = $dom_map->{$dm};
  }
  
  # Make sure there are no duplicate domains
  for(my $i = 0; $i < $#doms; $i++) {
    for(my $j = $i + 1; $j <= $#doms; $j++) {
      ($doms[$i] != $doms[$j]) or
        die sprintf("CSV line %d: Duplicate domains!\n",
                      $csv->number);
    }
  }
  
  # Parse grade as unsigned decimal integer
  ($r_grade =~ /\A[0-9]+\z/) or
    die sprintf("CSV line %d: Invalid grade field!\n", $csv->number);
  $r_grade = int($r_grade);
  
  # Make sure grade is in range
  (($r_grade >= 0) and ($r_grade < scalar(@$grade_array))) or
    die sprintf("CSV line %d: Grade '%d' out range!\n",
                  $csv->number, $r_grade);
  
  # Replace grade with its database key
  $r_grade = $grade_array->[$r_grade];
  
  # Parse the registers as an array
  my @regs;
  eval {
    @regs = Beygja::CSV->array($r_reg);
  };
  if ($@) {
    warn sprintf("CSV line %d registers:\n", $csv->number);
    die $@;
  }
  
  # Look up each register and replace with numeric key
  for my $rg (@regs) {
    (defined $reg_map->{$rg}) or
      die sprintf("CSV line %d: Unrecognized register '%s'!\n",
                    $csv->number, $rg);
    $rg = $reg_map->{$rg};
  }
  
  # Make sure there are no duplicate registers
  for(my $i = 0; $i < $#regs; $i++) {
    for(my $j = $i + 1; $j <= $#regs; $j++) {
      ($regs[$i] != $regs[$j]) or
        die sprintf("CSV line %d: Duplicate registers!\n",
                      $csv->number);
    }
  }
  
  # Parse the grammar flags as an array
  my @gflags;
  eval {
    @gflags = Beygja::CSV->array($r_gflags);
  };
  if ($@) {
    warn sprintf("CSV line %d grammar flags:\n", $csv->number);
    die $@;
  }
  
  # Look up each grammar flag and replace with numeric key
  for my $gf (@gflags) {
    $gf = correctGflag($gf);
    (defined $gflag_map->{$gf}) or
      die sprintf(
        "CSV line %d: Unrecognized grammar flag '%s' for '%s'!\n",
          $csv->number, $gf, $r_word);
    $gf = $gflag_map->{$gf};
  }
  
  # Make sure there are no duplicate grammar flags
  for(my $i = 0; $i < $#gflags; $i++) {
    for(my $j = $i + 1; $j <= $#gflags; $j++) {
      ($gflags[$i] != $gflags[$j]) or
        die sprintf("CSV line %d: Duplicate grammar flags!\n",
                      $csv->number);
    }
  }
  
  # Convert visibility set to 0 core 1 extended 2 correcitons
  if ($r_vis eq 'K') {
    $r_vis = 0;
  } elsif ($r_vis eq 'V') {
    $r_vis = 1;
  } elsif ($r_vis eq 'L') {
    $r_vis = 2;
  } else {
    die sprintf("CSV line %d: Unrecognized visibility '%s'!\n",
                  $csv->number, $r_vis);
  }
  
  # Parse syllable count as unsigned decimal integer, or zero if it is
  # blank
  if ($r_syl eq '') {
    $r_syl = '0';
  }
  ($r_syl =~ /\A[0-9]+\z/) or
    die sprintf("CSV line %d: Invalid syllable count field!\n",
            $csv->number);
  $r_syl = int($r_syl);
  
  
  # Insert the main word record
  $dbh->do('INSERT INTO word (wid, wbid, wlem, cid, wcp, gid, wvs, wsy)'
            . ' VALUES (?,?,?,?,?,?,?,?)', undef,
            $next_word_id,
            $r_id,
            Beygja::DB->stringToDB($r_word),
            $r_wclass,
            $r_cmpd,
            $r_grade,
            $r_vis,
            $r_syl);
  
  # Add any semantic domain mappings
  for my $dm (@doms) {
    $dbh->do('INSERT INTO wdom (wid, did) VALUES (?,?)', undef,
              $next_word_id, $dm);
  }
  
  # Add any register mappings
  for my $rg (@regs) {
    $dbh->do('INSERT INTO wreg (wid, rid) VALUES (?,?)', undef,
              $next_word_id, $rg);
  }
  
  # Add any grammatical flag mappings
  for my $gf (@gflags) {
    $dbh->do('INSERT INTO wflag (wid, fid) VALUES (?,?)', undef,
              $next_word_id, $gf);
  }
  
  # Increase the next word ID counter
  $next_word_id++;
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
