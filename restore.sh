#!/bin/bash
# Magento restore script
#
# You can use a config file
# Create the file in your home directory .restore.conf
# Or specify path to properly formatted file

# Be sure to use MAMP alias, if any.
# MAMP sets an alias rather than changing the command path.
if [[ -f ~/.profile ]] ; then shopt -s expand_aliases ; source ~/.profile ; fi

# Be sure to kill subprocesses if script is killed.
CHILD_PID=

function kill_subprocesses()
{
    local PID
    for PID in $CHILD_PID
    do
        if [[$(kill -0 $PID) <= /dev/null]]
        then
           kill -SIGKILL $PID
        fi
    done

    printf '\n'
    exit
}

trap 'kill_subprocesses' SIGHUP SIGINT SIGTERM SIGQUIT SIGTSTP SIGSTOP

####################################################################################################
#Variables with defaults which are allowed to be overwritten by the config file.
MAGENTO_ROOT="$PWD"
INSTANCE_DIR_NAME=$(basename "$MAGENTO_ROOT")

DB_HOST='sparta-db'
DB_USER_PREFIX="${USER}_"
# The variable DB_SCHEMA is often not quoted throughout the script as it should always appear as one word.
DB_SCHEMA=
# The variables DB_USER and DB_PASS are quoted throughout the script as they could contain spaces.
DB_USER="$USER"
DB_PASS=
BASE_URL="http://web1.sparta.corp.magento.com/dev/${USER}/"
FULL_INSTANCE_URL=
CORE_CONFIG_FILE=
CORE_CONFIG_RUN=0

LOCALE_CODE=${LANG:0:5}
TIMEZONE=$TZ

EXCEPTION_LOG_NAME='exception_dev.log'
SYSTEM_LOG_NAME='system_dev.log'

ADMIN_EMAIL="${USER}@magento.com"
ADMIN_USERNAME='admin'
ADMIN_PASSWORD='123123q'
ADMIN_PASSWD_HASH='eef6ebe8f52385cdd347d75609309bb29a555d7105980916219da792dc3193c6:6D'

# List of user settable variables to display.
VARIABLES_TO_DISPLAY='
    MAGENTO_ROOT INSTANCE_DIR_NAME DB_HOST DB_USER_PREFIX DB_SCHEMA DB_USER DB_PASS
    BASE_URL FULL_INSTANCE_URL LOCALE_CODE TIMEZONE EXCEPTION_LOG_NAME SYSTEM_LOG_NAME
    ADMIN_EMAIL ADMIN_USERNAME ADMIN_PASSWORD ADMIN_PASSWD_HASH
'

# Global variables.
CONFIG_FILE_PATH="${HOME}/.restore.conf"

P_DB_PASS=

TABLE_PREFIX=
CRYPT_KEY=
INSTALL_DATE=

DEBUG_MODE=0
DDR_OPT=

TAR_EXCLUDES="--exclude='._*' --exclude='var/cache' --exclude='var/full_page_cache'"

FORCE_RESTORE=0


####################################################################################################
#Define functions.

function showHelp()
{
    cat <<ENDHELP
Magento 1 Deployment Restore Script
Usage: ${0} [option]
    -H --help
            This screen.

    -c --config-file <file-name>
            Specify an additional configuration file. Variables defined here will override
            all other command line or "${CONFIG_FILE}" set variables.

    -F --force
            Install without pause to check data.

    -r --reconfigure
            Reconfigure files and DB only.

    -i --install-only
            Standard fresh install procedure through CLI.

    -m --mode <run-mode>
            This must have one of the following:
            "reconfigure", "install-only", "git-wrap", "reconfigure-code", "reconfigure-db", "code", or "db"
            The first two are optional usages of the previous two options.
            "code" tells the script to decompress and reconfigure the code, and
            "db" to move the data into the database and reconfigure the data.

    -h --host <host-name>|<ip-address>
            DB host name or IP address, defaults to "sparta-db".

    -D --database <name-string>
            Database or schema name.
            Defaults to "${USER}_" plus the current directory name.

    -u --user <user-name>
            DB user name. Defaults to "$USER".

    -p --password <password>
            DB password. Default is empty. A password cannot contain spaces.

    -f --full-instance-url <url>
            Full instance URL for this deployment host.
            Defaults to "http://web1.sparta.corp.magento.com/dev/${USER}/<dev sub dir>/".
            If it's not set then the default or config file value will be used
            and appended with the working directory basename.

    -e --email <email-address>
            Admin email address. Defaults to "${USER}@magento.com".

    -l --locale <locale-code>
            "base/locale/code" configuration value. Defaults to "${LOCALE_CODE}".

    --additional-configs <file-name>
            File name of additional or custom core config data. The lines must be
            formated as those in the function "doDbReconfigure".

    -C      Only update core_config_data with the values specified in the
            additional-configs file. Ignore all other options.

This script can be located anywhere but it assumes the current working directory
is the new deployment directory with the merchant's backup files. Your default
"${CONFIG_FILE_NAME}" file must be manually created in your home directory.

Missing entries are given default values. In most cases, if the requested
value is not included on the command line then the corresponding value from the
config file is used. In the special case of the DB schema name, if the name is
empty in the config file and none is entered on the command line then the
current working directory basename is used with the value in DB_USER_PREFIX.
Digits are allowed as a DB name. Sparta users might not need a configuration file.

Some of the available config names with their default values are:
ADMIN_EMAIL=${ADMIN_EMAIL}
BASE_URL=${BASE_URL}
DB_HOST=${DB_HOST}
DB_SCHEMA=
DB_PASS=
DB_USER=${DB_USER}
DEBUG_MODE=0
DB_USER_PREFIX=${DB_USER_PREFIX}
LOCALE_CODE=${LOCALE_CODE}

Sample ".restore.conf" on a local OSX workstation with MAMP:
DB_HOST=localhost
DB_USER=magento
DB_PASS=magpass
DB_USER_PREFIX=
BASE_URL=http://localhost/

NOTE: OS X users will need to install a newer version of "getopt" from a
repository like MacPorts:
> sudo port install getopt

Also note that xAMP users might need to be sure their desired version of PHP is
in the command path.

ENDHELP

}

