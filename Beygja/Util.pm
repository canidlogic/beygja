package Beygja::Util;
use v5.14;
use warnings;
use utf8;

use parent qw(Exporter);

=head1 NAME

Beygja::Util - Beygja utility functions.

=head1 SYNOPSIS

  use Beygja::VerbCode qw(dimToVerbCode);
  
  # Convert a DIM tag to a verb code and order number
  my ($verb_code, $order_number) = dimToVerbCode("GM-BH-ST2");

=head1 DESCRIPTION

Provides various utility functions.  See the function documentation for
details.

=head1 FUNCTIONS

=over 4

=item B<dimToVerbCode(str)>

Parse an inflection tag from the DIM data into a Beygja verb inflection
code and an order number.

Returns two values.  The first is the Beygja verb inflection code as a
string and the second is the order number as an integer.  If the
conversion fails, C<undef> is returned for both values.

See the C<VerbInflections.md> documentation file for details about how
the Beygja verb inflection codes work.

DIM data allows for a decimal integer suffix at the end of the
inflection code to indicate variants.  If there is no decimal integer
suffix, the default order number of 1 will be returned.  Otherwise, the
returned order number will match the decimal integer suffix.

This function uses an internal cache to speed things up.  If C<str> has
already been queried, this returns the cached response instead of
recomputing it.  C<str> values that don't successfully convert are
I<not> cached, however.

=cut

# Cache of input strings to array references storing the translated
# Beygja inflection code and the inflection order.
#
my %verbcode_cache;

# Mapping of DIM elements within the inflection tags to the equivalent
# Beygja verb inflection codes.
#
# All DIM elements used for verbs should be keys in the this map.
# However, note that the mapping is not one-to-one!  Sometimes multiple
# DIM elements map to the same Beygja value, sometimes a single DIM
# element maps to more than one Beygja value (indicated by a string
# value with more than one character), and sometimes a single DIM
# element maps to no Beygja values (indicated by an empty string value).
#
my %VERBCODE_MAPPING = (
  'GM'    => 'a',
  'MM'    => 'm',
  'FH'    => 'i',
  'VH'    => 's',
  'NT'    => 'r',
  'ÞT'    => 'p',
  'ET'    => 'v',
  'FT'    => 'w',
  '1P'    => '1',
  '2P'    => '2',
  '3P'    => '3',
  'NH'    => 'I',
  'BH'    => 'M',
  'LHNT'  => 'R',
  'LHÞT'  => 'P',
  'SAGNB' => 'S',
  'SB'    => 's',
  'VB'    => 'i',
  'KK'    => '1',
  'HK'    => '2',
  'KVK'   => '3',
  'NFET'  => 'v4',
  'ÞFET'  => 'v5',
  'ÞGFET' => 'v6',
  'EFET'  => 'v7',
  'NFFT'  => 'w4',
  'ÞFFT'  => 'w5',
  'ÞGFFT' => 'w6',
  'EFFT'  => 'w7',
  'OP'    => '',
  'það'   => '.',
  'ÞF'    => ':',
  'ÞGF'   => ',',
  'EF'    => ';',
  'SP'    => 'Q',
  'ST'    => 'z'
);

# Maps each character in the Beygja verb code alphabet to its order
# category, with lower order categories appearing before higher ones.
#
# It is an error for a Beygja verb code to have multiple characters in
# the same order category, but it is allowed to have empty order
# categories.
#
my %VERBCODE_ORDER = (
  '.' => 0,
  ':' => 0,
  ',' => 0,
  ';' => 0,
  'F' => 1,
  'Q' => 1,
  'I' => 1,
  'M' => 1,
  'R' => 1,
  'P' => 1,
  'S' => 1,
  'a' => 2,
  'm' => 2,
  'i' => 3,
  's' => 3,
  'r' => 4,
  'p' => 4,
  '1' => 5,
  '2' => 5,
  '3' => 5,
  'v' => 6,
  'w' => 6,
  'z' => 6,
  '4' => 7,
  '5' => 7,
  '6' => 7,
  '7' => 7
);

