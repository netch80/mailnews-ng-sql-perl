#!/usr/bin/perl
## $Id: feeder.pl,v 1.36 2002/07/15 14:44:01 netch Exp $

## Feeder is called as innd/innfeed feeding target, as direct command
## or (preferrable) from inetd. It talks as NNTP server which can only
## accept feed.
## Many feeders can run simultaneously; this increases database load,
## but can't cause any inconsistence.

use strict;

sub BEGIN {

  my $mn_prefix;
  if( ( $mn_prefix = $ENV{'MN_PREFIX'} ) ) {
    unshift @INC, "$mn_prefix/lib/mailnews", "$mn_prefix/etc";
  }

}

use DBI;
use Sys::Syslog qw( :DEFAULT setlogsock );
use mn_config;
use mn_mime;
## Socket is for smtp sender
use Socket qw( :DEFAULT );
use IO::Handle;

## Globals
my $dbh;                      ## handle of connection (DBI) to database
my %feed_users;               ## hash of users to be fed with article
my %list_users;               ## hash of users to receive notify
my @header;                   ## header of article to be fed or listed
my @body;                     ## body of article to be fed or listed
my $artsize;                  ## size of article, in bytes
my %cache_expire;             ## expiration times per group
my %cache_feed;               ## cached feed users per group
my %cache_list;               ## cached list users per group

setlogsock( 'unix' );
openlog( "${mn_config::cf_syslog_identity_prefix}/feeder",
    'pid', $mn_config::cf_syslog_facility );
eval {
  local $SIG{__WARN__} = \&on_warn;
  &main( @ARGV );
  ## UNREACHED unless died
};
$_ = $@; chomp;
syslog( 'err', 'main() failed: %s', $_ );
exit( 1 );

################################################################
## on_warn()

sub on_warn {
  local $SIG{__WARN__} = sub {};
  syslog( 'warn', 'warning from perl: %s', $_[0] );
}

################################################################
## main()

sub main {

  my( $l, $stream_msgid );


  $dbh = "";
  #$smtp = "";
  #$smtp_nsend = 0;

  $| = 1;

  print "200 ok\r\n";
  syslog 'info', 'started';

  for(;;) {
    $l = <STDIN>;
    unless( defined $l ) {
      syslog( 'notice', 'feeder closed connection without quit' );
      exit(1);
    }
    chomp $l;
    $l =~ s/\r$//;
    syslog 'debug', 'got command: %s', $l;
    if( $l =~ /^quit$/i ) {
      print "205 goodbye\r\n";
      exit(0);
    }
    elsif( $l =~ /^mode\s+stream$/i ) {
      ## Ready for streaming
      print "203 streaming ok\r\n";
      next;
    }
    elsif( $l =~ /^check\s+/i ) {
      $stream_msgid = $';
      print "238 $'\r\n";
      next;
    }
    elsif( $l =~ /^takethis\s+/i ) {
      $stream_msgid = $';
      &proceed_article($stream_msgid);
    }
    elsif( $l =~ /^ihave\s+/i ) {
      print "335 send it\r\n";
      &proceed_article('');
    }
    ## Unknown command
    else {
      print "500 unknown command\r\n";
    }
  }
}

################################################################
## proceed_article()
## get article from stdin (dot-stuffed) and proceed it

