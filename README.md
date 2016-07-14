# Additions and Updates to Restore Script
- Fixed SQL queries so that they accept table names of only digits.
- Fixed dissagreement between help statement and actual option usage.
- Changed handling of configuration file so that values from the config file are always used but are overridden by values from the command line. All configuration values can be overwritten by their matching command line option. Where appropriate, options are similar to using "mysql" client.
- Added modes to only process code or only import data. They are commented out as they are incomplete.
- The added and commented out code is a start at adding/changing the existing table name prefix. Table prefix handling is incomplete.

These changes have been tested with Ubuntu 14.04 Server.

# Magento Support Restore Script
```
> restore.sh
```

This script is designed to be run from folder with Magento dumps.
It restores dump files created by Magento Support module or backup.sh script:
> code dump (for ex. 5a9cefe85f8e1ccc2a5191553f31ab82.201607061906.sql.gz)

> DB dump (for ex. 5a9cefe85f8e1ccc2a5191553f31ab82.201607061906.tar.gz)

## Options
```
Usage: ./restore.sh [option]
    --help                show available params for script (this screen)
    -w, --without-config  do not use config file data
    -f, --force           install without check step
    -r, --reconfigure     ReConfigure current magento instance
    -c, --clean-install   Standard install procedure through CLI
    -m, --mode            must have one of the following:
                          "reconfigure", "clean-install", "code", or "db"
                          The first two are optional usages of the previous two options.
                          "code" tells the script to only decompress the code, and
                          "db" to only move the data into the database.
    -h, --host            DB host IP address, defaults to "localhost"
    -D, --database        Database or schema name, defaults to current directory name
    -u, --user            DB user name
    -p, --password        DB password
    -b, --base-url        Base URL for this deployment host.
```

This script assumes it is being run from the new deployment directory with merchant backup files.

Your "~/.restore.conf" file must be manually created in your home directory.

Missing entries are treated as empty strings.

In most cases, if the requested value is not included on the command line then the corresponding value from the config file is used. In the special case of the DB name, if the DB name is empty in the config file and none is entered on the command line then the current working directory basename is used. Digits are allowed as a DB name.

## Example
This is the contents of my "~/.restore.conf" that is running on a VirtualBox instance of Ubuntu 14.04 Server:
```
DBUSER=magento
DBPASS=magpass
BASE_URL=http://192.168.56.131/
```

Say you're working on SUPEE-9999. Place your dump files and this script in a directory inside your working web root, say "/var/www/9999/". You should see something like this (and type "n" or "no" to cancel the process):
```
reid@u14p55m56a:/var/www/9999$ ./restore.sh

Check parameters:
DB host is: localhost
DB name is: 9999
DB user is: magento
DB pass is: magpass
Full base url is: http://192.168.56.131/9999/
Continue? [Y/n]: n
Interrupted by user, exiting...
reid@u14p55m56a:/var/www/9999$
```

# Progress bar
In order to see a progress bar while restoring a dump you will need to install the `pv` utility.
