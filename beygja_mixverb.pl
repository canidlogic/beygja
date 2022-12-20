#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;

# Non-core imports
use Shastina::Const qw(:CONSTANTS snerror_str);
use Shastina::InputSource;
use Shastina::Parser;

=head1 NAME

beygja_mixverb.pl - Import mixed verb inflection records from the Beygja
mixed verbs script.

=head1 SYNOPSIS

  ./beygja_mixverb.pl < data/mixed_verbs.script

=head1 DESCRIPTION

Fill the Beygja verb database with mixed verb records from the mixed
verbs script included in the C<data> directory.  The location of the
verb database is determined by C<BeygjaConfig.pm>

The Beygja verb database must already have been constructed.  The table
C<mixverb> must be empty when this script is run.  This script will read
the C<mixed_verbs.script> file from standard input and use it to add all
the records to the C<mixverb> table.

=cut

# ==========
# Local data
# ==========

# Will be filled in with a read-write database handle to use during the
# start of the program.
#
my $dbh = undef;

# ===============
# Local functions
# ===============

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

# Check arguments
#
($#ARGV < 0) or die "Wrong number of program arguments!\n";

# Connect to verb database using the configured path
#
my $dbc = Beygja::DB->connect(beygja_dbpath('verb'), 0);

# Perform a work block that will contain all operations
#
$dbh = $dbc->beginWork('rw');

# Make sure that the target table is empty
#
isTableEmpty("mixverb" ) or die "mixverb table is not empty!\n";

# Wrap standard input as a Shastina input source
#
my $src = Shastina::InputSource->load;
(defined $src) or die "Failed to load input as Shastina source!\n";

# Build a Shastina parser around the input source
#
my $sr = Shastina::Parser->parse($src);
my $ent;

# Read the three header entities
#
for(my $i = 0; $i < 3; $i++) {
  # Read an entity
  $ent = $sr->readEntity;
  (ref($ent)) or die "Failed to read valid script header!\n";
  
  # Check the entity
  if ($i == 0) {
    # First entity must be BEGIN_META
    ($ent->[0] == SNENTITY_BEGIN_META) or
      die "Failed to read valid script header!\n";
    
  } elsif ($i == 1) {
    # Second entity must be proper meta token
    ($ent->[0] == SNENTITY_META_TOKEN) or
      die "Failed to read valid script header!\n";
    ($ent->[1] eq 'beygja-mixed-verbs') or
      die "Failed to read valid script header!\n";
    
  } elsif ($i == 2) {
    # Third entity must be END_META
    ($ent->[0] == SNENTITY_END_META) or
      die "Failed to read valid script header!\n";
    
  } else {
    die;
  }
}

# Interpreter stack begins empty
#
my @stack;

# Interpret rest of tokens in script
#
for($ent = $sr->readEntity; ref($ent); $ent = $sr->readEntity) {
  # First array element is the entity type
  my $etype = $ent->[0];
  
  # Determine line number, or -1 if not defined
  my $lnum = (defined $sr->count) ? $sr->count : -1;
  
  # Handle the different entities
  if ($etype == SNENTITY_STRING) { # ===================================
    # Get string parameters
    my $prefix = $ent->[1];
    my $stype  = $ent->[2];
    my $sdata  = $ent->[3];
    
    # Check that no prefix, type is quoted, and no backslash in data
    ($prefix eq '') or
      die sprintf("Line %d: String prefixes not supported!\n", $lnum);
    
    ($stype eq SNSTRING_QUOTED) or
      die sprintf("Line %d: Curly strings not supported!\n", $lnum);
    
    (not ($sdata =~ /\\/)) or
      die sprintf("Line %d: Backslash not allowed in string data!\n",
                    $lnum);
    
    # Push the string onto the stack
    push @stack, ($sdata);
  
  } elsif ($etype == SNENTITY_OPERATION) { # ===========================
    # Get operation name
    my $opname = $ent->[1];
    
    # Check that operation name is supported and figure out whether the
    # optional flag will be set
    my $is_opt;
    if ($opname eq 'mv') {
      $is_opt = 0;
    } elsif ($opname eq 'mva') {
      $is_opt = 0;
    } elsif ($opname eq 'mvo') {
      $is_opt = 1;
    } elsif ($opname eq 'mve') {
      $is_opt = 0;
    } else {
      die sprintf("Line %d: Unrecognized operator '%s'!\n",
                  $lnum, $opname);
    }
    
    # All of the operations take two parameters, so make sure we have
    # two entries on stake
    (scalar(@stack) >= 2) or
      die sprintf("Line %d: Stack underflow on '%s'!\n",
                  $lnum, $opname);
    
    # Get the parameters from the stack
    my $p_pres = pop @stack;
    my $p_inf  = pop @stack;
    
    # Check parameters
    ($p_pres =~ /\A[a-záéíóúýðþæö]+\z/) or
      die sprintf("Line %d: Invalid present form '%s'!\n",
                  $lnum, $p_pres);
    ($p_inf =~ /\A[a-záéíóúýðþæö]+\z/) or
      die sprintf("Line %d: Invalid infinitive form '%s'!\n",
                  $lnum, $p_inf);
    
    # Insert into database
    $dbh->do(
      'INSERT INTO mixverb(mixverb_inf, mixverb_pres, mixverb_opt) '
      . 'VALUES (?,?,?)', undef,
      Beygja::DB->stringToDB($p_inf),
      Beygja::DB->stringToDB($p_pres),
      $is_opt);
  
  } else { # ===========================================================
    die sprintf("Line %d: Unsupported Shastina entity!\n", $lnum);
  }
}

# Check that interpreter stack is empty
#
($#stack < 0) or
  die "Interpreter stack must be empty at end of script!\n";

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
