package FS::InitHandler;

use strict;
use vars qw($DEBUG);
use FS::UID qw(adminsuidsetup);
use FS::Record;

$DEBUG = 1;

sub handler {

=pod

  use Date::Format;
  use Date::Parse;
  use Tie::IxHash;
  use HTML::Entities;
  use IO::Handle;
  use IO::File;
  use String::Approx:
  use HTML::Widgets::SelectLayers 0.02;
  #use FS::UID;
  #use FS::Record;
  use FS::Conf;
  use FS::CGI;
  use FS::Msgcat;
  
  use FS::agent;
  use FS::agent_type;
  use FS::domain_record;
  use FS::cust_bill;
  use FS::cust_bill_pay;
  use FS::cust_credit;
  use FS::cust_credit_bill;
  use FS::cust_main;
  use FS::cust_main_county;
  use FS::cust_pay;
  use FS::cust_pkg;
  use FS::cust_refund;
  use FS::cust_svc;
  use FS::nas;
  use FS::part_bill_event;
  use FS::part_pkg;
  use FS::part_referral;
  use FS::part_svc;
  use FS::pkg_svc;
  use FS::port;
  use FS::queue qw(joblisting);
  use FS::raddb;
  use FS::session;
  use FS::svc_acct;
  use FS::svc_acct_pop qw(popselector);
  use FS::svc_acct_sm;
  use FS::svc_domain;
  use FS::svc_forward;
  use FS::svc_www;
  use FS::type_pkgs;
  use FS::part_export;
  use FS::part_export_option;
  use FS::export_svc;
  use FS::msgcat;

=cut

  warn "[FS::InitHandler] handler called\n" if $DEBUG;

  open(MAPSECRETS,"<$FS::UID::conf_dir/mapsecrets")
    or die "can't read $FS::UID::conf_dir/mapsecrets: $!";

  my %seen;
  while (<MAPSECRETS>) {
    /^([\w\-\.]+)\s(.*)$/
      or do { warn "strange line in mapsecrets: $_"; next; };
    my($user, $datasrc) = ($1, $2);
    next if $seen{$datasrc}++;
    warn "[FS::InitHandler] preloading $datasrc for $user\n" if $DEBUG;
    adminsuidsetup($user);
  }

  close MAPSECRETS;

}

1;