####################################################################################################
# Selftest for checking tools which will used
checkTools() {
    local MISSED_REQUIRED_TOOLS=

    for TOOL in 'sed' 'tar' 'mysql' 'head' 'gzip' 'getopt' 'mysqladmin' 'php' 'git'
    do
        which $TOOL >/dev/null 2>/dev/null
        if [[ $? != 0 ]]
        then
            MISSED_REQUIRED_TOOLS="$MISSED_REQUIRED_TOOLS $TOOL"
        fi
    done

    if [[ -n "$MISSED_REQUIRED_TOOLS" ]]
    then
        printf 'Unable to restore instance due to missing required tools:\n%s\n' "$MISSED_REQUIRED_TOOLS"
        exit 1
    fi
}

####################################################################################################
function initVariables()
{
    # Read from optional config file. They will overwrite corresponding variables.
    if [[ -f "$OPT_CONFIG_FILE" ]]
    then
        source "$OPT_CONFIG_FILE"
    fi

    if [[ -z "$DB_SCHEMA" ]]
    then
        DB_SCHEMA="$DB_USER_PREFIX$INSTANCE_DIR_NAME"
    fi

    if [[ -z "$FULL_INSTANCE_URL" ]]
    then
        FULL_INSTANCE_URL="${BASE_URL}${INSTANCE_DIR_NAME}/"
    fi

    printf 'Check parameters:\n'
    for VAR in $VARIABLES_TO_DISPLAY
    do
        printf '%#-20s%s\n' "$VAR" $(eval echo \$$VAR)
    done

    if [[ ${FORCE_RESTORE} -eq 0 ]]
    then
        printf 'Continue? [Y/n]: '
        read CONFIRM

        case "$CONFIRM" in
            [Nn]|[Nn][Oo]) printf 'Canceled.\n'; exit ;;
        esac
    fi

    if [[ -n "$DB_PASS" ]]
    then
        P_DB_PASS="-p$DB_PASS"
    fi

    if [[ -n "$(man tar | grep delay-directory-restore)" ]]
    then
        DDR_OPT='--delay-directory-restore'
    fi
}

####################################################################################################
function extractCode()
{
    FILENAME="$(ls -1 *.gz *.tgz *.bz2 *.tbz2 *.tbz *.gz *.bz *.bz2 2> /dev/null | grep -v '\.logs\.' | grep -v '\.sql\.' | head -n1)"

    debug 'Code dump Filename' "$FILENAME"

    if [[ -z "$FILENAME" ]]
    then
        printf '\nNo file name found.\n\n' >&2
        exit 1
    fi

    printf 'Extracting code.\n'
    expandFileArchive "$FILENAME"

    mkdir -pm 2777 "${MAGENTO_ROOT}/var" "${MAGENTO_ROOT}/media"

    # Also do the log archive if it exists.
    FILENAME="$(ls -1 *.gz *.tgz *.bz2 *.tbz2 *.tbz *.gz *.bz *.bz2 2>/dev/null | grep '\.logs\.' | head -n1)"
    if [[ -n "$FILENAME" ]]
    then
        printf 'Extracting log files.\n'
        expandFileArchive "$FILENAME"
    fi

    printf 'Updating permissions and cleanup.\n'

    mkdir -p "${MAGENTO_ROOT}/var/log/"
    touch "${MAGENTO_ROOT}/var/log/${EXCEPTION_LOG_NAME}"
    touch "${MAGENTO_ROOT}/var/log/${SYSTEM_LOG_NAME}"
    chmod -R 2777 "${MAGENTO_ROOT}/app/etc" "${MAGENTO_ROOT}/var" "${MAGENTO_ROOT}/media"
    chmod -R 2777 "${MAGENTO_ROOT}/app/etc" "${MAGENTO_ROOT}/var" "${MAGENTO_ROOT}/media"
}

function expandFileArchive
{
    # Tar can exclude confusing OS X garbage if any as if this command was run:
    # find . -name '._*' -print0 | xargs -0 rm

    if which pv > /dev/null; then
        case "$1" in
            *.tar.gz|*.tgz)
                pv -B 8k "$1" | tar zxf - $TAR_EXCLUDES $DDR_OPT -C "$MAGENTO_ROOT" 2>/dev/null ;;
            *.tar.bz2|*.tbz2|*.tbz)
                pv -B 8k "$1" | tar jxf - $TAR_EXCLUDES $DDR_OPT -C "$MAGENTO_ROOT" 2>/dev/null ;;