# This array has one record for each of the order values defined in the
# VERBCODE_ORDER map.
#
# Each record in this array is a hash reference to a set of inflection
# class codes that have a value in this category.
#
# This does not include the exceptional past-tense active infinitive,
# nor does it include the restriction that only active imperatives may
# have the clipped value for number, nor the restrictions that the
# different prefixes impose.
#
my @VERBCODE_ALLOW = (
  {'F' => 1},
  {'F' => 1,'Q' => 1,'I' => 1,'M' => 1,'R' => 1,'P' => 1,'S' => 1},
  {'F' => 1,'Q' => 1,'I' => 1,'M' => 1,'S' => 1},
  {'F' => 1,'Q' => 1,'P' => 1},
  {'F' => 1,'Q' => 1},
  {'F' => 1,'Q' => 1,'P' => 1},
  {'F' => 1,'Q' => 1,'M' => 1,'P' => 1},
  {'P' => 1},
);

# The public function
#
sub dimToVerbCode {
  # Get parameter
  ($#_ == 0) or die;
  my $str = shift;
  (not ref($str)) or die;
  
  # If cached response, return that
  if (defined $verbcode_cache{$str}) {
    my $cr = $verbcode_cache{$str};
    return ($cr->[0], $cr->[1]);
  }
  
  # Store original string for caching purposes
  my $original_input = $str;
  
  # Extract the order number first
  my $order_number = 1;
  if ($str =~ /([0-9]+)\z/) {
    $order_number = int($1);
    $str =~ s/[0-9]+\z//;
  }
  
  # String shouldn't be empty now or fail
  (length($str) > 0) or return (undef, undef);
  
  # Start an array of eight elements that will be used to store each of
  # the eight orders for the verb code
  my @varr = (undef, undef, undef, undef, undef, undef, undef, undef);
  
  # Go through each elemental tag in the string
  for my $el (split /\-/, $str) {
    # Skip if this element is not defined or empty
    (defined $el) or next;
    (length($el) > 0) or next;
    
    # Find the verb code mapping
    (defined $VERBCODE_MAPPING{$el}) or return (undef, undef);
    my $vcm = $VERBCODE_MAPPING{$el};
    
    # Go through each character in the verb code mapping
    for my $c (split //, $vcm) {
      # Get the order of this character
      my $vco = $VERBCODE_ORDER{$c};
      
      # Make sure order hasn't been defined yet and then add it
      (not defined $varr[$vco]) or return (undef, undef);
      $varr[$vco] = $c;
    }
  }
  
  # If the inflection class is missing, set it to default F
  unless (defined $varr[1]) {
    $varr[1] = 'F';
  }
  
  # Get the inflection class
  my $iclass = $varr[1];
  
  # Get the combined verb inflection code
  my $vic = '';
  for my $ve (@varr) {
    if (defined $ve) {
      $vic = $vic . $ve;
    }
  }
  
  # Allow the exceptional past-tense infinitive
  if ($vic eq 'Iap') {
    $verbcode_cache{$original_input} = ['Iap', $order_number];
    return ('Iap', $order_number);
  }
  
  # Go through and make sure all categories match what is needed for the
  # inflection class
  for(my $i = 0; $i <= $#varr; $i++) {
    if (defined $varr[$i]) {
      # Category is defined, so make sure it is allowed for this class
      unless (defined $VERBCODE_ALLOW[$i]->{$iclass}) {
        return (undef, undef);
      }
      
    } else {
      # Category is not defined, so make sure it is not allowed for this
      # class; except, skip this check for order 0 (prefixes optional)
      if ($i > 0) {
        if (defined $VERBCODE_ALLOW[$i]->{$iclass}) {
          return (undef, undef);
        }
      }
    }
  }
  
  # The "z" clipped number may only appear for "Maz"
  if ($vic =~ /z/) {
    if ($vic eq 'Maz') {
      $verbcode_cache{$original_input} = ['Maz', $order_number];
      return ('Maz', $order_number);
    } else {
      return (undef, undef);
    }
  }
  
  # If a prefix is defined, check the restrictions
  if (defined $varr[0]) {
    if ($varr[0] eq '.') {
      # Dummy subject can only be used with 3rd person singular
      (($varr[5] eq '3') and ($varr[6] eq 'v')) or
        return (undef, undef);
      
    } elsif (($varr[0] eq ':') or ($varr[0] eq ';')) {
      # Accusative and genitive subject can only be used with active
      # voice
      ($varr[2] eq 'a') or return (undef, undef);
    }
  }
  
  # If we got here, return the conversion
  $verbcode_cache{$original_input} = [$vic, $order_number];
  return ($vic, $order_number);
}

=back

=cut

# ==============
# Module exports
# ==============

our @EXPORT_OK = qw(
  dimToVerbCode
);

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
