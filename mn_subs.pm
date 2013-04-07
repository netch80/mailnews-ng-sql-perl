#!/usr/bin/perl

package mn_subs;
use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw(Exporter);
@EXPORT_OK = qw( i );

use POSIX;
use strict;
use mn_config;

my $english_months = {
    'jan' => 1,
    'feb' => 2,
    'mar' => 3,
    'apr' => 4,
    'may' => 5,
    'jun' => 6,
    'jul' => 7,
    'aug' => 8,
    'sep' => 9,
    'oct' => 10,
    'nov' => 11,
    'dec' => 12
};

## Return TRUE
return 1;

################################################################
## mn_list_print_header()

sub mn_list_print_header {
  my( $parms, $addr, $handle, $flag_lister, $flag_lhelp, $n_ind_letter,
      $src_nline, $src_msgid, $lang, $lhelp_text );
  $parms = shift;
  $addr = $parms->{'addr'};
  $handle = $parms->{'handle'};
  $flag_lister = $parms->{'flag_lister'};
  $flag_lhelp = 1;
  $flag_lhelp = $parms->{'lhelp'} if defined $parms->{'lhelp'};
  $lang = $parms->{'lang'} || 'ru';
  my $charset = $parms->{'charset'} || 'koi8-u';
  unless( $flag_lister ) {
    $n_ind_letter = $parms->{'n_ind_letter'} || 0;
    $src_nline = $parms->{'src_nline'} || 0;
    $src_msgid = $parms->{'src_msgid'} || '';
  }
  if( $flag_lister ) {
    print $handle "Subject: List of new USENET articles\n";
  }
  else {
    print $handle "Subject: List of available USENET articles\n";
  }
  print $handle sprintf( "From: News Mailing Service <%s>\n",
      $mn_config::cf_server_email );
  print $handle "To: $addr\n";
  print $handle "X-Class: slow\n";
  print $handle "Precedence: junk\n";
  print $handle "Errors-To: ${mn_config::cf_server_errors_to}\n";
  ## XXX Temporary MIME workaround
  print $handle "MIME-Version: 1.0\n";
  print $handle sprintf( "Content-Type: text/plain; charset=%s\n",
     $charset );
  print $handle sprintf( "Content-Transfer-Encoding: %s\n",
      ( lc $charset eq 'us-ascii' ? '7bit' : '8bit' ) );
  print $handle "\n";
  unless( $flag_lister ) {
    print $handle
        sprintf( i('Letter %s with list in reply to request:'),
            $n_ind_letter ),
        "\n",
        sprintf( i('line %d, letter %s'), $src_nline, $src_msgid ),
        "\n";
  }
  if( $flag_lhelp && $lang eq 'ru' ) {
    ## Default text
    $lhelp_text =
        "#    To order articles remove -' from the first column of\n".
        "#   corresponding lines and ".
        "send the list back to \${mn_config::cf_server_email}.";
    ## XXX Eval test
    ## XXX Change text for used language
    print $handle $lhelp_text, "\n";
  }
}

################################################################
## mn_list_format_entry()

sub mn_list_format_entry {
  my( $artnum, $size, $sender, $subject ) = @_;
  my $o;
  $o .= sprintf( "-ART %5d %s %s\n",
          $artnum,
          &mn_list_printable_size( $size ),
          $sender );
  if( $subject ) {
    ## XXX De-MIME subject
    $subject = substr( $subject, 0, 255 );
    while( $subject ne '' ) {
      $o .= sprintf( ">    %s\n", substr( $subject, 0, 60 ) );
      $subject = ( length $subject > 60 ) ? substr( $subject, 60 ) : '';
    }
  }
  return $o;
}

################################################################
## mn_list_printable_size()
## Fit size to 4 characters

sub mn_list_printable_size {
  my $size = shift;
  my $q;
  return '   -' if( $size eq '' || $size < 0 );
  return sprintf( '%4d', $size ) if( $size < 10000 );
  return sprintf( '%3dK', int( $size / 1024 ) ) if( $size < 1000000 );
  return '****';
}

################################################################
## mn_newgrp_print_header()

