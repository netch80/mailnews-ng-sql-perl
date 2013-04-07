#!/usr/bin/perl
## $Id: newgrp.pl,v 1.2 2006/04/13 15:05:02 netch Exp $

## newgrp is called once per week and send notifications for new groups.

use strict;

sub BEGIN {

  my $mn_prefix;
  if( ( $mn_prefix = $ENV{'MN_PREFIX'} ) ) {
    unshift @INC, "$mn_prefix/lib/mailnews", "$mn_prefix/etc";
  }

}

use DBI;
use Fcntl ':flock';
use Sys::Syslog qw( :DEFAULT setlogsock );
use mn_config;
use mn_subs;
use mn_intl;

&main();
## UNREACHED
die;

my $dbh;
my $sth;
my $rc;

################################################################
## main()

sub main {

  my @row;
  my %oldgroups = ();
  my %newgroups = ();
  my( $q, $oldgroup, $email, $group );

  setlogsock('unix');
  
  ## Get lock. If we can't get lock, exit immediately
  #- print STDERR "Try to open: $mn_config::cf_lister_lock_path\n";
  open( LOCK, ">>$mn_config::cf_newgrp_lock_path" ) ||
      die 'cannot open lock';
  unless( flock( LOCK, LOCK_EX|LOCK_NB ) ) {
    syslog( 'notice', 'Another lock is in action' );
    exit(0);
  }
  
  $dbh = &dbhandle();
  die 'cannot connect to database!' unless $dbh;

  ## We have two sources for newsgroup list: current INN's list and
  ## last recorded our internal list.
  ## Action: compare lists; new additions in INN's list shall be
  ## mailed to users unless they denied such lists; groups removed from
  ## INN's list shall be silently removed from our list.
  local *ACTIVE;
  open( ACTIVE, "/usr/local/news/db/active" ) ## XXX configurable name!!!
    or die "cannot open active!";
  $sth = $dbh->prepare('SELECT * from newsgroups');
  die unless $sth;
  $rc = $sth->execute();
  die unless $rc;
  while( (@row = $sth->fetchrow_array()) ) {
    $oldgroups{$row[0]} = 1;
  }
  while( defined( $q = <ACTIVE> ) ) {
    my @qq;
    chomp $q; @qq = split(/\s+/, $q); $q = $qq[0];
    if( !exists $oldgroups{$q} ) {
      $newgroups{$q} = 1;
    }
    delete $oldgroups{$q};
  }
  close( ACTIVE ) or die;
  ## Delete old groups
  $sth = $dbh->prepare( 'DELETE FROM newsgroups WHERE groupname=?' );
  die unless $sth;
  for $oldgroup ( keys %oldgroups ) {
    $rc = $sth->execute($oldgroup);
    die unless $rc;
  }

  ## Send new groups
  $sth = $dbh->prepare( 'SELECT email FROM users WHERE newgrp=1' );
  die unless $sth;
  $rc = $sth->execute();
  die unless $rc;
  while( ( @row = $sth->fetchrow_array() ) ) {
    $email = $row[0];
    local *SM;
    my $sendmail_cmd;
    $sendmail_cmd = sprintf( "/usr/sbin/sendmail -f%s -oi -t -odq -oee",
        &mn_subs::shellparseable( $mn_config::cf_server_errors_to ) );
    open( SM, "|$sendmail_cmd" ) or die;
    &mn_subs::mn_newgrp_print_header( {
      'addr' => $email,
      'handle' => \*MAIL,
      'lang' => 'en' ## XXX
    } );
    for $group ( keys %newgroups ) {
      print SM $group, "\n";
    }
    close( SM );
  }

  ## Add new groups to list
  $sth = $dbh->prepare( 'INSERT INTO newsgroups VALUES (?)' );
  die unless $sth;
  for $group ( keys %newgroups ) {
    $rc = $sth->execute( $group );
    die unless $rc;
  }
  
  $dbh->disconnect();
  exit(0);

}

################################################################
## dbhandle()

sub dbhandle {
  return DBI->connect(
      $mn_config::cf_db_handler,
      $mn_config::cf_db_lister_user,
      $mn_config::cf_db_lister_password,
      {AutoCommit=>1} );
}
