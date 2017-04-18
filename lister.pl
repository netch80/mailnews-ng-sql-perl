#!/usr/bin/perl
## $Id: lister.pl,v 1.23 2006/04/13 14:39:41 netch Exp $

## Lister is called periodically from cron and send notifications for
## new articles to users

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

## lister reads list of notifications, groups it per user and sends
## these notifications

&main();
## UNREACHED
die;

################################################################
## main()

sub main {

  ## make `use strict' happy
  my( $dbh, $rc, $sth, $sth2, $user, $mail_started, $groupname, $artnum,
    $size, $sender, $subject, $arts_shown, $sendmail_cmd, $currgroup,
    $sz_list_now, $entry, $uopt_lhelp, $uopt_lang );
  my @row;
  my %users;

  setlogsock('unix');

  ## Get lock. If we can't get lock, exit immediately
  #- print STDERR "Try to open: $mn_config::cf_lister_lock_path\n";
  open( LOCK, ">>$mn_config::cf_lister_lock_path" ) ||
      die 'cannot open lock';
  unless( flock( LOCK, LOCK_EX|LOCK_NB ) ) {
    syslog( 'notice', 'Another lock is in action' );
    exit(0);
  }

  $dbh = &dbhandle();
  die unless $dbh;

  ## Tag all current data with our tag.
  ## All records added by feeder will have tag 0.
  ## We work only with records retagged by lister. Together with lock for
  ## lister, this keeps constant set of records during all this work.
  $rc = $dbh->do( 'UPDATE list SET tag=1' );
  die unless $rc;

  ## Select users
  $sth = $dbh->prepare( 'SELECT DISTINCT email FROM list WHERE tag=1' );
  die $dbh->errstr unless $sth;
  $rc = $sth->execute();
  die $dbh->errstr unless $rc;
  exit(0) if $rc == 0;
  %users = ();
  while( ( @row = $sth->fetchrow_array ) ) {
    $user = $row[0];
    $users{$user} = 1;
  }
  #- $sth->finish();

  ## Iterate users
  $sth = $dbh->prepare(
      'SELECT groupname,artnum,size,sender,subject FROM list ' .
      'WHERE email=? AND tag=1 ORDER BY concat(groupname,artnum)' );
  die unless $sth;
  $sth2 = $dbh->prepare( 'SELECT lhelp,lang FROM users WHERE email=?' );
  die unless $sth2;
  foreach $user ( sort keys %users ) {
    $uopt_lhelp = 1;
    $rc = $sth2->execute( $user );
    die $dbh->errstr unless $rc;
    die if $rc > 1;
    if( $rc > 0 ) {
      ( $uopt_lhelp, $uopt_lang ) = $sth2->fetchrow_array;
    }
    $rc = $sth->execute( $user );
    die $dbh->errstr unless $rc;
    $mail_started = $sz_list_now = 0;
    while( $rc > 0 && ( @row = $sth->fetchrow_array ) ) {
      ($groupname,$artnum,$size,$sender,$subject) = @row;
      if( $mail_started && ( $arts_shown >= 500 || $sz_list_now >= 64000 ) )
      {
        ## Close current letter and set flag to begin new one
        close MAIL;
        $mail_started = 0;
      }
      if( !$mail_started ) {
        $sendmail_cmd = sprintf( "/usr/sbin/sendmail -f%s -oi -t -odq -oee",
            &mn_subs::shellparseable( $mn_config::cf_server_errors_to ) );
        open( MAIL, "|$sendmail_cmd" ) or die;
        &mn_subs::mn_list_print_header( {
            'addr' => $user,
            'handle' => \*MAIL,
            'flag_lister' => 1,
            'lhelp' => $uopt_lhelp,
            'lang' => $uopt_lang
            } );
        $mail_started = 1;
        $arts_shown = $sz_list_now = 0;
        $currgroup = "";
      }
      if( $currgroup ne $groupname ) {
        print MAIL "\n" if $currgroup;
        print MAIL "GROUP $groupname\n";
        $currgroup = $groupname;
      }
      ## Print article annotation. Only 'new' format as for old mailnews
      $subject = &mn_intl::convert_cp( $subject, 'utf-8', 'koi8-u' );
      $entry = &mn_subs::mn_list_format_entry(
          $artnum, $size, $sender, $subject );
      $sz_list_now += length( $entry );
      print MAIL $entry;
    }
    if( $mail_started ) {
      close MAIL;
    }
    ## As info for this user is sent, delete it from base
    $sth = $dbh->prepare( 'DELETE FROM list WHERE email=? AND tag=1' );
    die $dbh->errstr unless $sth;
    $rc = $sth->execute( $user );
    die $dbh->errstr unless $rc;
  }
  $sth->finish();
  $sth2->finish();

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
