package Beygja::CSV;
use v5.14;
use warnings;
use utf8;

# Core imports
use Scalar::Util qw(looks_like_number);

=head1 NAME

Beygja::CSV - Parser for CSV data files.

=head1 SYNOPSIS

  use Beygja::CSV;
  
  # Open a CSV file
  my $csv = Beygja::CSV->load("myfile.csv");
  
  # If we want the total line count, we need to scan
  $csv->scan;
  
  # Once we scanned, we can access the total line count
  my $line_count = $csv->count;
  
  # Rewind back to start of the file
  $csv->rewind;
  
  # Skip some lines that won't be parsed
  $csv->skip(2);
  
  # Keep reading record lines
  for(
      my $rec = $csv->readRecord;
      defined $rec;
      $rec = $csv->readRecord) {
    
    # Get the line number of the most recently read record
    my $lnum = $csv->number;
    
    # Go through each field in the record
    for(my $i = 0; $i < scalar(@$rec); $i++) {
      # Get the field value
      my $value = $rec->[$i];
    }
  }
  
  # Parse a value into an array
  my @arr = Beygja::CSV->array("Value1,Value2,Value3");
  
  # Explicitly close the opened file
  $csv->unload;

=head1 DESCRIPTION

Reads through CSV files in DIM format.

The file should be UTF-8 encoded, with Byte Order Mark (BOM) optional at
the very start of the file.  Line breaks are either LF or CR+LF.

Blank lines that are empty or consist only of spaces and tabs will be
skipped.  You can also skip lines with the C<skip()> function, which is
useful for skipping over headers.

Record lines have one or more fields.  Fields are separated from each
other with semicolons.  Each field value is automatically beginning- and
end-trimmed of space and tab characters.

Some fields might encode arrays where values are separated by commas.
There is no way for the parser to distinguish between arrays and
non-array field values when there are less than two elements, so the
parser always interprets fields as non-arrays and then provides a static
C<array()> function that will parse arrays.

Parsing and I/O errors will cause fatal errors.  This module is not
designed to recover from errors, so if an error occurs and you catch it,
you should C<unload()> the instance that threw the error.

=cut

# =========
# Constants
# =========

# Maximum safe integer size.
#
# This is the maximum integer value that can be reliably stored in a
# double-precision value without losing precision.  The negative
# equivalent of this values can also be stored.
#
use constant MAX_INTEGER => 9007199254740991;

# ========================
# Private static functions
# ========================