#             *.gz)
#                 gunzip -k "$1" ;;
#             *.bz|*.bz2)
#                 bunzip2 -k "$1" ;;
            *)
                printf '\n"%s" could not be extracted.\n\n' "$1" >&2; exit 1 ;;
        esac
    else
        # Modern versions of tar can automatically choose the decompression type when needed.
        case "$1" in
            *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tbz)
                tar xf "$1" $TAR_EXCLUDES $DDR_OPT -C "$MAGENTO_ROOT" ;;
#             *.gz)
#                 gunzip -k "$1" ;;
#             *.bz|*.bz2)
#                 bunzip2 -k "$1" ;;
            *)
                printf '\n"%s" could not be extracted.\n\n' "$1" >&2; exit 1 ;;
        esac
    fi
}

####################################################################################################
function createDb
{
    mysqladmin --force -h"$DB_HOST" -u"$DB_USER" $P_DB_PASS drop $DB_SCHEMA >/dev/null 2>&1

    mysqladmin -h"$DB_HOST" -u"$DB_USER" $P_DB_PASS create $DB_SCHEMA >/dev/null 2>&1
}

function restoreDb()
{
    printf 'Restoring DB from dump.\n'

    FILENAME=$(ls -1 *.sql.gz | head -n1)

    debug 'DB dump Filename' "$FILENAME"

    if [[ -z "$FILENAME" ]]
    then
        printf '\nDB dump absent.\n\n' >&2
        exit 1
    fi

    if which pv > /dev/null
    then
#         pv "$FILENAME" | gunzip -cf | sed -e 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/' | \
#             mysql -h"$DB_HOST" -u"$DB_USER" $P_DB_PASS --force $DB_SCHEMA 2>/dev/null
        pv "$FILENAME" | gunzip -cf | \
            mysql -h"$DB_HOST" -u"$DB_USER" $P_DB_PASS --force $DB_SCHEMA 2>/dev/null
    else
        gunzip -c "$FILENAME" | gunzip -cf | sed -e 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/' | \
            mysql -h"$DB_HOST" -u"$DB_USER" $P_DB_PASS --force $DB_SCHEMA 2>/dev/null
    fi
}

####################################################################################################
function doDbReconfigure()
{
    printf 'Replacing core config and other DB values.\n'

    getMerchantLocalXmlValues

    runMysqlQuery " \
        CREATE TABLE IF NOT EXISTS ${TABLE_PREFIX}core_config_data_merchant AS \
        SELECT * FROM ${TABLE_PREFIX}core_config_data"

    # Set convenient values for testing.
    setConfigValue 'admin/captcha/enable' '0'

    setConfigValue 'admin/dashboard/enable_charts' '0'

    setConfigValue 'admin/enterprise_logging/actions' 'a:0:{}'

    setConfigValue 'admin/security/lockout_failures' '0'
    setConfigValue 'admin/security/lockout_threshold' '0'
    setConfigValue 'admin/security/password_is_forced' '0'
    setConfigValue 'admin/security/password_lifetime' '9999'
    setConfigValue 'admin/security/session_cookie_lifetime' '0'
    setConfigValue 'admin/security/use_form_key' '0'

    setConfigValue 'admin/startup/page' 'system/config'

    setConfigValue 'dev/css/merge_css_files' '0'
    setConfigValue 'dev/js/merge_files' '0'
    setConfigValue 'dev/log/active' '1'
    setConfigValue 'dev/log/exception_file' "$EXCEPTION_LOG_NAME"
    setConfigValue 'dev/log/file' "$SYSTEM_LOG_NAME"

    setConfigValue 'general/locale/code' "$LOCALE_CODE"
    setConfigValue 'general/locale/timezone' "$TIMEZONE"

    setConfigValue 'system/csrf/use_form_key' '0'
    setConfigValue 'system/page_cache/multicurrency' '0'
    setConfigValue 'system/page_crawl/multicurrency' '0'

    setConfigValue 'web/cookie/cookie_domain' ''
    setConfigValue 'web/cookie/cookie_path' ''
    deleteFromConfigWhere "= 'web/cookie/cookie_lifetime'"

    setConfigValue 'web/secure/base_url' "$FULL_INSTANCE_URL"
    setConfigValue 'web/secure/use_in_adminhtml' '0'
    setConfigValue 'web/unsecure/base_url' "$FULL_INSTANCE_URL"

    deleteFromConfigWhere "IN ('web/unsecure/base_link_url', 'web/unsecure/base_skin_url', 'web/unsecure/base_media_url', 'web/unsecure/base_js_url')"

    deleteFromConfigWhere "IN ('web/secure/base_link_url', 'web/secure/base_skin_url', 'web/secure/base_media_url', 'web/secure/base_js_url')"

    deleteFromConfigWhere "LIKE 'admin/url/%'"

    runMysqlQuery "UPDATE ${TABLE_PREFIX}core_cache_option SET value = 0 WHERE 1"


    # Get "user_id" of first item in table, if any. Likely this is the user with the highest permission level.
    runMysqlQuery "SELECT user_id FROM ${TABLE_PREFIX}admin_user ORDER BY user_id ASC LIMIT 1"
    debug 'SQLQUERY_RESULT' "$SQLQUERY_RESULT"

    USER_ID=$(printf "$SQLQUERY_RESULT" | tr -Cd '[:digit:]')
    debug 'USER_ID' "$USER_ID"

    if [[ -z "$USER_ID" ]]
    then
        runMysqlQuery "SELECT user_id FROM ${TABLE_PREFIX}admin_user ORDER BY user_id ASC LIMIT 1"
        USER_ID=$(printf "$SQLQUERY_RESULT" | sed -e 's/^[a-zA-Z_]*//')
    fi

    runMysqlQuery " \
        UPDATE ${TABLE_PREFIX}admin_user \
        SET password='${ADMIN_PASSWD_HASH}', \
            username='${ADMIN_USERNAME}', \
            is_active=1, \
            email='${ADMIN_EMAIL}' \
        WHERE user_id = ${USER_ID}"

    runMysqlQuery " \
        UPDATE ${TABLE_PREFIX}enterprise_admin_passwords \
        SET expires = UNIX_TIMESTAMP() + (365 * 24 * 60 * 60) \
        WHERE user_id = ${USER_ID}"

    additionalDbConfig
}