sub mn_newgrp_print_header {
  my( $parms, $addr, $handle, $lang, $charset );
  $parms = shift;
  $addr = $parms->{'addr'};
  $handle = $parms->{'handle'};
  $lang = $parms->{'lang'} || 'ru';
  my $charset = $parms->{'charset'} || 'koi8-u';
  print $handle "Subject: List of new USENET groups\n";
  print $handle sprintf( "From: News Mailing Service <%s>\n",
      $mn_config::cf_server_email );
  print $handle "To: $addr\n";
  print $handle "X-Class: slow\n";
  print $handle "Precedence: junk\n";
  print $handle "Errors-To: ${mn_config::cf_server_errors_to}\n";
  ## XXX Temporary MIME workaround
  print $handle "MIME-Version: 1.0\n";
  print $handle sprintf( "Content-Type: text/plain; charset=%s\n",
     $charset );
  print $handle sprintf( "Content-Transfer-Encoding: %s\n",
      ( lc $charset eq 'us-ascii' ? '7bit' : '8bit' ) );
  print $handle "\n";
  print "На сервере созданы группы:\n\n"; ## XXX lang
}

################################################################
## mn_strip_address()
## Convert RFC822 forms `phrase <route-addr>' and `addr-spec (comment)'
## to simple address.
## XXX Too simple parsing now.

