#!/usr/bin/perl

package mn_mime;

use strict;
require Unicode::Map8;
use Unicode::String qw( utf7 utf8 utf16 );
use MIME::Base64;
use mn_config;
use mn_intl;

################################################################
## Globals

use vars qw( %dehex_hash );

################################################################
## Initialization

%dehex_hash = (
  '0' => 0,   '1' => 1,   '2' => 2,   '3' => 3,
  '4' => 4,   '5' => 5,   '6' => 6,   '7' => 7,
  '8' => 8,   '9' => 9,   'A' => 10,  'B' => 11,
  'C' => 12,  'D' => 13,  'E' => 14,  'F' => 15
  );

## Say ok to calling module
return 1;

################################################################
## decode_field()
## Decodes all rfc2047 sequences ('=?...?=') and converts its contents
## to character set specified in parameters hash.
## This ignore some rfc2047 recommendations (e.g. that encoded word must
## not appear in quoted-string), all field text is parsed literally without
## rfc822 parsing.

sub decode_field {
  my( $itext, $phash ) = @_;
  my( $otext, $cp_dest, $pl, $ew, $ew_charset, $ew_cte, $ew_ec,
      $flag_prev_ew, $flag_oksofar, $text_orig, $cc_status, $cc_result );

  $phash = {} unless $phash;
  ## Default is koi8-r. Otherwise one should specify language explicitly.
  $cp_dest = $phash->{'cp_dest'} || 'koi8-r';
  ## Return unchanged unless any rfc2047 sequence presents.
  return $itext unless( $itext =~ /=\?\S+\?[BbQq]\?\S*\?=/s );
  ## Work cycle...
  $flag_prev_ew = 0;
  $otext = '';
  while( $itext ne '' ) {
    if( $itext !~ /=\?(\S+)\?([BbQq])\?(\S*)\?=/s ) {
      return $otext . $itext;
    }
    ## Use results of previous regexp matching
    $pl = $`; $ew = $&; $itext = $';
    $ew_charset = $1; $ew_cte = $2; $ew_ec = $3;
    if( $flag_prev_ew && $pl =~ /^\s+$/ ) { $pl = ''; }
    if( $pl ne '' ) { $otext .= $pl; $pl = ''; }
    $flag_oksofar = 1;
    if( lc $ew_cte eq 'b' ) {
      $text_orig = decode_base64( $ew_ec );
      ($cc_status,$cc_result) =
          mn_intl::convert_cp( $text_orig, $ew_charset, $cp_dest );
      if( !$cc_status ) { $otext .= $cc_result; }
      else { $flag_oksofar = 0; }
    }
    elsif( lc $ew_cte eq 'q' ) {
      $text_orig = &decode_qp_2047( $ew_ec );
      ($cc_status,$cc_result) =
          mn_intl::convert_cp( $text_orig, $ew_charset, $cp_dest );
      if( !$cc_status ) { $otext .= $cc_result; }
      else { $flag_oksofar = 0; }
    }
    else { $flag_oksofar = 0; }
    if( !$flag_oksofar ) {
      $otext .= ' ' if $flag_prev_ew;
      $otext .= $ew;
    }
    $flag_prev_ew = 1;
  }
  return $otext;
}

################################################################
## decode_qp_2047()

sub decode_qp_2047 {
  my $itext = shift;
  my $otext = '';
  while( $itext ne '' ) {
    if( $itext =~ /^([^=_]+)/ ) {
      $otext .= $1; $itext = $'; next;
    }
    if( substr( $itext, 0, 1 ) eq '_' ) {
      $otext .= ' ';
      $itext =~ s/^.//;
      next;
    }
    die unless substr( $itext, 0, 1 ) eq '=';
    $otext .= chr(
         16*$dehex_hash{substr($itext,1,1)}
        +   $dehex_hash{substr($itext,2,1)} );
    $itext = substr( $itext, 3 );
  }
  return $otext;
}