function additionalDbConfig()
{
    if [[ -n "$CORE_CONFIG_FILE" ]]
    then
        if [[ -f "$CORE_CONFIG_FILE" ]]
        then
            source "$CORE_CONFIG_FILE"
        else
            printf 'Additional configs file could not be found.\n'
        fi
    fi
}

##  Pass parameters as: key value
function setConfigValue()
{
    # Using "insert...on duplicate key update" won't update values in all scopes.
    runMysqlQuery "SELECT value FROM ${TABLE_PREFIX}core_config_data WHERE path = '$1' LIMIT 1"

    if [[ -z "$SQLQUERY_RESULT" ]]
    then
        runMysqlQuery "INSERT INTO ${TABLE_PREFIX}core_config_data SET path = '$1', value = '$2'"
    else
        runMysqlQuery "UPDATE ${TABLE_PREFIX}core_config_data SET value = '$2' WHERE path = '$1'"
    fi
}

function deleteFromConfigWhere()
{
    runMysqlQuery "DELETE FROM ${TABLE_PREFIX}core_config_data WHERE path $1"
}

function runMysqlQuery()
{
    SQLQUERY_RESULT=$(mysql -h$DB_HOST -u"$DB_USER" $P_DB_PASS -D $DB_SCHEMA -e "$1" 2>/dev/null)
}

function getMerchantLocalXmlValues()
{
    #   If empty then get the values.
    if [[ -z "$INSTALL_DATE" ]]
    then
        getLocalXmlValue 'table_prefix'
        TABLE_PREFIX="$PARAMVALUE"

        getLocalXmlValue 'date'
        INSTALL_DATE="$PARAMVALUE"

        getLocalXmlValue 'key'
        CRYPT_KEY="$PARAMVALUE"
    fi
}

getLocalXmlValue()
{
    # First look for value surrounded by "CDATA" construct.
    local LOCAL_XML_SEARCH="s/.*<${1}><!\[CDATA\[\(.*\)\]\]><\/${1}>.*/\1/p"

    if [[ -e "${MAGENTO_ROOT}/app/etc/local.xml.merchant" ]]
    then
        local ORIGINAL_LOCAL_XML="${MAGENTO_ROOT}/app/etc/local.xml.merchant"
    else
        local ORIGINAL_LOCAL_XML="${MAGENTO_ROOT}/app/etc/local.xml"
    fi

    debug 'local XML search string' "$LOCAL_XML_SEARCH"
    PARAMVALUE=$(sed -n -e "$LOCAL_XML_SEARCH" "$ORIGINAL_LOCAL_XML" | head -n 1)
    debug 'local XML found' "$PARAMVALUE"

    # If not found then try searching without.
    if [[ -z "$PARAMVALUE" ]]
    then
        LOCAL_XML_SEARCH="s/.*<${1}>\(.*\)<\/${1}>.*/\1/p"
        debug 'local XML search string' "$LOCAL_XML_SEARCH"
        PARAMVALUE=$(sed -n -e "$LOCAL_XML_SEARCH" "$ORIGINAL_LOCAL_XML" | head -n 1)
        debug 'local XML found' "$PARAMVALUE"

        # Prevent disaster.
        if [[ "$PARAMVALUE" = '<![CDATA[]]>' ]]
        then
            PARAMVALUE=''
        fi
    fi
}

function debug()
{
    if [[ $DEBUG_MODE -eq 0 ]]
    then
        return
    fi

    printf 'KEY: %s\nVALUE: %s\n\n' "$1" "$2"
}

