#!/bin/sh
## Variables from command line cannot contain shell metacharacters!
## Otherwise behavior of scripts is unpredictable.
## You are warned.
OWNER="$1"
GROUP="$2"
PERL="$3"
PREFIX="$4"
PROGRAM="$5"
set -e
(
echo \#\!/bin/sh
## Provide default $PATH if doesn't exist.
## Add /bin to end of existing $PATH. This is to satisfy Sys::Syslog
## which wants hostname to be run to obtain host name.
## Possibly it isn't needed now but real testing isn't available yet.
echo 'if test -z "$PATH"; then'
echo '  PATH=/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin'
echo 'else'
echo '  PATH="$PATH":/bin'
echo 'fi'
echo export PATH
echo MN_PREFIX=$PREFIX; export MN_PREFIX
echo PERL=$PERL; export PERL
echo exec $PERL -I $PREFIX/etc -I $PREFIX/lib/mailnews \
	$PREFIX/lib/mailnews/$PROGRAM.pl \"\$\@\"
) >$PREFIX/bin/$PROGRAM
chown $OWNER:$GROUP $PREFIX/bin/$PROGRAM
chmod 750 $PREFIX/bin/$PROGRAM
