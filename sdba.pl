#!/usr/bin/perl
## $Id: sdba.pl,v 1.9 2006/04/13 14:40:18 netch Exp $

## sdba.pl - analog of sdba command of old mailnews server

use strict;

sub BEGIN {
  ## Add needed search paths according to environment set up by thunk.
  my $mn_prefix;
  if( ( $mn_prefix = $ENV{'MN_PREFIX'} ) ) {
    unshift @INC, "$mn_prefix/lib/mailnews", "$mn_prefix/etc";
  }
}

use DBI;
use mn_config;
use mn_subs;

## Globals
my $dbh;                         ## database connect handle

&main( @ARGV );

##############################################################3#
## main()

sub main {
  if( $#_ < 0 || $0 eq 'help' ) {
    print 'usage: sdba command [parameters]',"\n";
    print "Available commands are:\n";
    print "check_domain_empty      - check for domains without subscribers\n";
    print "check_group_need        - print list of needed groups\n";
    print "disable_domain <domain> - disable domain\n";
    print "disable_user <user>     - disable user\n";
    print "enable_domain <domain>  - enable domain (not separate users)\n";
    print "enable_user <user>      - enable user\n";
    print "help                    - print this message\n";
  }
  ## When add new commands, please sort entries lexicografically.
  ## But, help should be last.
  ## XXX not all old sdba commands are supported yet ;-|
  if( $_[0] eq 'check_domain_empty' ) {
    &check_domain_empty();
    exit(0);
  }
  if( $_[0] eq 'check_group_need' ) {
    &check_group_need();
    exit(0);
  }
  if( $_[0] eq 'disable_domain' ) {
    die 'sdba: usage: domain needed!' unless $#_>=1;
    &enable_domain( $_[1], 0 );
    exit(0);
  }
  if( $_[0] eq 'disable_user' ) {
    die 'sdba: usage: user needed!' unless $#_>=1;
    &enable_user( $_[1], 0 );
    exit(0);
  }
  if( $_[0] eq 'enable_domain' ) {
    die 'sdba: usage: domain needed!' unless $#_>=1;
    &enable_domain( $_[1], 1 );
    exit(0);
  }
  if( $_[0] eq 'enable_user' ) {
    die 'sdba: usage: user needed!' unless $#_>=1;
    &enable_user( $_[1], 1 );
    exit(0);
  }
  if( $_[0] eq 'rmuser' ) {
    die "sdba: rmuser: usage: no user\n" unless $_[1];
    &rmuser( $_[1] );
    exit(0);
  }
  die 'sdba: unknown command!';
}

################################################################
## check_domain_empty()

sub check_domain_empty {
  my( $sth, $rc, $domain );
  my %domains;
  unless( $dbh ) {
    $dbh = &dbhandle();
    die unless $dbh;
  }
  ## Really we proceed here simple set subtraction operation.
  $sth = $dbh->prepare( 'SELECT domain FROM domains' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute();
  die $dbh->errstr unless $rc;
  while( ( $domain ) = $sth->fetchrow_array ) {
    $domains{$domain} = 1;
  }
  $sth = $dbh->prepare( 'SELECT DISTINCT domain FROM users' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute();
  die $dbh->errstr unless $rc;
  while( ( $domain ) = $sth->fetchrow_array ) {
    delete $domains{$domain};
  }
  for $domain ( sort keys %domains ) {
    print "$domain\n";
  }
}

################################################################
## check_group_need()

sub check_group_need {
  my( $sth, $rc, $group );
  unless( $dbh ) {
    $dbh = &dbhandle();
    die unless $dbh;
  }
  $sth = $dbh->prepare(
      'SELECT DISTINCT groupname FROM subs ' .
      'WHERE NOT suspended ORDER BY groupname' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute();
  die $dbh->errstr unless $rc;
  while( ( $group ) = $sth->fetchrow_array ) {
    print "$group\n";
  }
}

################################################################
## enable_domain()

sub enable_domain {
  my( $domain, $enable ) = @_;
  my( $sth, $rc );
  $dbh = &dbhandle() unless $dbh;
  die 'database connection failed!' unless $dbh;
  $sth = $dbh->prepare( 'UPDATE domains SET suspended=?' );
  die unless $sth;
  $rc = $sth->do( $domain, $enable );
  die unless $rc;
}

################################################################
## enable_user()

sub enable_user {
  my( $user, $enable ) = @_;
  my( $sth, $rc );
  $dbh = &dbhandle() unless $dbh;
  die 'database connection failed!' unless $dbh;
  $sth = $dbh->prepare( 'UPDATE users SET suspended=?' );
  die unless $sth;
  $rc = $sth->do( $user, $enable );
  die unless $rc;
}

################################################################
## rmuser()

sub rmuser {
  my $user = shift;
  my( $sth, $rc );
  unless( $dbh ) {
    $dbh = &dbhandle();
    die unless $dbh;
  }
  $sth = $dbh->prepare( 'DELETE FROM subs WHERE email=?' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute( $user );
  die $dbh->errstr unless $rc;
  $sth = $dbh->prepare( 'DELETE FROM users WHERE email=?' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute( $user );
  die $dbh->errstr unless $rc;
  $sth = $dbh->prepare( 'DELETE FROM list WHERE email=?' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute( $user );
  die $dbh->errstr unless $rc;
}

################################################################
## dbhandle()

sub dbhandle {
  return DBI->connect( 'dbi:mysql:mailnews',
      $mn_config::cf_db_sdba_user,
      $mn_config::cf_db_sdba_password,
      {AutoCommit=>1} );
}