function getOrigHtaccess()
{
    if [[ ! -f "${MAGENTO_ROOT}/.htaccess.merchant" && -f "${MAGENTO_ROOT}/.htaccess" ]]
    then
        mv "${MAGENTO_ROOT}/.htaccess" "${MAGENTO_ROOT}/.htaccess.merchant"
    fi

    cat <<EOF > "${MAGENTO_ROOT}/.htaccess"
############################################
## uncomment these lines for CGI mode
## make sure to specify the correct cgi php binary file name
## it might be /cgi-bin/php-cgi

#    Action php5-cgi /cgi-bin/php5-cgi
#    AddHandler php5-cgi .php

############################################
## GoDaddy specific options

#   Options -MultiViews

## you might also need to add this line to php.ini
##     cgi.fix_pathinfo = 1
## if it still doesn't work, rename php.ini to php5.ini

############################################
## this line is specific for 1and1 hosting

    #AddType x-mapp-php5 .php
    #AddHandler x-mapp-php5 .php

############################################
## default index file

    DirectoryIndex index.php

<IfModule mod_php5.c>

############################################
## adjust memory limit

#    php_value memory_limit 64M
    php_value memory_limit 256M
    php_value max_execution_time 18000

############################################
## disable magic quotes for php request vars

    php_flag magic_quotes_gpc off

############################################
## disable automatic session start
## before autoload was initialized

    php_flag session.auto_start off

############################################
## enable resulting html compression

    #php_flag zlib.output_compression on

###########################################
# disable user agent verification to not break multiple image upload

    php_flag suhosin.session.cryptua off

###########################################
# turn off compatibility with PHP4 when dealing with objects

    php_flag zend.ze1_compatibility_mode Off

</IfModule>

<IfModule mod_security.c>
###########################################
# disable POST processing to not break multiple image upload

    SecFilterEngine Off
    SecFilterScanPOST Off
</IfModule>

<IfModule mod_deflate.c>

############################################
## enable apache served files compression
## http://developer.yahoo.com/performance/rules.html#gzip

    # Insert filter on all content
    ###SetOutputFilter DEFLATE
    # Insert filter on selected content types only
    #AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript

    # Netscape 4.x has some problems...
    #BrowserMatch ^Mozilla/4 gzip-only-text/html

    # Netscape 4.06-4.08 have some more problems
    #BrowserMatch ^Mozilla/4\.0[678] no-gzip

    # MSIE masquerades as Netscape, but it is fine
    #BrowserMatch \bMSIE !no-gzip !gzip-only-text/html

    # Don't compress images
    #SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png)$ no-gzip dont-vary

    # Make sure proxies don't deliver the wrong content
    #Header append Vary User-Agent env=!dont-vary

</IfModule>

<IfModule mod_ssl.c>

############################################
## make HTTPS env vars available for CGI mode

    SSLOptions StdEnvVars

</IfModule>

<IfModule mod_rewrite.c>

############################################
## enable rewrites

    Options +FollowSymLinks
    RewriteEngine on

############################################
## you can put here your magento root folder
## path relative to web root

    #RewriteBase /magento/

############################################
## uncomment next line to enable light API calls processing

#    RewriteRule ^api/([a-z][0-9a-z_]+)/?$ api.php?type=$1 [QSA,L]

############################################
## rewrite API2 calls to api.php (by now it is REST only)

    RewriteRule ^api/rest api.php?type=rest [QSA,L]

############################################
## workaround for HTTP authorization
## in CGI environment

    RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

############################################
## TRACE and TRACK HTTP methods disabled to prevent XSS attacks

    RewriteCond %{REQUEST_METHOD} ^TRAC[EK]
    RewriteRule .* - [L,R=405]

############################################
## redirect for mobile user agents

    #RewriteCond %{REQUEST_URI} !^/mobiledirectoryhere/.*$
    #RewriteCond %{HTTP_USER_AGENT} "android|blackberry|ipad|iphone|ipod|iemobile|opera mobile|palmos|webos|googlebot-mobile" [NC]
    #RewriteRule ^(.*)$ /mobiledirectoryhere/ [L,R=302]

############################################
## always send 404 on missing files in these folders

    RewriteCond %{REQUEST_URI} !^/(media|skin|js)/

############################################
## never rewrite for existing files, directories and links

    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_FILENAME} !-l

############################################
## rewrite everything else to index.php

    RewriteRule .* index.php [L]

</IfModule>


############################################
## Prevent character encoding issues from server overrides
## If you still have problems, use the second line instead

    AddDefaultCharset Off
    #AddDefaultCharset UTF-8

<IfModule mod_expires.c>

############################################
## Add default Expires header
## http://developer.yahoo.com/performance/rules.html#expires

    ExpiresDefault "access plus 1 year"

</IfModule>

############################################
## By default allow all access

    Order allow,deny
    Allow from all

###########################################
## Deny access to release notes to prevent disclosure of the installed Magento version

    <Files RELEASE_NOTES.txt>
        order allow,deny
        deny from all
    </Files>

############################################
## If running in cluster environment, uncomment this
## http://developer.yahoo.com/performance/rules.html#etags

    #FileETag none

EOF

}


function getMediaOrigHtaccess()
{
    if [[ ! -f "${MAGENTO_ROOT}/get.php" ]]
    then
        return;
    fi

    if [[ ! -f "${MAGENTO_ROOT}/media/.htaccess.merchant" && -e "${MAGENTO_ROOT}/media/.htaccess" ]]
    then
        mv "${MAGENTO_ROOT}/media/.htaccess" "${MAGENTO_ROOT}/media/.htaccess.merchant"
    fi

    mkdir -p "${MAGENTO_ROOT}/media"
    cat <<EOF > "${MAGENTO_ROOT}/media/.htaccess"
Options All -Indexes
<IfModule mod_php5.c>
php_flag engine 0
</IfModule>

AddHandler cgi-script .php .pl .py .jsp .asp .htm .shtml .sh .cgi
Options -ExecCGI

<IfModule mod_rewrite.c>

############################################
## enable rewrites

    Options +FollowSymLinks
    RewriteEngine on

############################################
## never rewrite for existing files
    RewriteCond %{REQUEST_FILENAME} !-f

############################################
## rewrite everything else to index.php

    RewriteRule .* ../get.php [L]
</IfModule>

EOF

}

