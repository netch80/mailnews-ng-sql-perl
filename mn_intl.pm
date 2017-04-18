#!/usr/bin/env perl5

package mn_intl;

use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw(Exporter);
@EXPORT_OK = qw( i );

use mn_config;
require Unicode::Map8;
use Unicode::String qw( utf7 utf8 utf16 );
use MIME::Base64;
use Sys::Syslog qw( :DEFAULT );

################################################################
## Globals

use vars qw( %map8_hash $has_i18n_charset $tried_use_i18n_charset
    %intl_parm %intl_state %intl_trans $cp_main );

################################################################
## Initialization

## Say ok to calling module
return 1;

################################################################
## set_intl()

sub set_intl {
  my $ip = shift;
  $intl_parm{'lang'} = $ip->{'lang'} if $ip->{'lang'};
  $intl_parm{'charset'} = $ip->{'charset'} if $ip->{'charset'};
  $cp_main = $intl_parm{'charset'} || 'koi8-u';
  &load_intl();
}

################################################################
## load_intl()

sub load_intl {
  ## Load translation maps
  my $lang = $intl_parm{'lang'};
  syslog( 'debug', 'load_intl(): lang=%s', $lang );
  return unless $lang;
  my( $rc, $k, $v, $cp_keys, $cp_values, $th_translations, $th_parameters );
  my $po_file = $mn_config::cf_intl_lang_po_files{$intl_parm{'lang'}};
  if( $po_file eq 'NONE' ) { return; }
  elsif( !$po_file ) {
    syslog( 'notice', 'no po file for selected language %s',
        $intl_parm{'lang'} );
    return;
  }
  eval {
    local $SIG{__WARN__} = sub {};
    undef &mn_ovl_po::translations;
    undef &mn_ovl_po::parameters;
    require $po_file;
    $th_translations = &mn_ovl_po::translations();
    $th_parameters = &mn_ovl_po::parameters();
    undef &mn_ovl_po::translations;
    undef &mn_ovl_po::parameters;
    eval { &mn_ovl_po::END(); };
    undef $INC{$po_file};
  };
  $rc = $@;
  if( $rc ) {
    chomp $rc;
    syslog( 'notice', 'loading po file failed: %s', $rc );
    return;
  }
  ## Author's host environment is in koi8-u
  $cp_keys = $th_parameters->{'cp_keys'} ||
      $mn_config::cf_default_charset || $cp_main || 'koi8-u';
  $cp_values = $th_parameters->{'cp_values'} ||
      $mn_config::cf_default_charset || $cp_main || 'koi8-u';
  for $k ( keys %$th_translations ) {
    next unless( defined $k && $k ne '' );
    $v = $th_translations->{$k};
    next unless( defined $v && $v ne '' );
    (undef,$k) = convert_cp( $k, $cp_keys, $cp_main );
    (undef,$v) = convert_cp( $v, $cp_values, $cp_main );
    $intl_trans{$k} = $v;
  }
  syslog( 'debug', 'load_intl(): ok' );
}

################################################################
## i()

sub i {
  my( $i, $ic, $oc, $o );
  $i = shift;
  $ic = convert_cp( $i, 'koi8-u', $cp_main );
  return $i unless $ic;
  $oc = $intl_trans{ $ic };
  return $i unless $oc;
  $o = convert_cp( $oc, $cp_main, $intl_parm{'charset'} );
  return $o || $i;
}

################################################################
## convert_cp()
## Converts text from one codepage to another.
## Returns list: (errflag,otext)

sub convert_cp {
  my( $itext, $cp_from, $cp_to, $phash ) = @_;
  my( $otext, $mtext, $flag_strict, $h );
  $phash = {} unless $phash;
  return undef unless defined $itext && defined $cp_from && defined $cp_to;
  $cp_from = lc $cp_from;
  $cp_to = lc $cp_to;
  return (0,$itext) if( $cp_from eq $cp_to );
  return (0,$itext) if(
      ( $cp_from eq 'koi8-r' || $cp_from eq 'koi8-u' ) &&
      ( $cp_to eq 'koi8-r' || $cp_to eq 'koi8-u' ) );
  #-$flag_strict = $phash->{'strict'} or 0;
  ## Find objects for conversion objects in global hash.
  return (-1,'') unless(
      &is_utf_name( $cp_from ) || &map8_open_handle( $cp_from ) );
  return (-1,'') unless(
      &is_utf_name( $cp_to ) || &map8_open_handle( $cp_to ) );
  if( lc $cp_from eq 'utf-8' || lc $cp_from eq 'utf8' ) {
    $mtext = utf8($itext)->utf16;
  }
  elsif( lc $cp_from eq 'utf-7' || lc $cp_from eq 'utf7' ) {
    $mtext = utf7($itext)->utf16;
  }
  elsif( ( $h = $map8_hash{$cp_from} ) ) {
    $h->default_to8(0x3f);
    $h->default_to16(0x3f);
    $mtext = $h->to16($itext);
  }
  else { return (-1,''); }
  if( lc $cp_to eq 'utf-8' || lc $cp_to eq 'utf8' ) {
    $otext = utf16($itext)->utf8;
  }
  elsif( lc $cp_to eq 'utf-7' || lc $cp_to eq 'utf7' ) {
    $otext = utf16($itext)->utf7;
  }
  elsif( ( $h = $map8_hash{$cp_to} ) ) {
    $h->default_to8(0x3f);
    $h->default_to16(0x3f);
    $otext = $h->to8($mtext);
  }
  else { return (-1,''); }
  return ( 0, $otext );
}

################################################################
## map8_open_handle()

sub map8_open_handle {
  my $cpname = shift; ## isn't changed here
  my $cn; ## can be changed to known for Unicode::Map8
  my $handle;
  $cn = lc $cpname;
  return 0 unless $cn;
  ## Find at hash. Hash is indexed with $cpname,
  ## but module is asked with $cn.
  return 1 if $map8_hash{$cpname};
  $map8_hash{$cpname} = Unicode::Map8->new( $cn ) and return 1;
  $map8_hash{$cpname} = Unicode::Map8->new( uc $cn ) and return 1;
  ## Unicode::Map8 uses codepage names with doesn't conform with IANA
  ## and also is case sensitive (!)
  ## Here we provide a bunch of works around its stupidity...
  $cn = '';
  unless( $tried_use_i18n_charset ) {
    eval {
      $tried_use_i18n_charset = 1;
      require I18N::Charset;
      $has_i18n_charset = 1;
      $cn = I18N::Charset::map8_charset_name( lc $cpname );
    };
  }
  if( $cn ) {
    $map8_hash{$cpname} = Unicode::Map8->new( $cn ) and return 1;
  }
  $cn = 'ASCII' if lc $cpname eq 'us-ascii';
  $cn = 'cp1251' if lc $cpname eq 'windows-1251';
  $map8_hash{$cpname} = Unicode::Map8->new( $cn ) and return 1;
  $cn = 'ANSI_X3.4-1968' if(
      lc $cpname eq 'us-ascii' || lc $cpname eq 'ascii' );
  $map8_hash{$cpname} = Unicode::Map8->new( $cn ) and return 1;
  return 0;
}

################################################################
## is_utf_name()

sub is_utf_name {
  my $n = shift; $n = lc $n;
  return ( $n eq 'utf-8' || $n eq 'utf8' || $n eq 'utf-7' || $n eq 'utf7' );
}
