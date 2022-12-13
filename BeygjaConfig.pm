package BeygjaConfig;
use v5.14;
use warnings;

use parent qw(Exporter);
our @EXPORT = qw(CONFIG_DBPATH);

use constant CONFIG_DBPATH => '/path/to/database.sqlite';

1;
