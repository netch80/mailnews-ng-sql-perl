#!/usr/bin/perl
## $Id: cmd.pl,v 1.45 2006/04/12 14:39:16 netch Exp $

## Called in pipe mode from sendmail.
## Gets letter with command on stdin and proceeds it.

use strict;

sub BEGIN {

  ## Add needed search paths according to environment set up by thunk.
  my $mn_prefix = $ENV{'MN_PREFIX'};
  if( $mn_prefix ) {
    unshift @INC, "$mn_prefix/lib/mailnews";
    unshift @INC, "$mn_prefix/etc";
  }

}

use Sys::Syslog qw( :DEFAULT setlogsock );
use DBI;
use News::NNTPClient;
use mn_config;
use mn_subs;
use mn_mime;
use mn_intl qw( i );

## Globals

my $nntp;               ## handle of nntp client connection
my $dbh;                ## handle of database client connection
my %active;             ## loaded active, hash: groupname -> info
my $flag_active_loaded; ## whether active is loaded
my $addr;               ## address of user sent the letter in question
my $addr_domain;        ## domain of $addr
## Header of letter in question, used in main
## and do_inject(). List of lines without terminating LF or CRLF
my @header;
my $uopt_suspended;     ## option for current user: whether suspended
my $uopt_lhelp;         ## option for current user: whether lhelp is on
my $uopt_newgrp;        ## option for current user: send new groups or not
my $dopt_disabled;     ## whether whole domain is disabled (admin option)
my $lang; 
my $charset;
my $mylocalpart;
my $myhdrfrom;
my $flag_xover_format_requested;
my $flag_has_xover_format;
my %xover_idx;

&main( @ARGV );

##############################################################3#
## main()