sub mn_strip_address {
  my $addr = shift;
  my( $localpart, $addr_domain );
  my @tmpa;
  $addr =~ s/^\s+//;
  $addr =~ s/\s+$//;
  if( $addr =~ /<\s*(.*)\s*>/ ) { $addr = $1; }
  if( $addr =~ /\s*\(.*\)\s*$/ ) { $addr = $`; }
  @tmpa = split /\@/, $addr;
  return $addr if( $#tmpa != 1 );
  $localpart = $tmpa[0];
  $localpart = "postmaster" if lc $localpart eq "postmaster";
  $addr_domain = lc $tmpa[1];
  return "$localpart\@$addr_domain";
}

################################################################
## parse_arpatime()

sub parse_arpatime {
  my $t = shift;
  my( $mday, $month, $year, $hour, $minute, $second,
      $tzone, $tzoff, $nmdays, $ts );
  while(
    $t =~ s/\s*\([^\)]*?\)\s*/ /
    ) {}
  $t =~ s/^\s+//s;
  $t =~ s/\s+$//s;

  if( $t =~ /^
      (?:[A-Z][a-z][a-z],\s*)*      ## day of week, if present
      (\d+)\s+                      ## day of month
      ([A-Z][a-z][a-z])\s+          ## month name
      (\d+)\s+                      ## year
      (\d+):                        ## hour
      (\d+)                         ## minute
      (:(\d+))*                     ## second
      \s+(\w+|\+\d{4}|-\d{4})       ## zone
      $/x )
  {
    $mday = $1;
    $month = &month_from_english( $2 );
    $year = $3;
    $hour = $4;
    $minute = $5;
    $second = $7 || 0;
    $tzone = $8;
  }
  else { return -1; }

  return -1 unless $mday;
  return -1 unless $month;
  return -1 unless $year;
  $year = '2000' if $year eq '00';
  $year += 2000 if $year < 70;
  $year += 1900 if( $year >= 70 && $year < 100 );
  if( $tzone eq '-0000' || $tzone eq '+0000' ||
      uc $tzone eq 'UT' || uc $tzone eq 'UTC' || uc $tzone eq 'GMT' )
  {
    $tzoff = 0;
  }
  elsif( $tzone =~ /^\+(\d{2})(\d{2})$/ ) {
    $tzoff = $1 * 3600 + $2 * 60;
  }
  elsif( $tzone =~ /^-(\d{2})(\d{2})$/ ) {
    $tzoff = -( $1 * 3600 + $2 * 60 );
  }
  elsif( $tzone =~ /^[A-Z]$/ ) {
    if( $tzone eq 'Z' ) {
      $tzoff = 0;
    }
    elsif( ( $tzone cmp 'I' ) <= 0 ) {
      $tzoff = -3600 * ( ord($tzone) - ord('A') + 1 );
    }
    elsif( ( $tzone cmp 'M' ) <= 0 ) {
      $tzoff = -3600 * ( ord($tzone) - ord('K') + 10 );
    }
    else {
      $tzoff = 3600 * ( ord($tzone) - ord('N') + 1 );
    }
  }
  else {
    $tzoff = {
      'EST' => -18000,
      'EDT' => -14400,
      'CST' => -21600,
      'CDT' => -18000,
      'MST' => -25200,
      'MDT' => -21600,
      'PST' => -28800,
      'PDT' => -21600
    } -> {$tzone} || 0;
  }
  $second += $tzoff;
  while( $second <= -86400 ) { $second += 86400; --$mday; }
  while( $second >= 86400 ) { $second -= 86400; ++$mday; }
  while( $second <= -3600 ) { $second += 3600; --$hour; }
  while( $second >= 3600 ) { $second -= 3600; ++$hour; }
  while( $second < 0 ) { $second += 60; --$minute; }
  while( $second >= 60 ) { $second -= 60; ++$minute; }
  while( $minute < 0 ) { $minute += 60; --$hour; }
  while( $minute >= 60 ) { $minute -= 60; ++$hour; }
  while( $hour < 0 ) { $hour += 24; --$mday; }
  while( $hour >= 60 ) { $hour -= 24; ++$mday; }
  ## Normalize date... it is too complicated
  for(;;) {
    $nmdays = &mdays( $year, $month );
    last if( $month >= 1 && $month <= 12 && $mday >= 1 &&
        $mday <= $nmdays );
    if( $month < 1 ) { --$year; $month += 12; next; }
    if( $month > 12 ) { ++$year; $month -= 12; next; }
    if( $mday < 1 ) {
      --$month;
      while( $month < 1 ) { --$year; $month += 12; }
      $mday += &mdays( $year, $month );
      next;
    }
    if( $mday > $nmdays ) {
      $mday -= $nmdays;
      ++$month;
      while( $month > 12 ) { ++$year; $month -= 12; }
      next;
    }
    last;
  }
  ## ($year,$month,$mday,$hour,$minute,$second) is now UTC representation
  return &make_unix_time_from_utc(
      $second, $minute, $hour, $mday, $month, $year );
}

############################################################3###
## month_from_english()

sub month_from_english {
  return $english_months -> { lc $_[0] };
}

################################################################
## make_unix_time_from_utc()

sub make_unix_time_from_utc {
  my( $second, $minute, $hour, $mday, $month, $year ) = @_;
  my( $t0, $niter, $diff );
  my @ref0;
  my @ref1;
  $year -= 1900;
  --$month;
  $t0 = mktime( $second, $minute, $hour, $mday, $month, $year );
  @ref0 = ( $second, $minute, $hour, $mday, $month, $year );
  $niter = 0;
  for(;;) {
    ++$niter;
    if( $niter >= 10 ) {
      ## XXX Add warning
      return $t0;
    }
    @ref1 = gmtime($t0);
    $diff = difflongtime(\@ref0,\@ref1);
    return $t0 if $diff == 0;
    $t0 -= $diff;
  }
}

################################################################
## difflongtime()
## Returns estimate of differences of two dates
## represented in long form.
## Lengths of year and month in seconds are average per all calendar.

sub difflongtime {
  my $ref0 = shift;
  my $ref1 = shift;
  return 31556926*(${$ref1}[5]-${$ref0}[5])+
          2629743*(${$ref1}[4]-${$ref0}[4])+
            86400*(${$ref1}[3]-${$ref0}[3])+
             3600*(${$ref1}[2]-${$ref0}[2])+
               60*(${$ref1}[1]-${$ref0}[1])+
                  (${$ref1}[0]-${$ref0}[0]);
}

################################################################

sub mdays {
  my( $year, $month ) = @_;
  my $flag_leap = &is_leap( $year );
  return ( $flag_leap ? 29 : 28 ) if( $month == 2 );
  return [0,31,28,31,30,31,30,31,31,30,31,30,31]->[$month];
}

################################################################

sub is_leap {
  my $y = shift;
  return 0 if( 0 != $y % 4 );
  return 1 if( 0 != $y % 100 );
  return 0 if( 0 != $y % 400 );
  return 1;
}

################################################################
##  shellparseable()
##  It prints form of this line adoptable by shell as single argument

sub shellparseable {
  my $s = shift;
  return '' unless defined $s; ## ?
  return "''" if $s eq '';
  return $s if $s =~ /^[A-Za-z0-9+,.\/\@:=^_]+$/;
  return "'$s'" unless $s =~ /['\\]/;
  return '"'.$s.'"' unless $s =~ /["\\\$]/;
  my $to;
  my $old = $s;
  my $c;
  my $cc;
  $to = '';
  while( $s ne '' ) {
    $c = substr( $s, 0, 1 );
    $s = substr( $s, 1 );
    if( $c eq "\n" ) { $to .= '"'."\n".'"'; next; }
    $to .= "\\" unless $c =~ /[A-Za-z0-9+,.\/\@:=^_-]/;
    $to .= $c;
  }
  return $to;
}

################################################################
## mn_gethostname()

use vars qw( $mn_hostname );

sub mn_gethostname {
  return $mn_hostname if $mn_hostname;
  eval {
    require Sys::Hostname;
    $mn_hostname = Sys::Hostname::hostname();
  };
  return $mn_hostname if $mn_hostname;
  return undef;
}
