#!/usr/bin/perl

##ADDMYINCHERE

package mn_config;
use vars qw(
  $cf_db_handler
  $cf_db_cmd_user
  $cf_db_cmd_password
  $cf_db_feeder_user
  $cf_db_feeder_password
  $cf_db_lister_user
  $cf_db_lister_password
  $cf_db_sdba_user
  $cf_db_sdba_password
  $cf_smtp_server
  $cf_lister_log
  $cf_syslog_facility
  $cf_syslog_identity_prefix
  $cf_smtp_max_nsend
  $cf_server_email
  $cf_server_errors_to
  @bad_localparts
  @our_explicit_domains
  $cf_lister_lock_path
  @cf_smtp_servers
  %cf_smtp_hp_pref
  $cf_smtp_maxnsent
  $cf_smtp_timo_resolv
  $cf_smtp_timo_dampen_inaddr
  $cf_smtp_timo_connect
  $cf_smtp_timo_banner
  $cf_smtp_timo_helo
  $cf_smtp_timo_mailfrom
  $cf_smtp_timo_rcptto
  $cf_smtp_timo_data
  $cf_smtp_timo_datafinal
  $cf_smtp_timo_rset
  $cf_smtp_timo_quit
  %cf_intl_lang_po_files
  );

## Set values
$cf_db_handler = "dbi:mysql:mailnews";
$cf_db_cmd_user = "mncmd";
$cf_db_cmd_password = "mnCmd";
$cf_db_feeder_user = "mnfeeder";
$cf_db_feeder_password = "mnFeeder";
$cf_db_lister_user = "mnlister";
$cf_db_lister_password = "mnLister";
$cf_db_sdba_user = 'mnsdba';
$cf_db_sdba_password = 'mnSdba';
$cf_smtp_server = "localhost";
$cf_lister_log = "/var/mnews/lister/log";
$cf_syslog_facility = 'local4';
$cf_syslog_identity_prefix = 'mailnews';
$cf_smtp_max_nsend = 1000;
$cf_server_email = 'news@segfault.kiev.ua';
$cf_server_errors_to = 'news-server@segfault.kiev.ua';
@bad_localparts = qw( root uucp mailer-daemon news );
@our_explicit_domains = qw(
  lucky.net
  segfault.kiev.ua
  netch.kiev.ua
  nn.kiev.ua
  iv.nn.kiev.ua
  ivb.nn.kiev.ua
);
$cf_lister_lock_path = '/var/mnews/lister/lock';
$cf_newgrp_lock_path = '/var/mnews/newgrp/lock';
@cf_smtp_servers = qw( localhost );
%cf_smtp_hp_pref = ( localhost => 10 );
%cf_intl_lang_po_files = (
  'uk' => '/var/homes/netch/cvswork/head/news/mailnews/ng-sql/intl/rus-ukr.po.pm'
  );

## Return TRUE
return 1;
