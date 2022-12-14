# Beygja inflections database

Tools for importing the DIM data for Icelandic inflections into a SQL database.

The DIM data is found [here](https://bin.arnastofnun.is/DMII/LTdata/data/)

While the DIM stores everything in one giant database, Beygja splits the data into multiple databases.  This alpha version only supports a verb database of verbal inflections.

## Building the databases

You need the following non-core Perl dependencies installed and in the Perl module search path:

* `DBD::SQLite`
* `File::Slurp`
* [libshastina](https://github.com/canidlogic/libshastina) Perl library
* The `Beygja` directory in this project

First, edit the `BeygjaConfig.pm` source file to set the absolute paths to the SQL databases that you want to create.  See the `@@TODO:` marker in the source code.

Second, make a copy of `TemplateDB.script` and follow all the `@@TODO:` markers to fill in data from the DIM.  As of the time of writing, the following typos in the DIM documentation should be corrected while you are filling in the data:

* Language register `OFORM` should be corrected to `OFOR`
* Semantic domain `vid` should be corrected to `við`
* Semantic domain `Stærð` should be corrected to `stærð`
* Add another semantic domain `landb` (meaning?)
* Add another semantic domain `hest` (meaning?)
* Grammar flag `OAFNÓ` should be corrected to `OAFN`
* Grammar flag `NN4N-ORDx` should be corrected to `NN4N-ORD`
* Grammar flag `NHÞT` should be corrected to `NHTHT`

Third, use `dbrun.pl` with the database script you filled in in the previous step to create each of the databases and fill in their constant tables.  The databases will be created at the locations given in `BeygjaConfig.pm`.  They must not already exist or the creation process will fail.  (Currently, only the `verb` database is supported.)

Fourth, use `beygja_words.pl` to import all the relevant word records to each database.  You will need the (decompressed) `Storasnid_ord.csv` data file from the DIM data, which is the Comprehensive Format for words.  (Currently, only the `verb` database is supported.)

Fifth, use the database-specific inflection scripts to import all the relevant inflections to each database.  You will need the (decompressed) `Storasnid_beygm.csv` data file from the DIM data, which is the Comprehensive Format for inflectional forms.  (Currently, only the `verb` database is supported, which uses the `beygja_iverb.pl` script to import inflectional forms.)

## Manifest

The scripts in this top-level directory are used for constructing the database.  The subdirectories are:

* `Beygja` - Perl modules that are referenced from the various scripts.  This will need to be in the Perl module search path
* `doc` - documentation files
* `tools` - various utility scripts
* `verb` - analytic tools for the verb database

## History

### Development

Changed architecture to support multiple databases for different word classes.  Completed functionality for building and importing all records to the `verb` database.

### Version 0.0.1-Alpha

Capable of importing all the word records from the DIM data.