function getOrigLocalXml()
{
    if [[ ! -f "${MAGENTO_ROOT}/app/etc/local.xml.merchant" && -f "${MAGENTO_ROOT}/app/etc/local.xml" ]]
    then
        mv "${MAGENTO_ROOT}/app/etc/local.xml" "${MAGENTO_ROOT}/app/etc/local.xml.merchant"
    fi

    getMerchantLocalXmlValues

    cat <<EOF > "${MAGENTO_ROOT}/app/etc/local.xml"
<?xml version="1.0"?>
<!--
/**
 * Magento
 *
 * NOTICE OF LICENSE
 *
 * This source file is subject to the Academic Free License (AFL 3.0)
 * that is bundled with this package in the file LICENSE_AFL.txt.
 * It is also available through the world-wide-web at this URL:
 * http://opensource.org/licenses/afl-3.0.php
 * If you did not receive a copy of the license and are unable to
 * obtain it through the world-wide-web, please send an email
 * to license@magentocommerce.com so we can send you a copy immediately.
 *
 * DISCLAIMER
 *
 * Do not edit or add to this file if you wish to upgrade Magento to newer
 * versions in the future. If you wish to customize Magento for your
 * needs please refer to http://www.magentocommerce.com for more information.
 *
 * @category   Mage
 * @package    Mage_Core
 * @copyright  Copyright (c) 2008 Irubin Consulting Inc. DBA Varien (http://www.varien.com)
 * @license    http://opensource.org/licenses/afl-3.0.php  Academic Free License (AFL 3.0)
 */
-->
<config>
    <global>
        <install>
            <date><![CDATA[${INSTALL_DATE}]]></date>
        </install>
        <crypt>
            <key><![CDATA[${CRYPT_KEY}]]></key>
        </crypt>
        <disable_local_modules>false</disable_local_modules>
        <resources>
            <db>
                <table_prefix><![CDATA[${TABLE_PREFIX}]]></table_prefix>
            </db>
            <default_setup>
                <connection>
                    <host><![CDATA[${DB_HOST}]]></host>
                    <username><![CDATA[${DB_USER}]]></username>
                    <password><![CDATA[${DB_PASS}]]></password>
                    <dbname><![CDATA[${DB_SCHEMA}]]></dbname>
                    <initStatements><![CDATA[SET NAMES utf8]]></initStatements>
                    <model><![CDATA[mysql4]]></model>
                    <type><![CDATA[pdo_mysql]]></type>
                    <pdoType><![CDATA[]]></pdoType>
                    <active>1</active>
                </connection>
            </default_setup>
        </resources>
        <session_save><![CDATA[files]]></session_save>
    </global>
    <admin>
        <routers>
            <adminhtml>
                <args>
                    <frontName><![CDATA[admin]]></frontName>
                </args>
            </adminhtml>
        </routers>
    </admin>
</config>

EOF

}

function getOrigEnterpriseXml()
{
    if [[ ! -f "${MAGENTO_ROOT}/app/etc/enterprise.xml.merchant" && -f "${MAGENTO_ROOT}/app/etc/enterprise.xml" ]]
    then
        mv "${MAGENTO_ROOT}/app/etc/enterprise.xml" "${MAGENTO_ROOT}/app/etc/enterprise.xml.merchant"
    fi

    cat <<EOF > "${MAGENTO_ROOT}/app/etc/enterprise.xml"
<?xml version='1.0' encoding="utf-8" ?>
<!--
/**
 * Magento Enterprise Edition
 *
 * NOTICE OF LICENSE
 *
 * This source file is subject to the Magento Enterprise Edition License
 * that is bundled with this package in the file LICENSE_EE.txt.
 * It is also available through the world-wide-web at this URL:
 * http://www.magentocommerce.com/license/enterprise-edition
 * If you did not receive a copy of the license and are unable to
 * obtain it through the world-wide-web, please send an email
 * to license@magentocommerce.com so we can send you a copy immediately.
 *
 * DISCLAIMER
 *
 * Do not edit or add to this file if you wish to upgrade Magento to newer
 * versions in the future. If you wish to customize Magento for your
 * needs please refer to http://www.magentocommerce.com for more information.
 *
 * @category    Enterprise
 * @copyright   Copyright (c) 2009 Irubin Consulting Inc. DBA Varien (http://www.varien.com)
 * @license     http://www.magentocommerce.com/license/enterprise-edition
 */
-->
<config>
    <global>
        <cache>
            <request_processors>
                <ee>Enterprise_PageCache_Model_Processor</ee>
            </request_processors>
            <frontend_options>
                <slab_size>1040000</slab_size>
            </frontend_options>
        </cache>
        <full_page_cache>
            <backend>Mage_Cache_Backend_File</backend>
            <backend_options>
                <cache_dir>full_page_cache</cache_dir>
            </backend_options>
        </full_page_cache>
        <skip_process_modules_updates>0</skip_process_modules_updates>
    </global>
</config>

EOF

}