sub proceed_article {
  my $stream_msgid = shift;
  my( $l, $f_end, $hfield, $f_groups, $f_xref, $f_subject, $f_from,
      $f_msgid, $f_control, $sth );
  my( $rc, $i, $iu, $ig );
  my( @groups, @tmp1 );
  my %xrefs;
  @header = ();
  $f_end = 0;
  $hfield = "";
  $f_groups = $f_msgid = '';
  $artsize = 0;
  ## read header
  for(;;) {
    $l = <STDIN>;
    unless( defined $l ) {
      syslog( 'err', 'premature end of connection from feeder' );
      exit(1);
    }
    $artsize += length $l;
    chomp $l;
    $l =~ s/\r$//;
    if( $l eq '.' ) {
      $f_end = 1;
      $l = "";
    }
    if( $l =~ /^\./ ) { $l = substr( $l, 1 ); }
    push @header, $l; ## push without terminating LF or CRLF
    unless( $l =~ /^\s/ ) {
      ## Parse hfield. We need: newsgroups: - for local goals;
      ## sender, subject - for listing
      if( $l =~ /^Newsgroups:\s*/i ) {
        $f_groups = $';
      }
      ## We need X-Ref to get article numbers. X-Ref is preferred to XRef.
      elsif( $l =~ /^X-Ref:\s*/i || $l =~ /^XRef:\s*/i ) {
        $f_xref = $' if( $l =~ /^X-Ref:\s*/i || !$f_xref );
      }
      elsif( $l =~ /^Subject:\s*/i ) { $f_subject = $'; }
      elsif( $l =~ /^From:\s*/i ) { $f_from = $'; }
      elsif( $l =~ /^Message-ID:\s*/i ) { $f_msgid = $'; }
      elsif( $l =~ /^Control:\s*/i ) { $f_control = $'; }
      $hfield = "";
    }
    last if $f_end || $l eq "";
    $hfield .= $l; ## without line separators
  } ## forever - read header
  ## Convert $f_from to address-only form. XXX ugly
  if( $f_from =~ /<\s*(.*)\s*>/ ) { $f_from = $1; }
  if( $f_from =~ /\s*\(.*\)\s*$/ ) { $f_from = $`; }
  ## Read body to memory. We must read it to know article size.
  @body = ();
  while( !$f_end ) {
    $l = <STDIN>;
    unless( defined $l ) {
      syslog( 'err', 'premature end of connection from feeder' );
      exit(1);
    }
    $artsize += length $l;
    chomp $l;
    $l =~ s/\r$//;
    if( $l eq '.' ) { $f_end = 1; last; }
    if( $l =~ /^\./ ) { $l = substr( $l, 1 ); }
    push @body, $l;
  }
  $f_end = 1;
  if( $f_control ) {
    ## Get groups from xref. Unless xref, reject.
    $f_xref =~ s/^\s+//; $f_xref =~ s/\s+$//;
    @groups = split( /\s+/, $f_xref );
    foreach $i ( @groups ) { $i =~ s/:.*$//; }
    unless( @groups ) {
      if( $stream_msgid ) { print "439 $stream_msgid\r\n"; }
      else { print "437 rejected: control and no x-ref\r\n"; }
      return;
    }
  }
  else {
    $f_groups =~ s/^[ \t,]+//;
    $f_groups =~ s/[ \t,]+$//;
    @groups = split( /[ \t,]+/, $f_groups );
  }
  unless( $f_msgid ) {
    syslog 'err', 'Message without msgid, rejected';
    if( $stream_msgid ) { print "439 $stream_msgid\r\n"; }
    else { print "437 rejected: no newsgroups\r\n"; }
    return;
  }
  syslog 'debug', 'artsize=%d', $artsize;
  syslog 'debug', 'Parsing message with msgid: %s', $f_msgid;
  syslog 'debug', 'X-Ref: %s', $f_xref;
  unless( @groups ) {
    if( $stream_msgid ) { print "439 $stream_msgid\r\n"; }
    else { print "437 rejected: no newsgroups\r\n"; }
    syslog 'err', 'Message rejected: no newsgroups';
    return;
  }
  %feed_users = ();
  %list_users = ();
  unless( &find_users( $artsize, @groups ) ) {
    syslog 'err', "proceed_article(): find_users() failed\n";
    if( $stream_msgid ) { print "439 $stream_msgid\r\n"; }
    else { print "436 Try again later\r\n"; }
    return;
  }
  unless( %feed_users || %list_users ) {
    syslog( 'debug', 'proceed_article() finished: no users' );
    if( $stream_msgid ) { print "439 $stream_msgid\r\n"; }
    else { print "437 unwanted\r\n"; }
    return;
  }
  syslog( 'debug', 'proceed_article(): feed_users: %s',
      join( ' ', sort keys %feed_users ) );
  syslog( 'debug', 'proceed_article(): list_users: %s',
      join( ' ', sort keys %list_users ) );
  if( %feed_users ) {
    &feed_it();
  }
  if( %list_users )
  {
    ## Parse X-Ref
    syslog 'debug', 'list_users: %s', join( ' ', sort keys %list_users );
    @tmp1 = split( /[ \t,]+/, $f_xref );
    %xrefs = ();
    foreach $i( @tmp1 ) {
      if( $i =~ /^([^:]+):(\d+)$/ ) {
        $xrefs{$1} = $2;
        syslog 'debug', 'parsed x-ref %s:%d', $1, $2;
      }
    }
    ## Add to lister log.
    ## INSERT IGNORE is MySQL feature: fail without error condition if
    ## row duplicates existing one with the same primary key.
    $f_subject = &mn_mime::decode_field(
        $f_subject, { 'cp_dest' => 'utf-8' } );
    syslog( 'debug', 'decoded subject: %s', $f_subject );
    $sth = $dbh->prepare(
        'INSERT into list ' .
        '(email,groupname,artnum,size,sender,subject) ' .
        'values(?,?,?,?,?,?)' );
    if( $sth ) {
      foreach $iu( keys %list_users ) {
        foreach $ig( keys %xrefs ) {
          syslog 'debug', 'adding to list: user=%s group=%s',
              $iu, $ig;
          $rc = $sth->execute( $iu, $ig, $xrefs{$ig},
              $artsize, $f_from, $f_subject );
          unless( $rc ) {
            syslog 'err', 'adding to list failed: %s', $dbh->errstr;
          }
        }
      }
      #- $sth->finish();
    } else {
      syslog( 'err', 'Cannot prepare lister insert' );
    }
    %xrefs = ();
  }
  syslog( 'debug', 'proceed_article() finished' );
  if( $stream_msgid ) { print "239 $stream_msgid\r\n"; }
  else { print "235 ok\r\n"; }
}

################################################################
## feed_it()

## uses globals: @header, @body, %feed_users
## SMTP connection logic is complicated. All this should quicken sending.

my $smtp;
my $smtp_nsent;
my $smtp_maxnsent;
my $smtp_need_rset;
my %smtp_hp_try;
my %smtp_dampen_host;
my %smtp_dampen_inaddr;
my $smtp_conn_host;
my $smtp_conn_port;
my $smtp_conn_ip;

sub feed_it {

  my( $u, $cmd, $inaddr, $rc, $rcode, $rtext, $rcpt, $line, $ts,
      $hp, $host, $port, $server_tries, $curtime, $flag_sent_some );
  my( @ta, @hostent, @inaddrs );
  my( %rcpts_sent );

  return unless %feed_users;
  foreach $u ( keys %feed_users ) {
    syslog 'debug', "feed_it(): feed article to $u\n";
  }
  ## Reuse existing connection if exists
  goto Connected if $smtp;

Unconnected:

  ## Reload servers hash if it is empty
  $server_tries = 0 if( !%smtp_hp_try );
  if( !%smtp_hp_try && @mn_config::cf_smtp_servers ) {
    for $hp ( @mn_config::cf_smtp_servers ) {
      $smtp_hp_try{$hp} = 1;
      ++$server_tries;
    }
  }
  if( !%smtp_hp_try && $mn_config::cf_smtp_server ) {
    $smtp_hp_try{$mn_config::cf_smtp_server} = 1;
    ++$server_tries;
  }
  unless( %smtp_hp_try ) {
    syslog 'notice', "feed_it(): smtp_servers aren't sent";
    goto SendViaSendmail;
  }

  ## Find most preferrable server in hash.
  ## XXX This works really strange and I ain't sure it is correct
  unless( $server_tries ) {
    syslog( 'notice', 'feed_it(): SMTP server tries exhausted' );
    goto SendViaSendmail;
  }
  --$server_tries;
  @ta = sort {
          ( $mn_config::smtp_hp_pref{$b} || 0 ) <=>
          ( $mn_config::smtp_hp_pref{$a} || 0 )
      } keys %smtp_hp_try;
  die unless @ta;
  $hp = $ta[0];
  die unless $hp; ## save from empty but defined
  syslog( 'debug', 'selected server: %s', $hp );
  delete $smtp_hp_try{$hp};
  if( $hp =~ /:/ ) {
    $host = $`;
    $port = $';
  }
  else {
    $host = $hp;
    $port = 25;
  }
  $curtime = time();
  if( exists $smtp_dampen_host{$host} &&
      $smtp_dampen_host{$host} >= $curtime )
  {
    syslog( 'notice', 'feed_it(): skip host %s: dampened', $host );
    goto Unconnected;
  }
  @hostent = ();
  if( $host =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ ) {
    $inaddr = inet_aton( $host );
    unless( defined $inaddr ) {
      syslog 'notice', 'feed_it(): inet_aton() failed';
      goto SendViaSendmail;
    }
    @inaddrs = ( $inaddr );
  }
  else {
    undef $inaddr;
    eval {
      local $SIG{ALRM} = \&on_alarm_die;
      alarm( $mn_config::cf_smtp_timo_resolv || 20 );
      @hostent = gethostbyname( $host );
      alarm(0);
    };
    if( $@ ) {
      syslog( 'notice', 'feed_it(): gethostbyname() timed out' );
      $smtp_dampen_host{$host} = time() +
          ( $mn_config::cf_smtp_timo_dampen_host || 120 );
      goto Unconnected;
    }
    unless( @hostent ) {
      syslog( 'notice', 'feed_it(): gethostbyname() failed: %s', $? );
      $smtp_dampen_host{$host} = time() +
          ( $mn_config::cf_smtp_timo_dampen_host || 120 );
      goto Unconnected;
    }
    ( undef, undef, undef, undef, @inaddrs ) = @hostent;
  }
  for $inaddr ( @inaddrs ) {
    syslog( 'debug', 'feed_it(): hp=%s: connect to [%s]:%s',
        $hp, inet_ntoa( $inaddr ), $port );
    $smtp = new IO::Handle;
    die unless $smtp;
    $smtp->autoflush(1);
    socket( $smtp, PF_INET, SOCK_STREAM, 0 ) or die;
    eval {
      alarm(0);
      local $SIG{ALRM} = \&on_alarm_die;
      alarm( $mn_config::cf_smtp_timo_connect || 60 );
      connect( $smtp, pack_sockaddr_in( $port, $inaddr ) )
          or die "connect: $!\n";
      alarm( $mn_config::cf_smtp_timo_banner || 60 );
      ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
      die "Banner is not 220\n" unless( $rcode == 220 );
      alarm( $mn_config::cf_smtp_timo_helo || 60 );
      print $smtp sprintf( "HELO %s\r\n", 'localhost' ); ## XXX
      ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
      ## Note that die's here will be caught by eval{}
      die "HELO rejected\n" unless $rcode >= 200 && $rcode <= 299;
    };
    $rc = $@;
    if( $rc ) {
      undef $smtp;
      chomp $rc;
      syslog( 'notice', 'feed_it(): connect to %s[%s]:%s failed: %s',
          $host, inet_ntoa( $inaddr ), $port, $rc );
      $smtp_dampen_inaddr{$inaddr} =
          time() + ( $mn_config::cf_smtp_timo_dampen_inaddr || 300 );
    }
    last if $smtp;
    $smtp_conn_ip = $inaddr;
  }
  unless( $smtp ) {
    syslog( 'notice', 'feed_it(): all connects to %s failed', $hp );
    goto Unconnected;
  }
  $smtp_need_rset = 0;
  $smtp_nsent = 0;
  $smtp_maxnsent = $mn_config::cf_smtp_maxnsent{$hp} ||
      $mn_config::cf_smtp_maxnsent || 300;
  $smtp_conn_host = $host;
  $smtp_conn_port = $port;

Connected:
  $flag_sent_some = 0;
  if( $smtp_nsent >= $smtp_maxnsent ) {
    syslog( 'debug', 'feed_it(): smtp_nmaxsent is over, reconnecting' );
    ## Say quit. Ignore any errors.
    eval {
      alarm(0);
      local $SIG{ALRM} = \&on_alarm_die;
      alarm( $mn_config::cf_smtp_timo_quit || 10 );
      print $smtp "QUIT\r\n";
      &smtp_get_reply( $smtp );
    };
    undef $smtp;
    goto Unconnected;
  }
  ## Have $smtp connected and prepared
  if( $smtp_need_rset ) {
    eval {
      alarm(0);
      local $SIG{ALRM} = \&on_alarm_die;
      alarm( $mn_config::cf_smtp_timo_rset || 60 );
      print $smtp "RSET\r\n";
      ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
      die "RSET rejected\n" unless $rcode >= 200 && $rcode <= 299;
    };
    $rc = $@;
    if( $rc ) {
      chomp $rc;
      syslog 'notice', 'RSET rejected: %s', $rc;
      undef $smtp;
      goto Unconnected;
    }
    $smtp_need_rset = 0;
  }

  ## MAIL FROM
  eval {
    alarm(0);
    local $SIG{ALRM} = \&on_alarm_die;
    alarm( $mn_config::cf_smtp_timo_mailfrom || 60 );
    print $smtp sprintf( "MAIL FROM:<%s>\r\n",
        $mn_config::cf_server_errors_to );
    ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
    die "MAIL_FROM rejected\n" unless $rcode >= 200 && $rcode <= 299;
  };
  $rc = $@;
  if( $rc ) {
    chomp $rc;
    syslog 'notice', 'MAIL_FROM rejected: %s', $rc;
    undef $smtp;
    goto SendViaSendmail;
  }
  $smtp_need_rset = 1;
  syslog( 'debug', 'feed_it(): said mail from, ok' );
  ++$smtp_nsent;

  ## RCPT TO
  %rcpts_sent = ();
  for $rcpt ( keys %feed_users )
  {
    ## Send recipient and check it is adopted by server.
    ## For now, all answers expect 2xx leads to send the same via
    ## sendmail, and them check mailed bounces.
    eval {
      alarm(0);
      local $SIG{ALRM} = \&on_alarm_die;
      alarm( $mn_config::cf_smtp_timo_rcptto || 60 );
      print $smtp sprintf( "RCPT TO:<%s>\r\n", $rcpt );
      ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
      die "Protocol error\n" unless( $rc && $rcode >= 200 && $rcode <= 599 );
      if( $rcode >= 200 && $rcode <= 299 ) {
        $rcpts_sent{$rcpt} = 1;
      }
    };
    $rc = $@;
    if( $rc ) {
      chomp $rc;
      if( $rc eq 'Protocol error' ) {
        undef $smtp;
        syslog( 'notice', 'feed_it(): protocol error on rcpt to' );
        goto Unconnected;
      }
      ## Otherwise, protocol is ok, but command is rejected
      syslog 'notice', 'RCPT_TO rejected: %s', $rc;
    }
  }

  ## Check that >=1 rcpt was adopted
  unless( %rcpts_sent ) {
    syslog( 'notice', 'feed_it(): no recipients accepted on SMTP' );
    goto SendViaSendmail;
  }

  ## Send data
  eval {
    alarm(0);
    local $SIG{ALRM} = \&on_alarm_die;
    alarm( $mn_config::cf_smtp_timo_data || 120 );
    print $smtp "data\r\n";
    ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
    if( !$rc || $rcode != 354 ) {
      syslog 'notice', 'feed_it(): incorrect reply to DATA';
      die "DATA failed\n";
    }
    foreach $_ ( @header ) {
      $line = $_;
      #chomp $line; $line =~ s/\r$//;
      if( $line =~ /^Subject:\s*/ ) {
        $line = 'Subject: [NEWS] ' . $';
      }
      print $smtp sprintf( "%s%s\r\n",
          ( $line =~ /^\./ ) ? '.' : '',
          $line );
    }
    print $smtp "\r\n";
    foreach $line ( @body ) {
      print $smtp sprintf( "%s%s\r\n",
          ( $line =~ /^\./ ) ? '.' : '',
          $line );
    }
    alarm(0);
  };
  $rc = $@;
  if( $rc ) {
    chomp $rc;
    syslog( 'notice', 'feed_it(): DATA (data) failed: %s', $rc );
    undef $smtp;
    goto Unconnected;
  }
  ## Data final. Timeout should be as large as possible, otherwise
  ## dubbing probability increases.
  eval {
    alarm(0);
    local $SIG{ALRM} = \&on_alarm_die;
    alarm( $mn_config::cf_smtp_timo_datafinal || 900 );
    print $smtp ".\r\n"; ## finish mail
    ($rc,$rcode,$rtext) = &smtp_get_reply( $smtp );
    alarm(0);
    unless( $rc && $rcode >= 200 && $rcode <= 599 ) {
      ## Protocol error
      syslog( 'notice', 'feed_it(): protocol error during data final phase' );
      undef $smtp;
      goto Unconnected;
    }
    ## If accepted, exclude users from %feed_users.
    ## Otherwise left them to next attempt.
    if( $rcode >= 200 && $rcode <= 299 ) {
      for $ts ( keys %rcpts_sent ) { delete $feed_users{$ts}; }
      $flag_sent_some = 1;
    }
  };
  $rc = $@;
  if( $rc ) {
    chomp $rc;
    syslog( 'notice', 'feed_it(): DATA failed: %s', $rc );
    undef $smtp;
    goto Unconnected;
  }
  return unless %feed_users;

  ## We have some recipients, and previous iteration gave some recipients
  ## sent. Do next attempt.
  ## XXX This will be transformed in another form: send to sendmail only
  ## such recipients which were rejected not due to overload.
  goto Connected if( $flag_sent_some );

SendViaSendmail:
  ## This is fallback variant. To decrease load during send,
  ## we call sendmail with -odq. This should be configurable later.
  syslog( 'debug', 'feed_it(): send it via sendmail command' );
  return unless %feed_users;
  $cmd = sprintf( '/usr/sbin/sendmail -oi -oee -odq -f%s --',
      &mn_subs::shellparseable( $mn_config::cf_server_errors_to ) );
  for $u ( keys %feed_users ) {
    $cmd .= ' ' . &mn_subs::shellparseable( $u );
  }
  unless( open( SM, "|$cmd" ) ) {
    syslog( 'err', 'feeding failed: cannot start sendmail' );
    return;
  }
  syslog 'debug', "sendmail opened\n";
  foreach $_ ( @header ) {
    $line = $_;
    chomp $line; $line =~ s/\r$//;
    if( $line =~ /^Subject:\s*/ ) {
      $line = 'Subject: [NEWS] ' . $';
    }
    print SM "$line\n";
  }
  print SM "\n";
  foreach $_ ( @body ) {
    print SM "$_\n";
  }
  close SM;
  syslog 'debug', "sendmail closed\n";
}

################################################################
## smtp_get_reply()
## Uses timeouts defined in calling routines

sub smtp_get_reply {
  my $h = shift;
  my $crlf = "\015\012";
  my( $line, $rcode, $rtext );
  my @lines;
  $rtext = '';
  for(;;) {
    $line = <$h>;
    unless( defined $line ) {
      syslog( 'notice', 'smtp_get_reply(): connection closed by remote' );
      return ( 0, 0, '' );
    }
    $line =~ s/\Q$crlf\E$//;
    syslog( 'debug', 'smtp_get_reply(): got line: %s', $line );
    if( $line =~ /^\d{3}-/ ) {
      ## Not last line of multiline response
      push @lines, $line;
      $rtext .= $' . ' ';
      next;
    }
    elsif( $line =~ /^(\d{3})$/ || $line =~ /^(\d{3})\s/ ) {
      $rcode = $1;
      $rtext .= $';
      return ( 1, $rcode, $rtext );
    }
    ## Otherwise simply skip line...
  }
}

################################################################
## find_users(): check users for the group list in cache
## or in mysql base
## Cache hold time is now statically set to 600 (10min)

sub find_users {
  my( $rc, $group, $sth, $an_feed, $an_list );
  my ($email,$smode,$rsize);
  my $artsize = shift;
  my $currtime;
  ## @_ is group list
  unless( $dbh ) {
    $dbh = &dbhandle();
    return 0 unless( $dbh );
  }
  $sth = $dbh->prepare(
      'SELECT email,smode,rsize FROM subs '.
      'WHERE groupname=? AND NOT suspended' );
  unless( $sth ) {
    return 0;
  }
  %feed_users = ();
  %list_users = ();
  $currtime = time();
  Group: foreach $group( @_ ) {
    if( 0 )
    #if( defined $cache_expire{$group} && $cache_expire{$group} < $currtime )
    {
      syslog( 'debug', 'find_users(): reuse cache' );
      $an_feed = $cache_feed{$group};
      $an_list = $cache_list{$group};
      foreach $email ( keys %$an_feed ) {
        $feed_users{$email} = 1;
        delete $list_users{$email};
        syslog( 'debug', 'add to cache: feed %s to %s', $group, $email );
      }
      foreach $email ( keys %$an_list ) {
        $list_users{$email} = 1 unless $feed_users{$email};
        syslog( 'debug', 'add to cache: list %s to %s', $group, $email );
      }
      next Group;
    }
    delete $cache_feed{$group};
    delete $cache_list{$group};
    delete $cache_expire{$group};
    $an_feed = {};
    $an_list = {};
    $rc = $sth->execute( $group );
    unless( $rc ) {
      syslog( 'notice', "find_users: SELECT failed: %s",
          $dbh->errstr );
      return 0;
    }
    while( ($email,$smode,$rsize) = $sth->fetchrow_array )
    {
      syslog( 'debug', 'find_users(): in cycle 2: %s %s %s %s',
          $group, $email, $smode, $rsize );
      if( $smode eq "feed" ||
          ( $smode eq "rfeed" && $artsize <= $rsize*1000 ) )
      {
        syslog( 'debug', 'setting feed %s to %s', $group, $email );
        $feed_users{$email} = 1;
        delete $list_users{$email};
        $an_feed->{$email} = 1;
      }
      elsif( !$feed_users{$email} && (
           $smode eq 'rfeed' || $smode eq "subscribe" ) )
      {
        syslog( 'debug', 'setting list %s to %s', $group, $email );
        $list_users{$email} = 1;
        $an_list->{$email} = 1;
      }
    } ## iterate select reply lines
    #$cache_feed{$group} = $an_feed;
    #$cache_list{$group} = $an_list;
    #$cache_expire{$group} = $currtime + 600;
    %cache_expire = ();
  } ## iterate groups
  #- $sth->finish();
  return 1;
}

################################################################
## dbhandle()

sub dbhandle {
  return DBI->connect(
      $mn_config::cf_db_handler,
      $mn_config::cf_db_feeder_user,
      $mn_config::cf_db_feeder_password,
      {AutoCommit=>1} );
}

################################################################
## on_alarm_die()

sub on_alarm_die {
  die "alarm\n";
}
