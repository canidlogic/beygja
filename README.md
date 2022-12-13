# Beygja inflections database

Tools for importing the DIM data for Icelandic inflections into a SQL database.

The DIM data is found [here](https://bin.arnastofnun.is/DMII/LTdata/data/)

This alpha version is only able to import the word information.  It has the structures for importing inflections but is not able to actually import the inflections yet.

## Building the database

You need the following non-core Perl dependencies installed and in the Perl module search path:

* `DBD::SQLite`
* [libshastina](https://github.com/canidlogic/libshastina) Perl library
* The `Beygja` directory in this project

First, edit the `BeygjaConfig.pm` source file to set the absolute path to the SQL database that you want to create and use with all the tools.

Second, make a copy of `TemplateDB.script` and follow all the `@@TODO:` markers to fill in data from the DIM.  As of the time of writing, the following typos in the DIM documentation should be corrected while you are filling in the data:

* Language register `OFORM` should be corrected to `OFOR`
* Semantic domain `vid` should be corrected to `við`
* Semantic domain `Stærð` should be corrected to `stærð`
* Add another semantic domain `landb` (meaning?)
* Add another semantic domain `hest` (meaning?)
* Grammar flag `OAFNÓ` should be corrected to `OAFN`
* Grammar flag `NN4N-ORDx` should be corrected to `NN4N-ORD`
* Grammar flag `NHÞT` should be corrected to `NHTHT`

One of the `@@TODO:` markers will direct you to use the `gentags.pl` script to automatically generate inflectional tag records.

Third, use `dbrun.pl` with the database script you filled in in the previous step to create the database and fill in the constant tables.  The database will be created at the location given in `BeygjaConfig.pm`.  It must not already exist or the creation process will fail.

Fourth, use `beygja_words.pl` to import all the word records.  You will need the `Storasnid_ord.csv` data file from the DIM data, which is the Comprehensive Format for words.

Another script `beygja_forms.pl` is present to import inflection records, but it is currently incomplete in this alpha and will not work yet.

## Manifest

The scripts in this top-level directory are used for constructing the database.

The `Beygja` subdirectory contains Perl modules that are referenced from the various scripts.  This will need to be in the Perl module search path.

The `doc` subdirectory contains documentation files.

The `tools` subdirectory contains various utility scripts that are not necessary for constructing the database.

## History

### Version 0.0.1-Alpha

Capable of importing all the word records from the DIM data.
