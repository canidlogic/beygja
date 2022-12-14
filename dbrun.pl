#!/usr/bin/env perl
use v5.14;
use warnings;
use utf8;

# Beygja imports
use BeygjaConfig qw(beygja_dbpath);
use Beygja::DB;

# Non-core imports
use File::Slurp;
use Shastina::Const qw(:CONSTANTS snerror_str);
use Shastina::InputSource;
use Shastina::Parser;

=head1 NAME

dbrun.pl - Run a database generation script to generate and populate a
Beygja database.

=head1 SYNOPSIS

  ./dbrun.pl verb < db.script

=head1 DESCRIPTION

Creates a brand-new Beygja database and runs the given Shastina script
given on standard input to structure the database and populate it with
initial values.

As an argument, you must pass which database type you want to build.
Currently, only C<verb> is supported.  This type will be used to select
the path of the database file as well as affecting the interpretation of
conditionals within the database script.

The location of the database is determined by the C<BeygjaConfig.pm>
module that this script imports.  The database must not already exist or
this script will fail.

See C<TemplateDB.script> for the structure of the database script.

=cut

# ============================
# High-level interpreter state
# ============================

# Before interpretation begins, this will be filled in with a database
# handle on a read-write transaction that will be used for database
# operations
#
my $dbh = undef;

# Each "(c)table" op fills this in with the name of a table
#
my $table_name = undef;

# Each "(c)table" op fills in the table_suppress flag, which will be 1
# if all database commands for this table should be suppressed, and zero
# otherwise; table always sets this to zero, while ctable uses
# conditionals to figure out its setting
#
my $table_suppress = undef;

# Mapping of record field indices to column names, as established by the
# "column" ops; will be reset each time the table_name changes; when
# defined, it is an array reference
#
my $field_names = undef;

# ===============
# Local functions
# ===============

