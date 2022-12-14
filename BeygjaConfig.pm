package BeygjaConfig;
use v5.14;
use warnings;
use utf8;

use parent qw(Exporter);

=head1 NAME

BeygjaConfig - Beygja configuration module.

=head1 SYNOPSIS

  use BeygjaConfig qw(beygja_dbpath);
  
  # Get the path of a specific database
  my $verb_db_path = beygja_dbpath('verb');

=head1 DESCRIPTION

Provides configuration functions.  Specifically, this provides a
function that determines the path to each specific Beygja inflection
database.

B<Important:> You must edit this script to have the proper paths for
your specific system.  See the section marked C<@@TODO:> in the source
file.  Until you configure the script, the functions will cause fatal
errors indicating configuration has not been performed yet.

=cut

# =====================
# CONFIGURATION SECTION
# =====================

# ----------------------------------------------------------------------
# @@TODO: In the %DB_MAP constant below, edit the values to paths that
# are appropriate for your particular system, and then change the
# DB_MAP_CONFIGURED constant value to 1 to indicate you have configured
# this file.
# ----------------------------------------------------------------------

my %DB_MAP = (
  'verb' => '/media/pi/3V635FXG/Documents/NEW/dev_posted/beygja/derived/beygja_verb.sqlite',
);

use constant DB_MAP_CONFIGURED => 1;

=head2 FUNCTIONS

=over 4

=item B<beygja_dbpath(db)>

Return the path to a specific Beygja database.

B<Important:> You must edit the source file of this script before this
function will work.  Look for the C<@@TODO:> marker in the source file.

The C<db> parameter is the specific Beygja database to get a path for.
Currently, the C<verb> value is supported for the verb inflections
database.

=cut

sub beygja_dbpath {
  # Check state
  unless (DB_MAP_CONFIGURED) {
    die "You haven't configured BeygjaConfig.pm yet, stopped";
  }
  
  # Get parameter
  ($#_ == 0) or die;
  my $db = shift;
  (not ref($db)) or die;
  
  # Get the path
  (defined $DB_MAP{$db}) or
    die "Database type '$db' not recognized, stopped";
  my $path = $DB_MAP{$db};
  
  # Return the path
  return $path;
}

# ==============
# Module exports
# ==============

our @EXPORT_OK = qw(
  beygja_dbpath
);

1;