# _validInteger(i)
# ----------------
#
# Returns 1 if the given value looks_like_number() and it is an integer
# that is in range [-MAX_INTEGER, MAX_INTEGER].  Otherwise, returns 0.
#
sub _validInteger {
  # Get parameter
  ($#_ == 0) or die;
  my $i = shift;
  
  # Check if integer
  (looks_like_number($i) and (int($i) == $i)) or return 0;
  
  # Check if in range
  (($i >= 0 - MAX_INTEGER) and ($i <= MAX_INTEGER)) or return 0;
  
  # If we got here, check is successful
  return 1;
}

=head1 STATIC FUNCTIONS

=over 4

=item B<array(str)>

Parse a string value as an array and return the elements in list
context.

The string contains zero or more array elements.  If it contains only
spaces and tabs, then the result is an empty list.

Elements are separated by comma characters.  If there are no commas in
the string, then the string decodes either to an empty list or a list of
one element.

Each element is trimmed of leading and trailing tabs and spaces.

=cut

sub array {
  # Drop module reference
  shift;
  
  # Get parameters
  ($#_ == 0) or die;
  my $str = shift;
  
  (not ref($str)) or die;
  (not ($str =~ /[\r\n]/)) or die;
  
  # Check for empty array
  if ($str =~ /\A[ \t]*\z/) {
    return;
  }
  
  # Check for single-element array
  unless ($str =~ /,/) {
    # Trim leading and trailing whitespace
    $str =~ s/\A[ \t]+//;
    $str =~ s/[ \t]+\z//;
    
    # Return single-element array
    return ($str);
  }
  
  # If we got here, then split into elements on comma
  my @result = split /,/, $str;
  
  # Trim each element
  for my $str (@result) {
    $str =~ s/\A[ \t]+//;
    $str =~ s/[ \t]+\z//;
  }
  
  # Return the parsed list
  return @result;
}

=back

=head1 CONSTRUCTOR

=over 4

=item B<load(path)>

Construct a new CSV parser instance.

The C<path> is the path to the file to open.  Fatal errors occur if the
file can not be opened successfully.

=cut

sub load {
  # Get parameters
  ($#_ == 1) or die;
  
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  
  my $path = shift;
  (not ref($path)) or die;
  
  # Define the new object
  my $self = { };
  bless($self, $class);
  
  # The '_fh' property is the read-only file handle with UTF-8 decoding
  # and CR+LF transation, or undef if the object has been unloaded
  open(my $fh, "< :encoding(UTF-8) :crlf", $path) or
    die "Failed to open '$path' for reading, stopped";
  (defined $fh) or
    die "Failed to open '$path' for reading, stopped";
  $self->{'_fh'} = $fh;
  
  # The '_count' property is the total number of lines that were scanned
  # in the file, or undef if the file has not been scanned yet
  $self->{'_count'} = undef;
  
  # The '_lnum' property is the line number of the line that was most
  # recently read or skipped, where line 1 is the first line; this has
  # the value zero if nothing has been read or skipped yet or if we just
  # rewound the file
  $self->{'_lnum'} = 0;
  
  # Return the new object
  return $self;
}

=back

=head1 DESTRUCTOR

The destructor routine closes the file handle if it is not already
closed.

=cut

sub DESTROY {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Only proceed if file handle has not been closed
  if (defined $self->{'_fh'}) {
    # Close the file handle
    close($self->{'_fh'}) or warn "Failed to close file handle";
    $self->{'_fh'} = undef;
  }
}

=head1 INSTANCE METHODS

=over 4

=item B<readRecord()>

Read and return the next record from the file.

Returns a reference to an array containing each of the fields, or
C<undef> if there are no more lines in the file.

This function does not attempt to parse array values into arrays, since
it is not able to reliably identify what is an array.  You can use the
static C<array()> function of this module to parse array fields.

=cut

sub readRecord {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Keep reading lines and updating the line count until we read a
  # non-blank line or EOF is encountered or there is an error
  my $ltext;
  for($ltext = readline($self->{'_fh'});
      defined $ltext;
      $ltext = readline($self->{'_fh'})) {
    # We read a line, so update the line count
    ($self->{'_lnum'} < MAX_INTEGER) or die "Line number overflow";
    $self->{'_lnum'}++;
    
    # Trim line break from the end of the line
    chomp $ltext;
    
    # If line is not blank, then leave loop
    unless ($ltext =~ /\A[ \t]*\z/) {
      last;
    }
  }
  
  # If we didn't successfully read a non-blank line, determine if due to
  # EOF or error and handle both special cases
  unless (defined $ltext) {
    if (eof($self->{'_fh'})) {
      return undef;
    } else {
      die "I/O error";
    }
  }
  
  # If we got here, we have a non-blank line, so first handle the
  # special case of a single field
  unless ($ltext =~ /;/) {
    # Trim single field of leading and trailing whitespace
    $ltext =~ s/\A[ \t]+//;
    $ltext =~ s/[ \t]+\z//;
    
    # Return the single field
    return [ $ltext ];
  }
  
  # If we got here, we have multiple fields, so parse into fields,
  # including empty fields at the end
  my @fields = split /;/, $ltext, -1;
  
  # Trim each field
  for my $fv (@fields) {
    $fv =~ s/\A[ \t]+//;
    $fv =~ s/[ \t]+\z//;
  }
  
  # Return the parsed record
  return \@fields;
}

=item B<number()>

Return the line number of the line that was most recently read or
skipped.  Returns zero if nothing has been read or skipped yet, or if
the file was just rewound.

=cut

sub number {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Return the number
  return $self->{'_lnum'};
}

=item B<skip(count)>

Skip the given number of lines in the file.

C<count> must be an integer that is zero or greater.  If it is zero,
then this function will do nothing.  Otherwise, the given number of
lines will be skipped without parsing.

If the end of the file is reached before the requested number of lines
has been skipped, this function will silently end early.

=cut

sub skip {
  # Check parameter count
  ($#_ == 1) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Get parameters
  my $count = shift;
  _validInteger($count) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Keep reading lines and updating the line count until we have read
  # the requested number of lines or EOF is encountered or there is an
  # error
  for(my $i = 0; $i < $count; $i++) {
    # Attempt to read a line
    my $ltext = readline($self->{'_fh'});
    unless (defined($ltext)) {
      if (eof($self->{'_fh'})) {
        return;
      } else {
        die "I/O error";
      }
    }
    
    # We read a line, so update the line count
    ($self->{'_lnum'} < MAX_INTEGER) or die "Line number overflow";
    $self->{'_lnum'}++;
  }
}

=item B<rewind()>

Rewind back to the beginning of the file.

=cut

sub rewind {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Reset the file pointer
  seek($self->{'_fh'}, 0, 0) or die "I/O error";
  
  # Reset _lnum
  $self->{'_lnum'} = 0;
}

=item B<scan()>

Figure out the total number of lines in the file and rewind.

If we've already scanned before, this function just rewinds and does
nothing further.

=cut

sub scan {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Rewind the file
  $self->rewind;
  
  # If we've already scanned, we are done
  if (defined $self->{'_count'}) {
    return;
  }
  
  # Keep reading lines and updating the line count until we hit EOF or
  # an error
  my $ltext;
  for($ltext = readline($self->{'_fh'});
      defined $ltext;
      $ltext = readline($self->{'_fh'})) {
    # We read a line, so update the line count
    ($self->{'_lnum'} < MAX_INTEGER) or die "Line number overflow";
    $self->{'_lnum'}++;
  }
  
  # Determine if we stopped due to error
  (eof($self->{'_fh'})) or die "I/O error";
  
  # We didn't stop due to I/O error, so store the current line number as
  # the count, setting it to at least one
  $self->{'_count'} = $self->{'_lnum'};
  unless ($self->{'_count'} > 0) {
    $self->{'_count'} = 1;
  }
  
  # Rewind again
  $self->rewind;
}

=item B<count()>

Return the total number of lines in the file, which will be at least
one.

You must call C<scan()> before this function can be used.

=cut

sub count {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Fail if we've unloaded the file
  (defined $self->{'_fh'}) or die;
  
  # Fail if we haven't scanned yet
  (defined $self->{'_count'}) or die;
  
  # Return the count
  return $self->{'_count'};
}

=item B<unload()>

Close the underlying file if not already closed.  You can't call other
functions on this object after it is unloaded, except you can call
C<unload()> as many times as you wish.

=cut

sub unload {
  # Check parameter count
  ($#_ == 0) or die;
  
  # Get self
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or die;
  
  # Only proceed if file handle has not been closed
  if (defined $self->{'_fh'}) {
    # Close the file handle
    close($self->{'_fh'}) or warn "Failed to close file handle";
    $self->{'_fh'} = undef;
  }
}

=back

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

# End with something that evaluates to true
1;