# addRecord($lnum, @fields)
# -------------------------
#
# Add a record with the given fields to the currently open table using
# the currently opened field mapping.
#
# At least one field must be passed and at most the number of fields
# currently registered with @$field_names.
#
# $lnum is the line number, for error reporting purposes.
#
# If table_suppress is set, then this function will silently ignore the
# request and not modify the database.
#
sub addRecord {
  # Check parameter count
  ($#_ >= 1) or die;
  
  # Get line number
  my $lnum = shift;
  (not ref($lnum)) or die;
  
  # Check remaining parameters are all scalar and convert to binary
  # UTF-8
  for my $arg (@_) {
    (not ref($arg)) or die;
    $arg = Beygja::DB->stringToDB($arg);
  }
  
  # Check state is defined
  (defined $dbh) or die;
  (defined $table_name) or
    die sprintf("Line %d: Table must be open for records!\n", $lnum);
  (defined $table_suppress) or die;
  (defined $field_names) or die;
  
  # If output is suppressed, skip the rest of this procedure
  if ($table_suppress) {
    return;
  }
  
  # Check we have enough field names
  (scalar(@_) <= scalar(@$field_names)) or
    die sprintf("Line %d: Not enough columns defined!\n", $lnum);
  
  # Build the outline of the insert, except for the values
  my $sql = "INSERT INTO " . $table_name . " (";
  for(my $i = 0; $i < scalar(@_); $i++) {
    if ($i > 0) {
      $sql = $sql . ", ";
    }
    $sql = $sql . $field_names->[$i];
  }
  $sql = $sql . ") VALUES (";
  for(my $i = 0; $i < scalar(@_); $i++) {
    if ($i > 0) {
      $sql = $sql . ", ";
    }
    $sql = $sql . '?';
  }
  $sql = $sql . ")";
  
  # Perform the insertion
  $dbh->do($sql, undef, @_);
}

# sqlScript($path)
# ----------------
#
# Run the SQL script at the given path.
#
sub sqlScript {
  # Get parameter
  ($#_ == 0) or die;
  
  my $spath = shift;
  (not ref($spath)) or die;
  
  (-f $spath) or die "Can't find SQL script '$spath'!\n";
  
  # Make sure database handle is there
  (defined $dbh) or die;
  
  # Read the whole SQL script into memory as a sequence of lines
  my @lines = read_file($spath, binmode => ':encoding(UTF-8) :crlf');
  
  # Drop comments and line breaks
  for my $ltx (@lines) {
    chomp $ltx;
    $ltx =~ s/\-\-.*\z//;
  }
  
  # Join everything into a single string now that comments are gone
  my $sql = join "\n", @lines;
  
  # Make sure at least one semicolon
  ($sql =~ /;/) or die "SQL script '$spath' has no semicolons!\n";
  
  # Make sure nothing but whitespace after last semicolon
  ($sql =~ /;[ \t\n]*\z/)
    or die "SQL script '$spath' has content after last semicolon!\n";
  
  # Drop the last semicolon and everything that follows
  $sql =~ s/;[^;]*\z//;
  
  # Split into SQL statements with semicolon separators
  my @sqls = split /;/, $sql;
  
  # Run each SQL statement
  my $si = 1;
  for my $s (@sqls) {
    eval {
      $s = Beygja::DB->stringToDB($s);
      $dbh->do($s);
    };
    if ($@) {
      warn "SQL failure in '$spath' statement #$si!\n";
      die $@;
    }
    $si++;
  }
}

# popString(\@stack, $lnum)
# -------------------------
#
# Pop a string off the top of the given stack and return it.  Error if
# no string on top of stack.
#
# lnum is the line number, used only for error reporting.
#
sub popString {
  # Get parameters
  ($#_ == 1) or die;
  
  my $st = shift;
  (ref($st) eq 'ARRAY') or die;
  
  my $lnum = shift;
  (not ref($lnum)) or die;
  
  # Check that stack not empty
  (scalar(@$st) > 0) or
    die sprintf("Line %d: Interpreter stack underflow!\n", $lnum);
  
  # Get top of stack
  my $val = pop @$st;
  
  # Check that we have a string (which is a direct scalar on the stack)
  (not ref($val)) or
    die sprintf("Line %d: Expecting string on stack!\n", $lnum);
  
  # Return the value
  return $val;
}

# popInteger(\@stack, $lnum)
# --------------------------
#
# Pop an integer off the top of the given stack and return it.  Error if
# no integer on top of stack.
#
# lnum is the line number, used only for error reporting.
#
sub popInteger {
  # Get parameters
  ($#_ == 1) or die;
  
  my $st = shift;
  (ref($st) eq 'ARRAY') or die;
  
  my $lnum = shift;
  (not ref($lnum)) or die;
  
  # Check that stack not empty
  (scalar(@$st) > 0) or
    die sprintf("Line %d: Interpreter stack underflow!\n", $lnum);
  
  # Get top of stack
  my $val = pop @$st;
  
  # Check that we have an integer (encoded as array ref on stack)
  (ref($val) eq 'ARRAY') or
    die sprintf("Line %d: Expecting integer on stack!\n", $lnum);
  
  # Unpack the wrapped integer
  $val = int($val->[0]);
  
  # Return the value
  return $val;
}

# ==================
# Program entrypoint
# ==================

# Get arguments
#
($#ARGV == 0) or die "Wrong number of program arguments!\n";

my $dbtype = shift @ARGV;
($dbtype eq 'verb') or
  die "Unsupported database type '$dbtype'!\n";

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
    ($ent->[1] eq 'beygja-db') or
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

# Connect to database using the configured path
#
my $dbc = Beygja::DB->connect(beygja_dbpath($dbtype), 1);

# Perform a work block that will contain all operations
#
$dbh = $dbc->beginWork('rw');

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
    
  } elsif ($etype == SNENTITY_NUMERIC) { # =============================
    # Get numeric string
    my $str = $ent->[1];
    
    # Make sure we have unsigned decimal integer
    ($str =~ /\A[0-9]+\z/) or
      die sprintf("Line %d: Invalid numeric literal!\n", $lnum);
    
    # Push the integer value on the stack wrapped in array reference
    push @stack, ([ int($str) ]);
    
  } elsif ($etype == SNENTITY_OPERATION) { # ===========================
    # Get operation name
    my $opname = $ent->[1];
    
    # Dispatch to operation after getting parameters
    if ($opname eq 'sql') {
      my $spath = popString(\@stack, $lnum);
    
      sqlScript($spath);
      
    } elsif ($opname eq 'csql') {
      my $ctype = popString(\@stack, $lnum);
      my $spath = popString(\@stack, $lnum);
      
      if ($ctype eq $dbtype) {
        sqlScript($spath);
      }
    
    } elsif ($opname eq 'table') {
      my $tname = popString(\@stack, $lnum);
      
      ($tname =~ /\A[A-Za-z_][A-Za-z_0-9]*\z/) or
        die sprintf("Line %d: Invalid table name '%s'!\n",
                    $lnum, $tname);
      
      $table_name     = $tname;
      $table_suppress = 0;
      $field_names    = [];
      
    } elsif ($opname eq 'ctable') {
      my $ctype = popString(\@stack, $lnum);
      my $tname = popString(\@stack, $lnum);
      
      ($tname =~ /\A[A-Za-z_][A-Za-z_0-9]*\z/) or
        die sprintf("Line %d: Invalid table name '%s'!\n",
                    $lnum, $tname);
      
      $table_name     = $tname;
      $table_suppress = 0;
      $field_names    = [];
      
      unless ($ctype eq $dbtype) {
        $table_suppress = 1;
      }
      
    } elsif ($opname eq 'column') {
      my $cname = popString(\@stack, $lnum);
      
      (defined $field_names) or
        die sprintf("Line %d: Table must be defined for column!\n",
                    $lnum);
      
      ($cname =~ /\A[A-Za-z_][A-Za-z_0-9]*\z/) or
        die sprintf("Line %d: Invalid column name '%s'!\n",
                    $lnum, $cname);
      
      push @$field_names, ($cname);
      
    } elsif ($opname eq 'tx') {
      my $en = popString(\@stack, $lnum);
      my $is = popString(\@stack, $lnum);
      my $tx = popString(\@stack, $lnum);
      
      addRecord($lnum, $tx, $is, $en);
      
    } elsif ($opname eq 'txl') {
      my $en = popString(\@stack, $lnum);
      my $is = popString(\@stack, $lnum);
      my $lv = popInteger(\@stack, $lnum);
      my $tx = popString(\@stack, $lnum);
      
      addRecord($lnum, $tx, $lv, $is, $en);
      
    } elsif ($opname eq 'txi') {
      my $en = popString(\@stack, $lnum);
      my $is = popString(\@stack, $lnum);
      my $lv = popInteger(\@stack, $lnum);
      
      addRecord($lnum, $lv, $is, $en);
      
    } else {
      die sprintf("Line %d: Unrecognized operation!\n", $lnum);
    }
    
  } else { # ===========================================================
    die sprintf("Line %d: Unsupported Shastina entity!\n", $lnum);
  }
}

# Check whether parsing ended successfully
#
if ($ent < 0) {
  # Finished with an error code
  die sprintf("Line %d: %s!\n",
                (defined $sr->count) ? $sr->count : -1,
                snerror_str($ent));
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