function getOrigIndex()
{
    if [[ ! -f "${MAGENTO_ROOT}/index.php.merchant" && -f "${MAGENTO_ROOT}/index.php" ]]
    then
        mv "${MAGENTO_ROOT}/index.php" "${MAGENTO_ROOT}/index.php.merchant"
    fi

    cat <<INDEX_EOF > index.php
<?php
/**
 * Magento Enterprise Edition
 *
 * NOTICE OF LICENSE
 *
 * This source file is subject to the Magento Enterprise Edition End User License
 * Agreement that is bundled with this package in the file LICENSE_EE.txt.
 * It is also available through the world-wide-web at this URL:
 * http://www.magento.com/license/enterprise-edition
 * If you did not receive a copy of the license and are unable to
 * obtain it through the world-wide-web, please send an email
 * to license@magento.com so we can send you a copy immediately.
 *
 * DISCLAIMER
 *
 * Do not edit or add to this file if you wish to upgrade Magento to newer
 * versions in the future. If you wish to customize Magento for your
 * needs please refer to http://www.magento.com for more information.
 *
 * @category    Mage
 * @package     Mage
 * @copyright Copyright (c) 2006 Magento, Inc. and affiliates (http://www.magento.com)
 * @license http://www.magento.com/license/enterprise-edition
 */

if (version_compare(phpversion(), '5.3.0', '<')===true) {
    echo  '<div style="font:12px/1.35em arial, helvetica, sans-serif;">
<p>Magento supports PHP 5.3.0 or newer.
<a href="http://www.magentocommerce.com/install" target="">Find out</a> how to install</a>
 Magento using PHP-CGI as a work-around.</p></div>';
    exit;
}

/**
 * Error reporting
 */
error_reporting(E_ALL | E_STRICT);
ini_set('display_errors', 1);

/**
 * Compilation includes configuration file
 */
define('MAGENTO_ROOT', getcwd());

\$compilerConfig = MAGENTO_ROOT . '/includes/config.php';
if (file_exists(\$compilerConfig)) {
    include \$compilerConfig;
}

\$mageFilename = MAGENTO_ROOT . '/app/Mage.php';
\$maintenanceFile = 'maintenance.flag';

if (!file_exists(\$mageFilename)) {
    if (is_dir('downloader')) {
        header("Location: downloader");
    } else {
        echo \$mageFilename." was not found";
    }
    exit;
}

if (file_exists(\$maintenanceFile)) {
    include_once dirname(__FILE__) . '/errors/503.php';
    exit;
}

if (file_exists(MAGENTO_ROOT . '/app/bootstrap.php')) {
    include MAGENTO_ROOT . '/app/bootstrap.php';
}

require_once \$mageFilename;

// Varien_Profiler::enable();

// Mage::setIsDeveloperMode(true);

umask(0);

/* Store or website code */
\$mageRunCode = isset(\$_SERVER['MAGE_RUN_CODE']) ? \$_SERVER['MAGE_RUN_CODE'] : '';

/* Run store or run website */
\$mageRunType = isset(\$_SERVER['MAGE_RUN_TYPE']) ? \$_SERVER['MAGE_RUN_TYPE'] : 'store';

Mage::run(\$mageRunCode, \$mageRunType);

INDEX_EOF

}

function doFileReconfigure()
{
    printf 'Reconfiguring files.\n'

    getOrigHtaccess
    getMediaOrigHtaccess
    getOrigLocalXml
    getOrigEnterpriseXml
    getOrigIndex
}

####################################################################################################
function installOnly()
{
    if [[ -f "${MAGENTO_ROOT}/app/etc/local.xml" ]]
    then
        printf '\nMagento already installed, rm app/etc/local.xml file to reinstall\n\n' >&2
        exit 1;
    fi

    printf 'Performing Magento install.\n'

    mkdir -p "${MAGENTO_ROOT}/var/log/"
    chmod 2777 "${MAGENTO_ROOT}/var"
    chmod 2777 "${MAGENTO_ROOT}/var/log"
    touch "${MAGENTO_ROOT}/var/log/${EXCEPTION_LOG_NAME}"
    touch "${MAGENTO_ROOT}/var/log/${SYSTEM_LOG_NAME}"

    chmod 2777 "${MAGENTO_ROOT}/app/etc" "${MAGENTO_ROOT}/media"

    php -f install.php -- \
        --license_agreement_accepted yes \
        --locale $LOCALE_CODE \
        --timezone $TIMEZONE \
        --default_currency USD \
        --db_host $DB_HOST \
        --db_name $DB_SCHEMA \
        --db_user "$DB_USER" \
        --db_pass "$DB_PASS" \
        --url "$FULL_INSTANCE_URL" \
        --use_rewrites yes \
        --use_secure no \
        --secure_base_url $FULL_INSTANCE_URL \
        --use_secure_admin no \
        --skip_url_validation yes \
        --admin_firstname Store \
        --admin_lastname Owner \
        --admin_email $ADMIN_EMAIL \
        --admin_username "$ADMIN_USERNAME" \
        --admin_password "$ADMIN_PASSWORD"
}