sub main {

  my( $f_eof, $hfield );
  my( $f_from, $f_reply, $f_sender, $f_msgid,
    $f_return, $f_fromsp, $f_subject, $f_groups, $l, $l0,
    $localpart, $tmps, $flag_ouruser, $ncmd, $ncmd_old,
    $currgroup, $cmd, $argline, $sth, $nline, $rc,
    $flag_seen_in_users, $flag_seen_in_domains );
  my( @tmpa );

  setlogsock( 'unix' );
  openlog( "${mn_config::cf_syslog_identity_prefix}/cmd",
      'pid', $mn_config::cf_syslog_facility );
  $nntp = 0;
  $dbh = 0;

  ## Parse command line.
  for $l ( @_ ) {
    if( $l =~ /^lang=/ ) { $lang = lc $'; }
    if( $l =~ /^mylocalpart=/ ) { $mylocalpart = $'; }
  }
  ## Define language and charset.
  ## Fixed charsets now; only koi-* for cyrillic
  $lang = {
      'rus' => 'ru',
      'ukr' => 'uk',
      'eng' => 'en'
      } -> {$lang}
      || $lang
      || 'ru';
  $charset = {
      'en' => 'us-ascii',
      'ru' => 'koi8-r',
      'uk' => 'koi8-u'
      } -> {$lang}
      || 'koi8-r';
  #-syslog( 'debug', 'main(): lang=%s charset=%s', $lang, $charset );
  ## set_intl() should be later

  ## Parse header
  $f_eof = 0;
  $hfield = $f_from = $f_reply = $f_sender = $f_return = $f_fromsp = "";
  $f_subject = $f_groups = "";
  @header = ();
  %active = ();
  $flag_active_loaded = 0;
  for(;;) {
    $l = <STDIN>;
    unless( defined $l ) { $f_eof = 1; $l = ""; }
    $l0 = $l;
    chomp $l;
    if( $l eq "" || $l !~ /^\s/ ) {
      ## Flush hfield
      $hfield =~ s/\n//g; ## delete all line separators as for rfc822
      if( $hfield =~ /^Subject:\s*/i ) { $f_subject = $'; }
      if( $hfield =~ /^Reply-To:\s*/i ) { $f_reply = $'; }
      if( $hfield =~ /^From:\s*/i ) { $f_from = $'; }
      if( $hfield =~ /^Sender:\s*/i ) { $f_sender = $'; }
      if( $hfield =~ /^Return-Path:\s*/i ) { $f_return = $'; }
      if( $hfield =~ /^Newsgroups:\s*/i ) { $f_groups = $'; }
      if( $hfield =~ /^Message-ID:\s*/i ) { $f_msgid = $'; }
      if( $hfield =~ /^From\s+/i ) {
        ##****
      }
      $hfield = "";
    }
    push @header, $l0;
    chomp $l; ## remove unneeded line separator
    last if $l eq ""; ## includes eof
    $hfield .= $l; ## without terminating "\n"
  }
  ## Detect user's address
  $addr = $f_reply || $f_from || $f_return || $f_sender || $f_fromsp;
  unless( $addr ) {
    ## ??
    syslog( 'notice', 'message without return address, drop it' );
    exit( 0 );
  }
  
  ## Convert address to canonical form. Requires rfc822 magic and perversions.
  ## Now use simplest rfc1036 case.
  $addr = &mn_subs::mn_strip_address( $addr );
  ## We don't allow address of too complex form
  if( $addr =~ /^-/ || $addr !~ /^[A-Za-z0-9._+-]+\@[A-Za-z0-9._-]+$/ ||
      length( $addr ) > 127 )
  {
    syslog( 'notice', 'address is too complex for us, rejecting: %s', $addr );
    exit(0);
  }
  @tmpa = split /\@/, $addr;
  if( $#tmpa != 1 ) {
    syslog( 'notice', 'address is too strange for us, rejecting: %s', $addr );
    exit(0);
  }
  $localpart = $tmpa[0];
  $addr_domain = lc $tmpa[1];
  $addr = $localpart . '@' . $addr_domain;
  if( defined @mn_config::bad_localparts ) {
    foreach $tmps( @mn_config::bad_localparts ) {
      if( lc $localpart eq lc $tmps ) {
        syslog( 'notice', 'address has prohibited local part: %s', $addr );
        exit(0);
      }
    }
  }
  
  ## Check address for valid and belong to our users
  ## XXX Now temporary workaround with explicit list. For future release,
  ## more flexible mechanism should be used.
  $flag_ouruser = 0;
  if( defined @mn_config::our_explicit_domains ) {
    foreach $tmps ( @mn_config::our_explicit_domains ) {
      if( $tmps eq $addr_domain ) { $flag_ouruser = 1; last; }
    }
  }
  
  ## For message with newgroups, inject it to news system
  if( $f_groups ) {
    unless( $flag_ouruser ) {
      syslog( 'notice', 'Rejected mail from $addr which is not our user' );
      exit( 0 );
    }
    &inject();
    ## NOTREACHED
    exit(1);
  }
  
  ## No newsgroup. Treat as command
  &mn_intl::set_intl( {
      lang => $lang,
      charset => $charset
      } );
  $myhdrfrom = $mn_config::cf_server_email ||
      ( 'newsserv@' . mn_gethostname() );
  if( $mylocalpart ) {
    die unless $myhdrfrom =~ /^.*@(.*)$/;
    $myhdrfrom = $mylocalpart . '@' . $1;
  }
  open( SM, sprintf( '|/usr/sbin/sendmail -f%s -oi -t',
        &mn_subs::shellparseable( ${mn_config::cf_server_errors_to} ) ) )
      or die "cannot open sendmail";
  print SM sprintf( "From: News Mailing Service <%s>\n",
      $myhdrfrom );
  print SM sprintf( "Errors-To: ${mn_config::cf_server_errors_to}\n" );
  print SM sprintf( "Sender: ${mn_config::cf_server_errors_to}\n" );
  print SM "To: $addr\n";
  #- print SM sprintf(
  #-     "Subject: Re: %s\n", $f_subject ? $f_subject : "your mail" );
  print SM "Subject: reply from USENET server\n";
  print SM "In-Reply-To: $f_msgid\n";
  print SM "References: $f_msgid\n";
  ## XXX Temporary MIME workaround
  print SM sprintf(
      "MIME-Version: 1.0\n" .
      "Content-Type: text/plain; charset=%s\n" .
      "Content-Transfer-Encoding: %s\n",
      $charset, ( $charset eq 'us-ascii' ? '7bit' : '8bit' ) );
  print SM "\n";
  print SM "Mail-News Gateway\n";
  print SM "Copyright (C) 2002 Valentin Nechayev <netch\@netch.kiev.ua>\n";
  print SM "\n";
  print SM sprintf( i('Result of query from <%s>'), $addr ),
      "\n";
  print SM "\n";
  unless( $flag_ouruser ) {
    print SM i('You are not our user. Functions are partially unavailable'),
        "\n";
  }
  
  $dbh = &dbhandle();
  die unless $dbh;
  ## Get options from database
  $sth = $dbh->prepare( 'SELECT suspended FROM domains WHERE domain=?' );
  die unless $sth;
  $rc = $sth->execute( $addr_domain );
  die unless $rc;
  die if $rc > 1;
  $dopt_disabled = 0;
  $flag_seen_in_domains = 0;
  if( $rc > 0 ) {
    ( $dopt_disabled ) = $sth->fetchrow_array();
    $flag_seen_in_domains = 1;
  }
  #- $sth->finish();
  $sth = $dbh->prepare( 'SELECT suspended,lhelp FROM users WHERE email=?' );
  die unless $sth;
  $rc = $sth->execute( $addr );
  die unless $rc;
  die if $rc > 1;
  $uopt_suspended = 0;
  $uopt_lhelp = 1;
  $flag_seen_in_users = 0;
  if( $rc > 0 ) {
    ( $uopt_suspended, $uopt_lhelp ) = $sth->fetchrow_array();
    $flag_seen_in_users = 1;
  }
  #- $sth->finish();
  if( $flag_ouruser && !$flag_seen_in_users ) {
    $sth = $dbh->prepare(
        'INSERT INTO users (email,domain,lang,lhelp,newgrp,suspended) ' .
        'VALUES (?,?,?,?,?,?)' );
    die unless $sth;
    $rc = $sth->execute( $addr, $addr_domain, 'rus', 1, 1, 0 );
    die unless $rc;
  }
  if( $flag_ouruser && !$flag_seen_in_domains ) {
    $sth = $dbh->prepare(
        'INSERT INTO domains (domain,suspended) VALUES(?,?)' );
    die unless $sth;
    $rc = $sth->execute( $addr_domain, 0 );
    die unless $rc;
  }

  ## Parse input. Unknown commands are silently ignored.
  $nline = $ncmd = $ncmd_old = 0;
  $currgroup = "";
  Command: while( !$f_eof )
  {
    $l = <STDIN>;
    unless( defined $l ) { $f_eof = 1; last; }
    ++$nline;
    chomp $l;
    #-print SM ">>>>> Seen line: $l\n";
    last Command if $l eq '-- '; ## standard signature start
    $l =~ s/\s+$//;
    if( $l =~ /^([A-za-z]\S*)\s*/ ) { $cmd = $1; $argline = $'; }
    else { next; }
    $cmd = lc $cmd;
    print SM "\n" unless $ncmd == $ncmd_old;
    $ncmd_old = $ncmd;
    last Command if( $cmd eq 'quit' || $cmd eq 'end' || $cmd eq 'exit' );
    if( $cmd eq 'help' ) {
      ## Help is allowed for anybody
      ++$ncmd;
      print SM ">>>HELP\n";
      &print_help();
      ## Traditional behavior: after HELP, rest of letter skipped
      last Command;
    }
    if( $cmd eq 'group' ) {
      ++$ncmd;
      $currgroup = $argline;
      print SM ">>>$cmd $argline\n";
      unless( $flag_ouruser ) {
        print SM i('FAILED: command is unavailable for you'),"\n";
        next Command;
      }
      if( $currgroup =~ /[ \t,]/ ) {
        print i('FAILED: group is incorrect. No selected group now.'),"\n";
        $currgroup = '';
      }
      ##**** Check that group exists
      ##****
    }
    if( $cmd eq 'art' || $cmd eq 'article' ) {
      ++$ncmd;
      print SM ">>>$cmd $argline\n";
      unless( $flag_ouruser ) {
        print SM i('FAILED: command is unavailable for you'),"\n";
        next Command;
      }
      &do_art( $argline, $currgroup );
    }
    if( $cmd eq 'feed' ||
        $cmd eq 'rfeed' ||
        $cmd eq 'subscribe' ||
        $cmd eq 'sub' ||
        $cmd eq 'subs' ||
        $cmd eq 'unsubscribe' ||
        $cmd eq 'unsub' ||
        $cmd eq 'unsubs' )
    {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      $cmd = 'unsubscribe' if $cmd eq 'unsub' || $cmd eq 'unsubs';
      $cmd = 'subscribe' if $cmd eq 'sub' || $cmd eq 'subs';
      if( !$flag_ouruser && $cmd ne 'unsubscribe' ) {
        print SM i('FAILED: command is unavailable for you'),"\n";
        next Command;
      }
      &subscribe_cmds( $addr, $cmd, $argline );
    }
    if( $cmd eq 'forget' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      &do_forget( $addr, lc($argline) eq "silent" );
    }
    if( $cmd eq 'scheck' || $cmd eq 'check' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      &do_check( $addr );
    }
    if( $cmd eq 'list' || $cmd eq 'ilist' || $cmd eq 'ulist' ) {
      my $listmode = 0;
      $listmode = 1 if $cmd eq 'ilist';
      $listmode = 2 if $cmd eq 'ulist';
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      unless( $flag_ouruser ) {
        print SM i('FAILED: command is unavailable for you'),"\n";
        next Command;
      }
      &do_list( $argline, $listmode );
    }
    if( $cmd eq 'index' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      unless( $flag_ouruser ) {
        print SM i('FAILED: command is unavailable for you'),"\n";
        next Command;
      }
      &do_index( $argline, $currgroup, $nline, $f_msgid );
    }
    if( $cmd eq 'suspend' || $cmd eq 'resume' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      ## Don't check for current state, apply command unconditionally.
      ## User can set conformed state of subs.suspended field of all
      ## his records via this command.
      $uopt_suspended = ( $cmd eq 'suspend' );
      $sth = $dbh->prepare( 'UPDATE users SET suspended=? WHERE email=?' );
      die unless $sth;
      $rc = $sth->execute( int( $uopt_suspended ), $addr );
      die unless $rc;
      $sth = $dbh->prepare( 'UPDATE subs SET suspended=? WHERE email=?' );
      die unless $sth;
      $rc = $sth->execute( int( $uopt_suspended || $dopt_disabled ), $addr );
      die unless $rc;
      if( $uopt_suspended ) {
        print SM i('Subscription is suspended'),"\n";
      }
      else {
        print SM i('Subscription is resumed'),"\n";
      }
    }
    if( $cmd eq 'lang' ) {
      $argline =~ s/\s+$//;
      my $lang = lc $argline;
      $lang = 'ru' if $lang eq 'rus';
      $lang = 'uk' if $lang eq 'ukr';
      $lang = 'en' if $lang eq 'eng';
      if( $lang ne 'ru' && $lang ne 'uk' && $lang ne 'ru' ) {
        print SM "ERROR: unknown language, change is not applied\n";
        next Command;
      }
      $sth = $dbh->prepare( 'UPDATE users SET lang=? WHERE email=?' );
      die unless $sth;
      $rc = $sth->execute( $lang, $addr );
      die unless $rc;
    }
    if( $cmd eq 'lhelp' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      $uopt_lhelp = ( lc $argline eq 'on' || $argline eq '1' ||
          lc $argline eq 'yes' || lc $argline eq 'y' );
      $rc = $dbh->do( 'UPDATE users SET lhelp=? WHERE email=?',
          $uopt_lhelp, $addr );
      die unless $rc;
      print SM i('Command succeeded'),"\n";
    }
    if( $cmd eq 'newgrp' ) {
      ++$ncmd;
      print SM ">>$cmd $argline\n";
      $uopt_newgrp = ( lc $argline eq 'on' || $argline eq '1' ||
          lc $argline eq 'yes' || lc $argline eq 'y' );
      $rc = $dbh->do( 'UPDATE users SET newgrp=? WHERE email=?',
          $uopt_newgrp, $addr );
      die unless $rc;
      print SM i('Command succeeded'),"\n";
    }
  }
  
  unless( $ncmd ) {
    print SM i('No command was recognized.'),"\n\n";
    &print_help() if $flag_ouruser;
    close( SM );
    exit( 0 );
  }
  
  print SM "\n", sprintf( i('%d command(s) recognized'), $ncmd ), "\n";
  close SM;
  exit( 0 );
}

################################################################
## subscribe_cmds()

sub subscribe_cmds {

  my( $addr, $smode, $argline ) = @_;
  my( $group, $rsize, $oldsmode, $oldrsize );
  my( $rc, $tmp, $sth );
  my @args;
  my @groups;

  $rsize = 0;
  if( $smode eq "rfeed" ) {
    if( $argline =~ /^(\d+)\s+/ ) { $rsize = $1; $argline = $'; }
    else {
      print SM i('FAILED: command is syntactically invalid'),"\n";
      return;
    }
  }
  print SM "_: subscribe_cmds: $addr $smode $rsize $argline\n";

  ## Get group list
  @args = split( /\s+/, $argline );
  @groups = &expand_group_list( @args );
  ## Find expanding errors
  while( $#groups >= 0 ) {
    $tmp = $groups[0];
    if( $tmp eq '-' ) { shift @groups; last; }
    if( $tmp =~ /^error:\s*/ ) {
      die sprintf( "expand_group_list() failed: %s", $' );
    }
    shift @groups;
  }
  print SM sprintf "_: subscribe_cmds: %d groups expanded\n", $#groups + 1;

  unless( $dbh ) {
    $dbh = &dbhandle();
    unless( $dbh ) {
      print SM sprintf(
          i('No connect to database: %s. Command failed.'),
          $dbh->errstr ), "\n";
      return;
    }
  }

  Group: foreach $group ( @groups ) {

    ## For subscribing, check group for existence.
    ## For unsubscribing, only existence in user subscription matters.
    if( $smode ne 'unsubscribe' ) {
      $rc = &check_group( $group );
      if( $rc ) {
        print SM sprintf(
            i('Subscription to %s failed due to: %s'), $group, $rc ),
            "\n";
        next Group;
      }
    }

    ## Get old params
    $oldsmode = '';
    $sth = $dbh->prepare(
        'SELECT smode,rsize FROM subs WHERE email=? AND groupname=?' );
    unless( $sth ) {
      print SM i('Cannot prepare command'),"\n";
      return;
    }
    $rc = $sth->execute( $addr, $group );
    if( $rc ) {
      ($oldsmode,$oldrsize) = $sth->fetchrow_array;
    }
    else {
      print SM i('Cannot get data from database'),"\n";
      return;
    }
    #- $sth->finish();
    $oldrsize = 0 unless $oldsmode eq "rfeed";
    if( $smode eq $oldsmode && $rsize == $oldrsize ) {
      print SM sprintf( i('Group %s: state is unchanged: %s%s'),
          $group, $smode, ( $smode eq 'rfeed' ? " $rsize" : '' ) ), "\n";
      next Group;
    }
    print SM sprintf(
        "_: subscribe_cmds: %s: %s %s -> %s %s\n",
        $group, ( $oldsmode || '-' ), $oldrsize, ( $smode || '-', $rsize ) );

    ## Proceed unsubscribe
    if( $smode eq 'unsubscribe' ) {
      $sth = $dbh->prepare(
          'DELETE FROM subs WHERE email=? AND groupname=?' );
      unless( $sth ) {
        print SM i('FAILED: cannot prepare command'),"\n";
        return;
      }
      $rc = $sth->execute( $addr, $group );
      unless( $rc ) {
        print SM i('Command failed: database failure'),"\n";
        #- $sth->finish();
        return;
      }
      #- $sth->finish();
      print SM i('Command succeeded'),"\n";
      next Group;
    }

    ## Proceed subscribe
    if( $oldsmode ) {
      $sth = $dbh->prepare(
        'UPDATE subs SET smode=?,rsize=? WHERE email=? AND groupname=?' );
      unless( $sth ) {
        print SM
            sprintf( i('Cannot prepare UPDATE: %s'), $dbh->errstr ),
            "\n";
        return;
      }
      $rc = $sth->execute( $smode, $rsize, $addr, $group );
      unless( $rc ) {
        print SM i('Cannot prepare UPDATE in database'),"\n";
        return;
      }
    }
    else {
      $sth = $dbh->prepare(
        'INSERT INTO subs (email,domain,groupname,smode,rsize,suspended) '.
        "\n" .
        "VALUES(?,?,?,?,?,?)" );
      unless( $sth ) {
        print SM
            sprintf( i('Cannot prepare INSERT: %s'), $dbh->errstr ),
            "\n";
        return;
      }
      $rc = $sth->execute( $addr, $addr_domain, $group, $smode, $rsize,
        int( $uopt_suspended || $dopt_disabled ) );
      unless( $rc ) {
        print SM sprintf(
           i('Cannot execute INSERT in database: %s'), $dbh->errstr ),
           "\n";
        return;
      }
    }
  } ## Group: foreach
  print SM i('Command succeeded'),"\n";
}

################################################################
## do_list()

sub do_list {
  my $arg = shift;
  my $listmode = shift;
  my @args;
  my %out;
  my( $group, $tmp );
  print SM "_: do_list: start: $addr $arg\n";
  unless( $flag_active_loaded ) {
    &load_active();
    unless( $flag_active_loaded ) {
      print SM i('Cannot get newsgroups list'),"\n";
      return;
    }
  }
  if( $arg eq '' ) {
    ## List top-level hierarchies
    %out = ();
    foreach $group ( keys %active ) {
      $tmp = $group; $tmp =~ s/\..*$//;
      $out{$tmp} = 0 unless defined $out{$tmp};
      ++$out{$tmp};
    }
    print SM i('Top-level hierarchies:'),"\n";
    foreach $tmp( sort keys %out ) {
      print SM sprintf( i('%s (%d groups)'), $tmp, $out{$tmp} ), "\n";
    }
    return;
  }
  ## List specific hierarchy
  ## XXX Add descriptions
  %out = ();
  foreach $group ( keys %active ) {
    if( $group =~ /^\Q$arg\E\./ ) { $out{$group} = 1; }
  }
  foreach $tmp ( sort keys %out ) {
    print SM "$tmp\n";
  }
}

################################################################
## do_index()

use vars qw(
    $index_flag_has_letter
    $index_n_ind_letter
    $index_n_ind_entries
    $index_narts_ind_letter
    $index_sz_ind_letter
    $index_flag_group_said
    );

sub do_index {
  my( $argline, $currgroup, $src_nline, $src_msgid ) = @_;
  my( $ts, $tmp, $i, $reply, $ts_art, $k, $l0, $l,
      $timespec, $timestart, 
      $group, $n, $g_first, $g_last,
      $ff_from, $ff_subject, $ff_date, $artsize );
  my( @args, @grouppats, @groups, @xover_format_flat, @xo_group, @xo_art,
      @arthead );
  local *IND;

  $timespec = -1;
  @args = split( /\s+/, $argline );
  ## Distinguish arguments: time period and group pattern specification
  foreach $tmp ( @args ) {
    if( $tmp =~ /^-/ ) { $timespec = &timespec_to_seconds( $' ); }
    else { push @grouppats, $tmp; }
  }
  if( @grouppats ) {
    @groups = &expand_group_list( @grouppats );
    while( $#groups >= 0 ) {
      $tmp = $groups[0];
      if( $tmp eq '-' ) { shift @groups; last; }
      if( $tmp =~ /^error:\s*/ ) {
        die sprintf( "expand_group_list() failed: %s", $' );
      }
      shift @groups;
    }
  }
  else {
    if( $currgroup ) {
      @groups = ( $currgroup );
    }
    else {
      print SM i('No selected group'),"\n";
      return;
    }
  }
  if( $timespec > 0 ) { $timestart = time() - $timespec; }
  else { $timestart = 1; }
  ## @groups contains only group names
  unless( $nntp ) {
    &open_nntp();
    unless( $nntp ) {
      print SM i('Cannot connect to server'),"\n";
      return;
    }
  }
  ## XXX Ugly: reads header of each article. Correct code should use
  ## only XOVER.
  unless( $flag_xover_format_requested ) {
    @xover_format_flat = $nntp->list( 'overview.fmt' );
    $flag_xover_format_requested = 1;
    if( $nntp->ok ) {
      $flag_has_xover_format = 1;
      for( $i = 0; $i <= $#xover_format_flat; ++$i ) {
        $ts = $xover_format_flat[$i];
        if( $ts =~ /^([^:]+):[^:]*$/ ) { $xover_idx{lc($1)} = $i; }
      }
      #-syslog( 'debug', 'xover keys: %s', join( ' ', sort keys %xover_idx ) );
    } else { $flag_has_xover_format = 0; }
    $flag_has_xover_format = 0 unless $xover_idx{'xref'};
  }
  $index_flag_has_letter = 0;
  $index_n_ind_letter = $index_n_ind_entries =
      $index_narts_ind_letter = $index_sz_ind_letter = 0;
  Group: foreach $group ( @groups ) {
    $index_flag_group_said = 0;
    ( $g_first, $g_last ) = $nntp->group( $group );
    #-syslog( 'debug', 'do_index(): group=%s g_first=%s g_last=%s',
    #-    $group, $g_first, $g_last );
    unless( $nntp->ok ) {
      $reply = sprintf( "%d %s", $nntp->code, $nntp->message );
      print SM sprintf( i('Group %s: %s'), $group, $reply ), "\n";
      next Group;
    }
    if( $flag_has_xover_format ) {
      @xo_group = $nntp->xover( $g_first, $g_last );
      goto PlainGroupRequest unless $nntp->ok;
      XoverArticle: for $ts ( @xo_group ) {
        @xo_art = split( /\t/, $ts );
        $n = shift @xo_art;
        $ff_from = $xo_art[$xover_idx{'from'}];
        $ff_subject = $xo_art[$xover_idx{'subject'}];
        $ff_date = $xo_art[$xover_idx{'date'}];
        $artsize = $xo_art[$xover_idx{'bytes'}] || '-';
        $ts_art = &mn_subs::parse_arpatime( $ff_date );
        #-syslog( 'debug', 'parse_arpatime returned %d on: %s',
        #-    $ts_art, $ff_date );
        #-syslog( 'debug', 'do_index(): xover: n=%d ts_art=%d ff_date="%s"',
        #-    $n, $ts, $ff_date );
        next XoverArticle
            if( $ts_art && $ts_art > 0 && $ts_art < $timestart );
        #-syslog( 'debug', 'do_index(): xover: n=%d: print it', $n );
        &index_print_article( {
            'group' => $group,
            'n' => $n,
            'ff_from' => $ff_from,
            'ff_subject' => $ff_subject,
            'ff_date' => $ff_date,
            'src_nline' => $src_nline,
            'src_msgid' => $src_msgid,
            'artsize' => $artsize
            } );
        #-syslog( 'debug', 'do_index(): xover: n=%d: printed it', $n );
      }
      goto ToNextGroup;
    }
    ## XXX Timespec now isn't used, full group list is sent.
    PlainGroupRequest: do {};
    Article: for( $n = $g_first; $n <= $g_last; ++$n ) {
      @arthead = $nntp->head( $n );
      push @arthead, ''; ## for terminator check in cycle
      ## Parse header
      $k = '';
      $ff_subject = $ff_from = $ff_date = '';
      foreach $l0 ( @arthead ) {
        $l = $l0; ## don't modify in array
        chomp $l; $l =~ s/\r$//;
        if( $l !~ /^\s/ ) {
          if( $k =~ /^Subject:\s*/i ) { $ff_subject = $'; }
          if( $k =~ /^From:\s*/ ) { $ff_from = $'; }
          if( $k =~ /^Date:\s*/ ) { $ff_date = $'; }
          $k = ''; 
        }
        last if $l eq '';
        $k .= $l;
      }
      $ts_art = &mn_subs::parse_arpatime( $ff_date );
      next Article if( $ts_art && $ts_art > 0 && $ts_art < $timestart );
      &index_print_article( {
          'group' => $group,
          'n' => $n,
          'ff_from' => $ff_from,
          'ff_subject' => $ff_subject,
          'ff_date' => $ff_date,
          'src_nline' => $src_nline,
          'src_msgid' => $src_msgid
          } );
    }
ToNextGroup:
    print IND "\n"; ## separate groups
  } ## Group: foreach $group
  if( $index_flag_has_letter ) {
    close IND;
    $index_flag_has_letter = 0;
  }
  print SM
      sprintf( i('Command succeeded, %d letters sent with %d records'),
          $index_n_ind_letter, $index_n_ind_entries ), "\n";
}

#####

sub index_print_article {
  my $params = shift;
  my $group = $params->{'group'};
  my $n = $params->{'n'};
  my $ff_from = $params->{'ff_from'};
  my $ff_subject = $params->{'ff_subject'};
  my $ff_date = $params->{'ff_date'};
  my $artsize = $params->{'artsize'};
  $artsize = '-' unless defined $artsize;
  my $src_nline = $params->{'src_nline'};
  my $src_msgid = $params->{'src_msgid'};
  my( $sendmail_cmd, $entry );
  ## We have article group, number, sender and subject. Print them.
  ## XXX We also need article size to report
  if( $index_sz_ind_letter >= 64000 || $index_narts_ind_letter >= 500 ) {
    close IND;
    $index_flag_has_letter = 0;
    $index_sz_ind_letter = $index_narts_ind_letter = 0;
  }
  if( !$index_flag_has_letter ) {
    $sendmail_cmd = sprintf( "/usr/sbin/sendmail -f%s -oi -t",
        &mn_subs::shellparseable( $mn_config::cf_server_errors_to ) );
    unless( open( IND, "|$sendmail_cmd" ) ) {
      print SM i('Cannot prepare new letter with index'),"\n";
      return;
    }
    ++$index_n_ind_letter;
    &mn_subs::mn_list_print_header( {
        'addr' => $addr,
        'handle' => \*IND,
        'flag_lister' => 0,
        'n_ind_letter' => $index_n_ind_letter,
        'src_nline' => $src_nline,
        'src_msgid' => $src_msgid,
        'charset' => $charset,
        'lhelp' => $uopt_lhelp
        } );
    $index_flag_group_said = 0;
    $index_sz_ind_letter = $index_narts_ind_letter = 0;
    $index_flag_has_letter = 1;
  }
  if( !$index_flag_group_said ) {
    print IND "GROUP $group\n";
    $index_flag_group_said = 1;
  }
  ++$index_n_ind_entries;
  ++$index_narts_ind_letter;
  $ff_subject = &mn_mime::decode_field(
      $ff_subject, { 'cp_dest' => $charset } );
  $entry = &mn_subs::mn_list_format_entry(
      $n, $artsize, $ff_from, $ff_subject );
  $index_sz_ind_letter += length( $entry );
  print IND $entry;
}

################################################################
## timespec_to_seconds()

sub timespec_to_seconds {
  my $ts = shift;
  my $nsec = 0;
  while( $ts ne '' ) {
    if( $ts =~ /^(\d+)w/ ) { $nsec += 604800 * $1; $ts = $'; next; }
    elsif( $ts =~ /^(\d+)d/ ) { $nsec += 86400 * $1; $ts = $'; next; }
    elsif( $ts =~ /^(\d+)h/ ) { $nsec += 3600 * $1; $ts = $'; next; }
    elsif( $ts =~ /^(\d+)m/ ) { $nsec += 60 * $1; $ts = $'; next; }
    elsif( $ts =~ /^(\d+)s/ ) { $nsec += $1; $ts = $'; next; }
    last;
  }
  return $nsec;
}

################################################################
## expand_group_list()
## Expands wildcard list on input to group list on output.
## Output is prepended with return code. '-' is delimiter.

sub expand_group_list {
  my @ret = qw( - );
  my %allow;
  my ( $desc, $r, $reg, $extg, $flag_wildcard, $flag_exclude );
  while( $#_ >= 0 ) {
    $desc = shift;
    $flag_wildcard = ( $desc =~ /[\[\]\*]/ );
    $flag_exclude = ( $desc =~ /^\!/ );
    if( $flag_exclude ) {
      $desc =~ s/^.//;
    }
    unless( $flag_wildcard || $flag_exclude ) {
      $allow{$desc} = 1;
      next;
    }
    if( !$flag_wildcard ) {
      delete $allow{$desc};
      next;
    }
    ## Wildcard case
    unless( $flag_active_loaded ) {
      &load_active();
      unless( $flag_active_loaded ) {
        unshift @ret, "error: load_active() failed";
        return @ret;
      }
    }
    $reg = &grouppat_to_regexp( $desc );
    for $extg( sort keys %active ) {
      ## XXX ugly. It recompiles regexp at each pass. Convert it to closure.
      if( $extg =~ /$reg/ ) { $allow{$extg} = 1; }
      else { delete $allow{$extg}; }
    }
  } ## iterate input
  foreach $r ( sort keys %allow ) {
    push @ret, $r if $allow{$r};
  }
  ## OK
  return @ret;
}

################################################################
## grouppat_to_regexp()

sub grouppat_to_regexp {
  my $arg = shift;
  return '.' if( lc($arg) eq 'all' || $arg eq '*' );
  return &wildmat_to_regexp( $arg );
}

################################################################
## wildmat_to_regexp()

sub wildmat_to_regexp {
  my $o = '^';
  my $i = shift;
  my $c;
  while( length $i > 0 ) {
    if( $i =~ /^\./ ) { $o .= "\\" . '.'; $i =~ s/^.//; next; }
    if( $i =~ /^\*/ ) { $o .= '.*'; $i =~ s/^.//; next; }
    if( $i =~ /^\?/ ) { $o .= '.'; $i =~ s/^.//; next; }
    if( $i =~ /^(\[[^\]]*\])/ ) { $o .= $&; $i = $'; next; }
    if( $i =~ /^([^\.\*\?\[])/ ) { $o .= $&; $i = $'; next; }
    ##???
    die;
  }
  $o .= '$';
  $o =~ s/^\^\.\*//;
  $o =~ s/\.\*\$$//;
  return $o;
}

################################################################
## check_group()
## false (empty string) on OK, true (error description) on error

sub check_group {
  my $group = shift;
  &open_nntp() unless( $nntp );
  unless( $nntp->group( $group ) ) {
    return sprintf( "%d %s", $nntp->code, $nntp->message );
  }
  return '';
}

################################################################
## do_forget()

sub do_forget {
  my $rc;
  my @row;
  my ( $group, $smode, $rsize );
  my $flag_silent = shift;
  my $sth;
  unless( $dbh ) {
    $dbh = &dbhandle();
    unless( $dbh ) {
      print SM sprintf(
          i('No connection with database: %s. Command failed'),
          $dbh->errstr ), "\n";
      return;
    }
  }
  unless( $flag_silent ) {
    $sth = $dbh->prepare(
        'SELECT groupname,smode,rsize FROM subs WHERE email=? ' .
        'ORDER BY groupname' );
    unless( $sth ) {
      print SM i('Cannot prepare command'),"\n";
      return;
    }
    $rc = $sth->execute( $addr );
    unless( $rc ) {
      print SM i('Command failed: database reject'),"\n";
      #- $sth->finish();
      return;
    }
    ##****
    while( @row = $sth->fetchrow_array ) {
      ($group,$smode,$rsize) = @row;
      print SM sprintf( i('Deleting: %s'), $smode );
      print SM " $rsize" if( $smode eq "rfeed" );
      print SM " $group\n";
    }
  }
  $sth = $dbh->prepare( 'DELETE from subs WHERE email=?' );
  die unless $sth;
  $rc = $sth->execute( $addr );
  unless( $rc ) {
    print SM sprintf(
        i('Command DELETE FROM subs failed: database reject: %s'),
         $dbh->errstr ), "\n";
    return;
  }
  $sth = $dbh->prepare( 'DELETE from users WHERE email=?' );
  die unless $sth;
  $rc = $sth->execute( $addr );
  unless( $rc ) {
    print SM sprintf(
        i('Command DELETE FROM users failed: database reject: %s'),
        $dbh->errstr ), "\n";
    return;
  }
  print SM i('Command succeeded'),"\n";
}

################################################################
## do_check()

sub do_check {
  my ( $groupname, $smode, $rsize );
  my $rc;
  my $addr = shift;
  my $sth;
  unless( $dbh ) { $dbh = &dbhandle(); }
  die unless $dbh;
  $sth = $dbh->prepare(
      'SELECT groupname,smode,rsize FROM subs ' .
      'WHERE email=? ORDER BY groupname' );
  die unless $sth;
  $rc = $sth->execute( $addr );
  die unless $rc;
  if( $rc == 0 ) {
    print SM i('Your subscription is empty'), "\n";
    return;
  }
  print SM i('Your subscription:'), "\n";
  print SM i('Subscription of the whole domain is suspended'), "\n"
      if( $dopt_disabled );
  print SM i('Subscription is suspended'), "\n" if( $uopt_suspended );
  print SM i('List headers are turned off'), "\n" if( !$uopt_lhelp );
  while( ( $groupname, $smode, $rsize ) = $sth->fetchrow_array ) {
    if( $smode eq 'rfeed' ) {
      print SM sprintf( "RFEED %d %s\n", $rsize, $groupname );
    } else {
      print SM sprintf( "%s %s\n", uc( $smode ), $groupname );
    }
  }
  #- $sth->finish();
}

################################################################

sub do_art {
  my $arg = shift;
  my $currgroup = shift;
  my $rc;
  my @a_hdr;
  my @a_body;
  my $reply;
  my $line;
  local *SM2;
  $arg =~ s/^\s+//; $arg =~ s/\s+$//;
  if( $arg !~ /^\d+$/ && $arg !~ /^\d+\s/ && $arg !~ /^<.*>$/ ) {
    print SM i('Command failed: incorrect parameter'), "\n";
    return;
  }
  ## If `ART n ...', delete all after number
  if( $arg =~ /^(\d+)\s/ ) {
    $arg = $1;
  }
  if( $arg =~ /^(\d+)$/ ) {
    if( !$currgroup ) {
      print SM i('No selected group. Command failed'), "\n";
      return;
    }
  }
  unless( $nntp ) {
    &open_nntp();
    unless( $nntp ) {
      print SM i('Command failed: no connection to server'), "\n";
      return;
    }
  }
  if( $arg =~ /^\d+$/ ) {
    $rc = $nntp->group( $currgroup );
    $reply = sprintf( '%d %s', $nntp->code, $nntp->message );
    unless( $rc ) {
      print SM
          sprintf( i('Command failed: group was not recognized: %s'),
          $reply ), "\n";
      return;
    }
  }
  @a_hdr = $nntp->head( $arg );
  $reply = sprintf( '%d %s', $nntp->code, $nntp->message );
  unless( $nntp->code =~ /^2/ ) {
    print SM sprintf(
        i('Command failed: header request rejected: %s'),
        $reply ), "\n";
    return;
  }
  @a_body = $nntp->body( $arg );
  $reply = sprintf( '%d %s', $nntp->code, $nntp->message );
  unless( $nntp->code =~ /^2/ ) {
    print SM sprintf(
        i('Command failed: body request rejected: %s'),
        $reply ), "\n";
    return;
  }
  unless( open( SM2, sprintf( '|/usr/sbin/sendmail -oi -oee -- %s',
      &mn_subs::shellparseable( $addr ) ) ) )
  {
    print SM i('Command failed'), "\n";
    return;
  }
  foreach $_ ( @a_hdr ) {
    $line = $_;
    if( $line =~ /^Subject:\s+/i ) { $line = 'Subject: [NEWS] ' . $'; }
    print SM2 $line;
  }
  print SM2 "\n";
  print SM2 @a_body;
  close SM2;
  print SM i('Command succeeded'), "\n";
}

################################################################
## inject()

sub inject {
  my( $rc, $reason, $flag_skip, $ts, $l );
  my( @body, @h1 );
  unless( $nntp ) {
    &open_nntp();
    unless( $nntp ) {
      print SM i('Command failed: no connection to server'), "\n";
      return;
    }
  }
  ## Process header
  @h1 = ();
  for $l ( @header ) {
    if( $l !~ /^\s/ ) {
      $flag_skip = 0;
      $flag_skip = 1 if( $l =~ /^>*From /i );
      $flag_skip = 1 if( $l =~ /^to:/i );
      $flag_skip = 1 if( $l =~ /^received:/i );
      $flag_skip = 1 if( $l =~ /^return-path:/i );
    }
    push @h1, $l unless $flag_skip;
  }
  ## $nntp->post accepts list of lines, each line can be either terminated
  ## with "\n" or not terminated, function strips terminator and adds own
  ## one
  @body = <STDIN>;
  $rc = $nntp->post( @h1, "", @body );
  $reason = sprintf( "%d %s", $nntp->code, $nntp->message );
  if( !$rc ) {
    open( SM, "|/usr/sbin/sendmail -oi -t" ) or die;
    print SM "To: $addr\n";
    print SM "Subject: your article was rejected\n";
    print SM sprintf( "From: News Mailing Service <%s>\n",
        $mn_config::cf_server_errors_to );
    print SM "\n";
    print SM "Reason: $reason\n";
    close SM;
    exit(1);
  }
  exit(0);
}

################################################################
## load_active()

sub load_active {
  my @list;
  my( $line, $group, $info );
  unless( $nntp ) {
    &open_nntp();
    return unless $nntp;
  }
  @list = $nntp->list( 'active' );
  return unless $nntp->ok;
  %active = ();
  foreach $line ( @list ) {
    chomp $line; $line =~ s/\r$//;
    if( $line =~ /^(\S+?)\s+/ ) {
      $group = $1; $info = $';
      $active{$group} = $info;
    }
  }
  $flag_active_loaded = 1;
}

################################################################
## open_nntp()

sub open_nntp {
  ## XXX Use simple default variant now
  $nntp = new News::NNTPClient( 'localhost' );
  return unless( $nntp );
  $nntp->fourdigityear(1);
  $nntp->mode_reader();
}

################################################################
## print_help()

sub print_help {
  local *HELP;
  my $h;
  my $mn_prefix = $ENV{'MN_PREFIX'};
  if( open( HELP, "$mn_prefix/lib/mailnews/helpfile" ) ) {
    while( defined( $h = <HELP> ) ) {
      print SM $h;
    }
    close( HELP );
  }
  else {
    print SM i('Help is temporary unavailable'), "\n";
  }
}

################################################################
## dbhandle()

sub dbhandle {
  return DBI->connect( 'dbi:mysql:mailnews',
      $mn_config::cf_db_cmd_user,
      $mn_config::cf_db_cmd_password,
      {AutoCommit=>1} );
}