####################################################################################################
function gitAdd()
{
    if [[ -e '.gitignore' ]]
    then
        mv -f .gitignore .gitignore.merchant
    fi

    cat <<GIT_IGNORE_EOF > .gitignore
/media/
/var/
/privatesales/
/.idea/
.svn/
*.gz
*.tgz
*.bz
*.bz2
*.tbz2
*.tbz
*.zip
*.tar
.DS_Store

GIT_IGNORE_EOF

    if [[ -e '.git' ]]
    then
        rm -rf .git.merchant
        mv -f .git .git.merchant
    fi

    git init >/dev/null 2>&1

    if [[ "$(uname)" = 'Darwin' ]]
    then
        FIND_REGEX_TYPE='find -E . -type f'
    else
        FIND_REGEX_TYPE='find . -type f -regextype posix-extended'
    fi

    $FIND_REGEX_TYPE ! -regex \
        '\./\.git/.*|\./media/.*|\./var/.*|.*\.svn/.*|\./\.idea/.*|.*\.gz|.*\.tgz|.*\.bz|.*\.bz2|.*\.tbz2|.*\.tbz|.*\.zip|.*\.tar|.*DS_Store' \
        -print0 | xargs -0 git add -f

    git commit -m 'initial merchant deployment' >/dev/null 2>&1
}


####################################################################################################
##  MAIN  ##########################################################################################
####################################################################################################

checkTools

####################################################################################################
# Set timezone default after checking for tools.
if [[ -z "$TIMEZONE" ]]
then
    TIMEZONE=$(php -r 'echo date_default_timezone_get();')
fi

# Read defaults from config file. They will overwrite corresponding variables.
# An additional config file, specified as a command option, will be read later.
if [[ -f "$CONFIG_FILE_PATH" ]]
then
    source "$CONFIG_FILE_PATH"
fi

####################################################################################################
#   Parse options and set environment.
OPTIONS=$(getopt \
    -o Hc:Frim:h:D:u:p:f:b:e:l:C \
    -l help,config-file:,force,reconfigure,install,mode:,host:,database:,user:,password:,full-instance-url:,email:,locale:,additional-configs: \
    -n "$0" -- "$@")

if [[ $? != 0 ]]
then
    printf '\nFailed parsing options.\n\n' >&2
    showHelp
    exit 1
fi

eval set -- "$OPTIONS"

while true; do
    case "$1" in
        -H|--help )                 showHelp; exit 0;;
        -c|--config-file )          OPT_CONFIG_FILE="$2"; shift 2;;
        -F|--force )                FORCE_RESTORE=1; shift 1;;
        -r|--reconfigure )          MODE='reconfigure'; shift 1;;
        -i|--install-only )         MODE='install-only'; shift 1;;
        -m|--mode )                 MODE="$2"; shift 2;;
        -h|--host )                 DB_HOST="$2"; shift 2;;
        -D|--database )             DB_SCHEMA="$2"; shift 2;;
        -u|--user )                 DB_USER="$2"; shift 2;;
        -p|--password )             DB_PASS="$2"; shift 2;;
        -f|--full-instance-url )    FULL_INSTANCE_URL="$2"; shift 2;;
        -e|--email )                ADMIN_EMAIL="$2"; shift 2;;
        -l|--locale )               LOCALE_CODE="$2"; shift 2;;
        --additional-configs )      CORE_CONFIG_FILE="$2"; shift 2;;
        -C )                        CORE_CONFIG_RUN=1; shift 1;;
        -- ) shift; break;;
        * ) printf 'Internal getopt parse error.\n\n'; showHelp; exit 1;;
    esac
done


####################################################################################################
# Execute.

# If doing this then do nothing else.
if [[ $CORE_CONFIG_RUN -gt 0 ]]
then
    additionalDbConfig
    exit 0
fi

# Catch bad modes before initializing variables.
case "$MODE" in
    reconfigure|install-only|git-wrap|reconfigure-code|reconfigure-db|code|db) ;;
    '') ;;
    *) printf 'Bad mode.\n\n'; showHelp; exit 1 ;;
esac

initVariables

case "$MODE" in
    # --reconfigure
    reconfigure)
        doFileReconfigure
        doDbReconfigure
        ;;

    # --install-only
    install-only)
        #comment out "createDb" if using sample data
        createDb
        installOnly
        doDbReconfigure
        # Add GIT repo if none exists, regular or worktree.
        if [[ ! -e '.git' ]]
        then
            printf 'Wrapping deployment with local-only git repository.\n'
            gitAdd
        fi
        ;;

    # --mode code
    code)
        extractCode
        doFileReconfigure
        # Add GIT repo if this is not a redo.
        if [[ ! -d '.git.merchant' ]]
        then
            printf 'Wrapping deployment with local-only git repository.\n'
            gitAdd
        fi
        ;;

    # --mode db
    db)
        createDb
        restoreDb
        doDbReconfigure
        ;;

    # --mode reconfigure-code
    reconfigure-code)
        doFileReconfigure
        ;;

    # --mode reconfigure-db
    reconfigure-db)
        doDbReconfigure
        ;;

    # --mode git-wrap
    git-wrap)
        gitAdd
        ;;

    # Empty "mode". Do everything.
    '')
        # create DB in background
        ( createDb ) &
        CHILD_PID="${CHILD_PID}$! "
        extractCode
        doFileReconfigure
        # create repository in background
        (
            # Add GIT repo if this is not a redo.
            if [[ ! -d '.git.merchant' ]]
            then
                gitAdd
            fi
        ) &
        CHILD_PID="${CHILD_PID}${!} "
        restoreDb
        doDbReconfigure
        ;;
esac

exit 0
