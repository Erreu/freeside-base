package FS::ClientAPI::MyAccount;

use 5.008; #require 5.8+ for Time::Local 1.05+
use strict;
use vars qw( $cache $DEBUG $me );
use subs qw( _cache _provision );
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Date::Format;
use Business::CreditCard;
use Time::Duration;
use Time::Local qw(timelocal_nocheck);
use FS::UI::Web::small_custview qw(small_custview); #less doh
use FS::UI::Web;
use FS::UI::bytecount qw( display_bytecount );
use FS::Conf;
#use FS::UID qw(dbh);
use FS::Record qw(qsearch qsearchs dbh);
use FS::Msgcat qw(gettext);
use FS::Misc qw(card_types);
use FS::ClientAPI_SessionCache;
use FS::svc_acct;
use FS::svc_domain;
use FS::svc_phone;
use FS::svc_external;
use FS::part_svc;
use FS::cust_main;
use FS::cust_bill;
use FS::cust_main_county;
use FS::cust_pkg;
use FS::payby;
use FS::acct_rt_transaction;
use HTML::Entities;
use FS::TicketSystem;

$DEBUG = 0;
$me = '[FS::ClientAPI::MyAccount]';

use vars qw( @cust_main_editable_fields );
@cust_main_editable_fields = qw(
  first last company address1 address2 city
    county state zip country daytime night fax
  ship_first ship_last ship_company ship_address1 ship_address2 ship_city
    ship_state ship_zip ship_country ship_daytime ship_night ship_fax
  payby payinfo payname paystart_month paystart_year payissue payip
  ss paytype paystate stateid stateid_state
);

sub _cache {
  $cache ||= new FS::ClientAPI_SessionCache( {
               'namespace' => 'FS::ClientAPI::MyAccount',
             } );
}

sub skin_info {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  #return { 'error' => $session } if $context eq 'error';

  my $agentnum = '';
  if ( $context eq 'customer' ) {

    my $sth = dbh->prepare('SELECT agentnum FROM cust_main WHERE custnum = ?')
      or die dbh->errstr;

    $sth->execute($custnum) or die $sth->errstr;

    $agentnum = $sth->fetchrow_arrayref->[0]
      or die "no agentnum for custnum $custnum";

  #} elsif ( $context eq 'agent' ) {
  } elsif ( $p->{'agentnum'} =~ /^(\d+)$/ ) {
    $agentnum = $1;
  }

  my $conf = new FS::Conf;

  #false laziness w/Signup.pm

  my $skin_info_cache_agent = _cache->get("skin_info_cache_agent$agentnum");

  if ( $skin_info_cache_agent ) {

    warn "$me loading cached skin info for agentnum $agentnum\n"
      if $DEBUG > 1;

  } else {

    warn "$me populating skin info cache for agentnum $agentnum\n"
      if $DEBUG > 1;

    $skin_info_cache_agent = {
      'agentnum' => $agentnum,
      ( map { $_ => scalar( $conf->config($_, $agentnum) ) }
        qw( company_name ) ),
      ( map { $_ => scalar( $conf->config("selfservice-$_", $agentnum ) ) }
        qw( body_bgcolor box_bgcolor
            text_color link_color vlink_color hlink_color alink_color
            font title_color title_align title_size menu_bgcolor menu_fontsize
          )
      ),
      ( map { $_ => $conf->exists("selfservice-$_", $agentnum ) }
        qw( menu_skipblanks menu_skipheadings menu_nounderline )
      ),
      ( map { $_ => scalar($conf->config_binary("selfservice-$_", $agentnum)) }
        qw( title_left_image title_right_image
            menu_top_image menu_body_image menu_bottom_image
          )
      ),
      'logo' => scalar($conf->config_binary('logo.png', $agentnum )),
      ( map { $_ => join("\n", $conf->config("selfservice-$_", $agentnum ) ) }
        qw( head body_header body_footer company_address ) ),
    };

    _cache->set("skin_info_cache_agent$agentnum", $skin_info_cache_agent);

  }

  #{ %$skin_info_cache_agent };
  $skin_info_cache_agent;

}

sub login_info {
  my $p = shift;

  my $conf = new FS::Conf;

  my %info = (
    %{ skin_info($p) },
    'phone_login'  => $conf->exists('selfservice_server-phone_login'),
    'single_domain'=> scalar($conf->config('selfservice_server-single_domain')),
  );

  return \%info;

}

#false laziness w/FS::ClientAPI::passwd::passwd
sub login {
  my $p = shift;

  my $conf = new FS::Conf;

  my $svc_x = '';
  if ( $p->{'domain'} eq 'svc_phone'
       && $conf->exists('selfservice_server-phone_login') ) { 

    my $svc_phone = qsearchs( 'svc_phone', { 'phonenum' => $p->{'username'} } );
    return { error => 'Number not found.' } unless $svc_phone;

    #XXX?
    #my $pkg_svc = $svc_acct->cust_svc->pkg_svc;
    #return { error => 'Only primary user may log in.' } 
    #  if $conf->exists('selfservice_server-primary_only')
    #    && ( ! $pkg_svc || $pkg_svc->primary_svc ne 'Y' );

    return { error => 'Incorrect PIN.' }
      unless $svc_phone->check_pin($p->{'password'});

    $svc_x = $svc_phone;

  } else {

    my $svc_domain = qsearchs('svc_domain', { 'domain' => $p->{'domain'} } )
      or return { error => 'Domain '. $p->{'domain'}. ' not found' };

    my $svc_acct = qsearchs( 'svc_acct', { 'username'  => $p->{'username'},
                                           'domsvc'    => $svc_domain->svcnum, }
                           );
    return { error => 'User not found.' } unless $svc_acct;

    return { error => 'Incorrect password.' }
      unless $svc_acct->check_password($p->{'password'});

    $svc_x = $svc_acct;

  }

  my $session = {
    'svcnum' => $svc_x->svcnum,
  };

  my $cust_svc = $svc_x->cust_svc;
  my $cust_pkg = $cust_svc->cust_pkg;
  if ( $cust_pkg ) {
    my $cust_main = $cust_pkg->cust_main;
    $session->{'custnum'} = $cust_main->custnum;
    if ( $conf->exists('pkg-balances') ) {
      my @cust_pkg = grep { $_->part_pkg->freq !~ /^(0|$)/ }
                          $cust_main->ncancelled_pkgs;
      $session->{'pkgnum'} = $cust_pkg->pkgnum
        if scalar(@cust_pkg) > 1;
    }
  }

  #my $pkg_svc = $svc_acct->cust_svc->pkg_svc;
  #return { error => 'Only primary user may log in.' } 
  #  if $conf->exists('selfservice_server-primary_only')
  #    && ( ! $pkg_svc || $pkg_svc->primary_svc ne 'Y' );
  my $part_pkg = $cust_pkg->part_pkg;
  return { error => 'Only primary user may log in.' }
    if $conf->exists('selfservice_server-primary_only')
       && $cust_svc->svcpart != $part_pkg->svcpart([qw( svc_acct svc_phone )]);

  my $session_id;
  do {
    $session_id = md5_hex(md5_hex(time(). {}. rand(). $$))
  } until ( ! defined _cache->get($session_id) ); #just in case

  my $timeout = $conf->config('selfservice-session_timeout') || '1 hour';
  _cache->set( $session_id, $session, $timeout );

  return { 'error'      => '',
           'session_id' => $session_id,
         };
}

sub logout {
  my $p = shift;
  if ( $p->{'session_id'} ) {
    _cache->remove($p->{'session_id'});
    return { %{ skin_info($p) }, 'error' => '' };
  } else {
    return { %{ skin_info($p) }, 'error' => "Can't resume session" }; #better error message
  }
}

sub access_info {
  my $p = shift;

  my $conf = new FS::Conf;

  my $info = skin_info($p);

  use vars qw( $cust_paybys ); #cache for performance
  unless ( $cust_paybys ) {

    my %cust_paybys = map { $_ => 1 }
                      map { FS::payby->payby2payment($_) }
                          $conf->config('signup_server-payby');

    $cust_paybys = [ keys %cust_paybys ];

  }
  $info->{'cust_paybys'} = $cust_paybys;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  $info->{hide_payment_fields} =
  [
    map { my $pg = '';
          if ( FS::payby->realtime($_) ) {
            $pg = $cust_main->agent->payment_gateway(
              'method'  => FS::payby->payby2bop($_),
              'nofatal' => 1,
            );
          }
          $pg && $pg->gateway_namespace eq 'Business::OnlineThirdPartyPayment';
        }
    @{ $info->{cust_paybys} }
  ];

  return { %$info,
           'custnum'       => $custnum,
           'access_pkgnum' => $session->{'pkgnum'},
           'access_svcnum' => $session->{'svcnum'},
         };
}

sub customer_info {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my %return;

  my $conf = new FS::Conf;
  if ($conf->exists('cust_main-require_address2')) {
    $return{'require_address2'} = '1';
  }else{
    $return{'require_address2'} = '';
  }
  
  if ( $custnum ) { #customer record

    my $search = { 'custnum' => $custnum };
    $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
    my $cust_main = qsearchs('cust_main', $search )
      or return { 'error' => "unknown custnum $custnum" };

    if ( $session->{'pkgnum'} ) { 
      $return{balance} = $cust_main->balance_pkgnum( $session->{'pkgnum'} );
    } else {
      $return{balance} = $cust_main->balance;
    }

    $return{tickets} = [ ($cust_main->tickets) ];

    unless ( $session->{'pkgnum'} ) {
      my @open = map {
                       {
                         invnum => $_->invnum,
                         date   => time2str("%b %o, %Y", $_->_date),
                         owed   => $_->owed,
                       };
                     } $cust_main->open_cust_bill;
      $return{open_invoices} = \@open;
    }

    $return{small_custview} =
      small_custview( $cust_main,
                      scalar($conf->config('countrydefault')),
                      ( $session->{'pkgnum'} ? 1 : 0 ), #nobalance
                    );

    $return{name} = $cust_main->first. ' '. $cust_main->get('last');

    for (@cust_main_editable_fields) {
      $return{$_} = $cust_main->get($_);
    }

    if ( $cust_main->payby =~ /^(CARD|DCRD)$/ ) {
      $return{payinfo} = $cust_main->paymask;
      @return{'month', 'year'} = $cust_main->paydate_monthyear;
    }

    $return{'invoicing_list'} =
      join(', ', grep { $_ !~ /^(POST|FAX)$/ } $cust_main->invoicing_list );
    $return{'postal_invoicing'} =
      0 < ( grep { $_ eq 'POST' } $cust_main->invoicing_list );

    if (scalar($conf->config('support_packages'))) {
      my @support_services = ();
      foreach ($cust_main->support_services) {
        my $seconds = $_->svc_x->seconds;
        my $time_remaining = (($seconds < 0) ? '-' : '' ).
                             int(abs($seconds)/3600)."h".
                             sprintf("%02d",(abs($seconds)%3600)/60)."m";
        my $cust_pkg = $_->cust_pkg;
        my $pkgnum = '';
        my $pkg = '';
        $pkgnum = $cust_pkg->pkgnum if $cust_pkg;
        $pkg = $cust_pkg->part_pkg->pkg if $cust_pkg;
        push @support_services, { svcnum => $_->svcnum,
                                  time => $time_remaining,
                                  pkgnum => $pkgnum,
                                  pkg => $pkg,
                                };
      }
      $return{support_services} = \@support_services;
    }

  } elsif ( $session->{'svcnum'} ) { #no customer record

    my $svc_acct = qsearchs('svc_acct', { 'svcnum' => $session->{'svcnum'} } )
      or die "unknown svcnum";
    $return{name} = $svc_acct->email;

  } else {

    return { 'error' => 'Expired session' }; #XXX redirect to login w/this err!

  }

  return { 'error'          => '',
           'custnum'        => $custnum,
           %return,
         };

}

sub edit_info {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'}
    or return { 'error' => "no customer record" };

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $new = new FS::cust_main { $cust_main->hash };
  $new->set( $_ => $p->{$_} )
    foreach grep { exists $p->{$_} } @cust_main_editable_fields;

  my $payby = '';
  if (exists($p->{'payby'})) {
    $p->{'payby'} =~ /^([A-Z]{4})$/
      or return { 'error' => "illegal_payby " . $p->{'payby'} };
    $payby = $1;
  }

  if ( $payby =~ /^(CARD|DCRD)$/ ) {

    $new->paydate($p->{'year'}. '-'. $p->{'month'}. '-01');

    if ( $new->payinfo eq $cust_main->paymask ) {
      $new->payinfo($cust_main->payinfo);
    } else {
      $new->payinfo($p->{'payinfo'});
    }

    $new->set( 'payby' => $p->{'auto'} ? 'CARD' : 'DCRD' );

  } elsif ( $payby =~ /^(CHEK|DCHK)$/ ) {

    my $payinfo;
    $p->{'payinfo1'} =~ /^([\dx]+)$/
      or return { 'error' => "illegal account number ". $p->{'payinfo1'} };
    my $payinfo1 = $1;
     $p->{'payinfo2'} =~ /^([\dx]+)$/
      or return { 'error' => "illegal ABA/routing number ". $p->{'payinfo2'} };
    my $payinfo2 = $1;
    $payinfo = $payinfo1. '@'. $payinfo2;

    $new->payinfo( ($payinfo eq $cust_main->paymask)
                     ? $cust_main->payinfo
                     : $payinfo
                 );

    $new->set( 'payby' => $p->{'auto'} ? 'CHEK' : 'DCHK' );

  } elsif ( $payby =~ /^(BILL)$/ ) {
    #no-op
  } elsif ( $payby ) {  #notyet ready
    return { 'error' => "unknown payby $payby" };
  }

  my @invoicing_list;
  if ( exists $p->{'invoicing_list'} || exists $p->{'postal_invoicing'} ) {
    #false laziness with httemplate/edit/process/cust_main.cgi
    @invoicing_list = split( /\s*\,\s*/, $p->{'invoicing_list'} );
    push @invoicing_list, 'POST' if $p->{'postal_invoicing'};
  } else {
    @invoicing_list = $cust_main->invoicing_list;
  }

  my $error = $new->replace($cust_main, \@invoicing_list);
  return { 'error' => $error } if $error;
  #$cust_main = $new;
  
  return { 'error' => '' };
}

sub payment_info {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  ##
  #generic
  ##

  use vars qw($payment_info); #cache for performance
  unless ( $payment_info ) {

    my $conf = new FS::Conf;
    my %states = map { $_->state => 1 }
                   qsearch('cust_main_county', {
                     'country' => $conf->config('countrydefault') || 'US'
                   } );

    my %cust_paybys = map { $_ => 1 }
                      map { FS::payby->payby2payment($_) }
                          $conf->config('signup_server-payby');

    my @cust_paybys = keys %cust_paybys;

    $payment_info = {

      #list all counties/states/countries
      'cust_main_county' => 
        [ map { $_->hashref } qsearch('cust_main_county', {}) ],

      #shortcut for one-country folks
      'states' =>
        [ sort { $a cmp $b } keys %states ],

      'card_types' => card_types(),

      'paytypes' => [ @FS::cust_main::paytypes ],

      'paybys' => [ $conf->config('signup_server-payby') ],
      'cust_paybys' => \@cust_paybys,

      'stateid_label' => FS::Msgcat::_gettext('stateid'),
      'stateid_state_label' => FS::Msgcat::_gettext('stateid_state'),

      'show_ss'  => $conf->exists('show_ss'),
      'show_stateid' => $conf->exists('show_stateid'),
      'show_paystate' => $conf->exists('show_bankstate'),
    };

  }

  ##
  #customer-specific
  ##

  my %return = %$payment_info;

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  $return{hide_payment_fields} =
  [
    map { my $pg = '';
          if ( FS::payby->realtime($_) ) {
            $pg = $cust_main->agent->payment_gateway(
              'method'  => FS::payby->payby2bop($_),
              'nofatal' => 1,
            );
          }
          $pg && $pg->gateway_namespace eq 'Business::OnlineThirdPartyPayment';
        }
    @{ $return{cust_paybys} }
  ];

  $return{balance} = $cust_main->balance; #XXX pkg-balances?

  $return{payname} = $cust_main->payname
                     || ( $cust_main->first. ' '. $cust_main->get('last') );

  $return{$_} = $cust_main->get($_) for qw(address1 address2 city state zip);

  $return{payby} = $cust_main->payby;
  $return{stateid_state} = $cust_main->stateid_state;

  if ( $cust_main->payby =~ /^(CARD|DCRD)$/ ) {
    $return{card_type} = cardtype($cust_main->payinfo);
    $return{payinfo} = $cust_main->paymask;

    @return{'month', 'year'} = $cust_main->paydate_monthyear;

  }

  if ( $cust_main->payby =~ /^(CHEK|DCHK)$/ ) {
    my ($payinfo1, $payinfo2) = split '@', $cust_main->paymask;
    $return{payinfo1} = $payinfo1;
    $return{payinfo2} = $payinfo2;
    $return{paytype}  = $cust_main->paytype;
    $return{paystate} = $cust_main->paystate;

  }

  #doubleclick protection
  my $_date = time;
  $return{paybatch} = "webui-MyAccount-$_date-$$-". rand() * 2**32;

  return { 'error' => '',
           %return,
         };

};

#some false laziness with httemplate/process/payment.cgi - look there for
#ACH and CVV support stuff
sub process_payment {

  my $p = shift;

  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my %return;

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  $p->{'amount'} =~ /^\s*(\d+(\.\d{2})?)\s*$/
    or return { 'error' => gettext('illegal_amount') };
  my $amount = $1;
  return { error => 'Amount must be greater than 0' } unless $amount > 0;

  $p->{'payname'} =~ /^([\w \,\.\-\']+)$/
    or return { 'error' => gettext('illegal_name'). " payname: ". $p->{'payname'} };
  my $payname = $1;

  $p->{'paybatch'} =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=]*)$/
    or return { 'error' => gettext('illegal_text'). " paybatch: ". $p->{'paybatch'} };
  my $paybatch = $1;

  $p->{'payby'} ||= 'CARD';
  $p->{'payby'} =~ /^([A-Z]{4})$/
    or return { 'error' => "illegal_payby " . $p->{'payby'} };
  my $payby = $1;

  #false laziness w/process/payment.cgi
  my $payinfo;
  my $paycvv = '';
  if ( $payby eq 'CHEK' || $payby eq 'DCHK' ) {
  
    $p->{'payinfo1'} =~ /^([\dx]+)$/
      or return { 'error' => "illegal account number ". $p->{'payinfo1'} };
    my $payinfo1 = $1;
     $p->{'payinfo2'} =~ /^([\dx]+)$/
      or return { 'error' => "illegal ABA/routing number ". $p->{'payinfo2'} };
    my $payinfo2 = $1;
    $payinfo = $payinfo1. '@'. $payinfo2;

    $payinfo = $cust_main->payinfo
      if $cust_main->paymask eq $payinfo;
   
  } elsif ( $payby eq 'CARD' || $payby eq 'DCRD' ) {
   
    $payinfo = $p->{'payinfo'};

    #more intelligent mathing will be needed here if you change
    #card_masking_method and don't remove existing paymasks
    $payinfo = $cust_main->payinfo
      if $cust_main->paymask eq $payinfo;

    $payinfo =~ s/\D//g;
    $payinfo =~ /^(\d{13,16})$/
      or return { 'error' => gettext('invalid_card') }; # . ": ". $self->payinfo
    $payinfo = $1;

    validate($payinfo)
      or return { 'error' => gettext('invalid_card') }; # . ": ". $self->payinfo
    return { 'error' => gettext('unknown_card_type') }
      if cardtype($payinfo) eq "Unknown";

    if ( length($p->{'paycvv'}) && $p->{'paycvv'} !~ /^\s*$/ ) {
      if ( cardtype($payinfo) eq 'American Express card' ) {
        $p->{'paycvv'} =~ /^\s*(\d{4})\s*$/
          or return { 'error' => "CVV2 (CID) for American Express cards is four digits." };
        $paycvv = $1;
      } else {
        $p->{'paycvv'} =~ /^\s*(\d{3})\s*$/
          or return { 'error' => "CVV2 (CVC2/CID) is three digits." };
        $paycvv = $1;
      }
    }
  
  } else {
    die "unknown payby $payby";
  }

  my %payby2fields = (
    'CARD' => [ qw( paystart_month paystart_year payissue payip
                    address1 address2 city state zip country    ) ],
    'CHEK' => [ qw( ss paytype paystate stateid stateid_state payip ) ],
  );

  my $error = $cust_main->realtime_bop( $FS::payby::payby2bop{$payby}, $amount,
    'quiet'    => 1,
    'payinfo'  => $payinfo,
    'paydate'  => $p->{'year'}. '-'. $p->{'month'}. '-01',
    'payname'  => $payname,
    'paybatch' => $paybatch, #this doesn't actually do anything
    'paycvv'   => $paycvv,
    'pkgnum'   => $session->{'pkgnum'},
    map { $_ => $p->{$_} } @{ $payby2fields{$payby} }
  );
  return { 'error' => $error } if $error;

  $cust_main->apply_payments;

  if ( $p->{'save'} ) {
    my $new = new FS::cust_main { $cust_main->hash };
    if ($payby eq 'CARD' || $payby eq 'DCRD') {
      $new->set( $_ => $p->{$_} )
        foreach qw( payname paystart_month paystart_year payissue payip
                    address1 address2 city state zip country );
      $new->set( 'payby' => $p->{'auto'} ? 'CARD' : 'DCRD' );
    } elsif ($payby eq 'CHEK' || $payby eq 'DCHK') {
      $new->set( $_ => $p->{$_} )
        foreach qw( payname payip paytype paystate
                    stateid stateid_state );
      $new->set( 'payby' => $p->{'auto'} ? 'CHEK' : 'DCHK' );
    }
    $new->set( 'payinfo' => $payinfo );
    $new->set( 'paydate' => $p->{'year'}. '-'. $p->{'month'}. '-01' );
    my $error = $new->replace($cust_main);
    return { 'error' => $error } if $error;
    $cust_main = $new;
  }

  return { 'error' => '' };

}

sub realtime_collect {
  my $p = shift;

  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $error = $cust_main->realtime_collect(
    'method'     => $p->{'method'},
    'pkgnum'     => $session->{'pkgnum'},
    'session_id' => $p->{'session_id'},
    'apply'      => 1,
  );
  return { 'error' => $error } unless ref( $error );

  my $amount = $session->{'pkgnum'}
                 ? $cust_main->balance_pkgnum( $session->{'pkgnum'} )
                 : $cust_main->balance;

  return { 'error' => '', amount => $amount, %$error };
}

sub process_payment_order_pkg {
  my $p = shift;

  my $hr = process_payment($p);
  return $hr if $hr->{'error'};

  order_pkg($p);
}

sub process_payment_order_renew {
  my $p = shift;

  my $hr = process_payment($p);
  return $hr if $hr->{'error'};

  order_renew($p);
}

sub process_prepay {

  my $p = shift;

  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my %return;

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my( $amount, $seconds, $upbytes, $downbytes, $totalbytes ) = ( 0, 0, 0, 0, 0 );
  my $error = $cust_main->recharge_prepay( $p->{'prepaid_cardnum'},
                                           \$amount,
                                           \$seconds,
                                           \$upbytes,
                                           \$downbytes,
                                           \$totalbytes,
                                         );

  return { 'error' => $error } if $error;

  return { 'error'     => '',
           'amount'    => $amount,
           'seconds'   => $seconds,
           'duration'  => duration_exact($seconds),
           'upbytes'   => $upbytes,
           'upload'    => FS::UI::bytecount::bytecount_unexact($upbytes),
           'downbytes' => $downbytes,
           'download'  => FS::UI::bytecount::bytecount_unexact($downbytes),
           'totalbytes'=> $totalbytes,
           'totalload' => FS::UI::bytecount::bytecount_unexact($totalbytes),
         };

}

sub invoice {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $invnum = $p->{'invnum'};

  my $cust_bill = qsearchs('cust_bill', { 'invnum'  => $invnum,
                                          'custnum' => $custnum } )
    or return { 'error' => "Can't find invnum" };

  #my %return;

  return { 'error'        => '',
           'invnum'       => $invnum,
           'invoice_text' => join('', $cust_bill->print_text ),
           'invoice_html' => $cust_bill->print_html( { unsquelch_cdr => 1 } ),
         };

}

sub invoice_logo {
  my $p = shift;

  #sessioning for this?  how do we get the session id to the backend invoice
  # template so it can add it to the link, blah

  my $agentnum = '';
  if ( $p->{'invnum'} ) {
    my $cust_bill = qsearchs('cust_bill', { 'invnum' => $p->{'invnum'} } )
      or return { 'error' => 'unknown invnum' };
    $agentnum = $cust_bill->cust_main->agentnum;
  }

  my $templatename = $p->{'template'} || $p->{'templatename'};

  #false laziness-ish w/view/cust_bill-logo.cgi

  my $conf = new FS::Conf;
  if ( $templatename =~ /^([^\.\/]*)$/ && $conf->exists("logo_$1.png") ) {
    $templatename = "_$1";
  } else {
    $templatename = '';
  }

  my $filename = "logo$templatename.png";

  return { 'error'        => '',
           'logo'         => $conf->config_binary($filename, $agentnum),
           'content_type' => 'image/png', #should allow gif, jpg too
         };
}


sub list_invoices {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my @cust_bill = $cust_main->cust_bill;

  return  { 'error'       => '',
            'invoices'    =>  [ map { { 'invnum' => $_->invnum,
                                        '_date'  => $_->_date,
                                      }
                                    } @cust_bill
                              ]
          };
}

sub cancel {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my @errors = $cust_main->cancel( 'quiet'=>1 );

  my $error = scalar(@errors) ? join(' / ', @errors) : '';

  return { 'error' => $error };

}

sub list_pkgs {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  #return { 'cust_pkg' => [ map { $_->hashref } $cust_main->ncancelled_pkgs ] };

  my $conf = new FS::Conf;

  { 'svcnum'   => $session->{'svcnum'},
    'custnum'  => $custnum,
    'cust_pkg' => [ map {
                          { $_->hash,
                            $_->part_pkg->hash,
                            part_svc =>
                              [ map $_->hashref, $_->available_part_svc ],
                            cust_svc => 
                              [ map { my $ref = { $_->hash,
                                                  label => [ $_->label ],
                                                };
                                      $ref->{_password} = $_->svc_x->_password
                                        if $context eq 'agent'
                                        && $conf->exists('agent-showpasswords')
                                        && $_->part_svc->svcdb eq 'svc_acct';
                                      $ref;
                                    } $_->cust_svc
                              ],
                          };
                        } $cust_main->ncancelled_pkgs
                  ],
    'small_custview' =>
      small_custview( $cust_main, $conf->config('countrydefault') ),
  };

}

sub list_svcs {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my @cust_svc = ();
  #foreach my $cust_pkg ( $cust_main->ncancelled_pkgs ) {
  foreach my $cust_pkg ( $p->{'ncancelled'} 
                         ? $cust_main->ncancelled_pkgs
                         : $cust_main->unsuspended_pkgs ) {
    next if $session->{'pkgnum'} && $cust_pkg->pkgnum != $session->{'pkgnum'};
    push @cust_svc, @{[ $cust_pkg->cust_svc ]}; #@{[ ]} to force array context
  }
  if ( $p->{'svcdb'} ) {
    my $svcdb = ref($p->{'svcdb'}) eq 'HASH'
                  ? $p->{'svcdb'}
                  : ref($p->{'svcdb'}) eq 'ARRAY'
                    ? { map { $_=>1 } @{ $p->{'svcdb'} } }
                    : { $p->{'svcdb'} => 1 };
    @cust_svc = grep $svcdb->{ $_->part_svc->svcdb }, @cust_svc
  }

  #@svc_x = sort { $a->domain cmp $b->domain || $a->username cmp $b->username }
  #              @svc_x;

  { 
    'svcnum'   => $session->{'svcnum'},
    'custnum'  => $custnum,
    'svcs'     => [
      map { 
            my $svc_x = $_->svc_x;
            my($label, $value) = $_->label;
            my $svcdb = $_->part_svc->svcdb;
            my $part_pkg = $_->cust_pkg->part_pkg;

            my %hash = (
              'svcnum' => $_->svcnum,
              'svcdb'  => $svcdb,
              'label'  => $label,
              'value'  => $value,
            );

            if ( $svcdb eq 'svc_acct' ) {
              %hash = (
                %hash,
                'username'   => $svc_x->username,
                'email'      => $svc_x->email,
                'seconds'    => $svc_x->seconds,
                'upbytes'    => display_bytecount($svc_x->upbytes),
                'downbytes'  => display_bytecount($svc_x->downbytes),
                'totalbytes' => display_bytecount($svc_x->totalbytes),

                'recharge_amount'  => $part_pkg->option('recharge_amount',1),
                'recharge_seconds' => $part_pkg->option('recharge_seconds',1),
                'recharge_upbytes'    =>
                  display_bytecount($part_pkg->option('recharge_upbytes',1)),
                'recharge_downbytes'  =>
                  display_bytecount($part_pkg->option('recharge_downbytes',1)),
                'recharge_totalbytes' =>
                  display_bytecount($part_pkg->option('recharge_totalbytes',1)),
                # more...
              );

            } elsif ( $svcdb eq 'svc_phone' ) {
              %hash = (
                %hash,
              );
            }

            \%hash;
          }
          @cust_svc
    ],
  };

}

sub _list_svc_usage {
  my($svc_acct, $begin, $end) = @_;
  my @usage = ();
  foreach my $part_export ( 
    map { qsearch ( 'part_export', { 'exporttype' => $_ } ) }
    qw( sqlradius sqlradius_withdomain )
  ) {
    push @usage, @ { $part_export->usage_sessions($begin, $end, $svc_acct) };
  }
  (@usage);
}

sub list_svc_usage {
  _usage_details(\&_list_svc_usage, @_);
}

sub _list_support_usage {
  my($svc_acct, $begin, $end) = @_;
  my @usage = ();
  foreach ( grep { $begin <= $_->_date && $_->_date <= $end }
            qsearch('acct_rt_transaction', { 'svcnum' => $svc_acct->svcnum })
          ) {
    push @usage, { 'seconds'  => $_->seconds,
                   'support'  => $_->support,
                   '_date'    => $_->_date,
                   'id'       => $_->transaction_id,
                   'creator'  => $_->creator,
                   'subject'  => $_->subject,
                   'status'   => $_->status,
                   'ticketid' => $_->ticketid,
                 };
  }
  (@usage);
}

sub list_support_usage {
  _usage_details(\&_list_support_usage, @_);
}

sub _list_cdr_usage {
  my($svc_phone, $begin, $end) = @_;
  map [ $_->downstream_csv('format' => 'default') ], #XXX config for format
      $svc_phone->cust_svc->get_cdrs( 'begin'=>$begin, 'end'=>$end, );
}

sub list_cdr_usage {
  my $p = shift;
  _usage_details( \&_list_cdr_usage, $p,
                  'svcdb' => 'svc_phone',
                );
}

sub _usage_details {
  my($callback, $p, %opt) = @_;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'svcnum' => $p->{'svcnum'} };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';

  my $svcdb = $opt{'svcdb'} || 'svc_acct';

  my $svc_x = qsearchs( $svcdb, $search );
  return { 'error' => 'No service selected in list_svc_usage' } 
    unless $svc_x;

  my $header = $svcdb eq 'svc_phone'
                 ? [ split(',', FS::cdr::invoice_header('default') ) ]  #XXX
                 : [];

  my $cust_pkg = $svc_x->cust_svc->cust_pkg;
  my $freq     = $cust_pkg->part_pkg->freq;
  my $start    = $cust_pkg->setup;
  #my $end      = $cust_pkg->bill; # or time?
  my $end      = time;

  unless ( $p->{beginning} ) {
    $p->{beginning} = $cust_pkg->last_bill;
    $p->{ending}    = $end;
  }

  my (@usage) = &$callback($svc_x, $p->{beginning}, $p->{ending});

  #kinda false laziness with FS::cust_main::bill, but perhaps
  #we should really change this bit to DateTime and DateTime::Duration
  #
  #change this bit to use Date::Manip? CAREFUL with timezones (see
  # mailing list archive)
  my ($nsec,$nmin,$nhour,$nmday,$nmon,$nyear) =
    (localtime($p->{ending}) )[0,1,2,3,4,5];
  my ($psec,$pmin,$phour,$pmday,$pmon,$pyear) =
    (localtime($p->{beginning}) )[0,1,2,3,4,5];

  if ( $freq =~ /^\d+$/ ) {
    $nmon += $freq;
    until ( $nmon < 12 ) { $nmon -= 12; $nyear++; }
    $pmon -= $freq;
    until ( $pmon >= 0 ) { $pmon += 12; $pyear--; }
  } elsif ( $freq =~ /^(\d+)w$/ ) {
    my $weeks = $1;
    $nmday += $weeks * 7;
    $pmday -= $weeks * 7;
  } elsif ( $freq =~ /^(\d+)d$/ ) {
    my $days = $1;
    $nmday += $days;
    $pmday -= $days;
  } elsif ( $freq =~ /^(\d+)h$/ ) {
    my $hours = $1;
    $nhour += $hours;
    $phour -= $hours;
  } else {
    return { 'error' => "unparsable frequency: ". $freq };
  }
  
  my $previous  = timelocal_nocheck($psec,$pmin,$phour,$pmday,$pmon,$pyear);
  my $next      = timelocal_nocheck($nsec,$nmin,$nhour,$nmday,$nmon,$nyear);

  { 
    'error'     => '',
    'svcnum'    => $p->{svcnum},
    'beginning' => $p->{beginning},
    'ending'    => $p->{ending},
    'previous'  => ($previous > $start) ? $previous : $start,
    'next'      => ($next < $end) ? $next : $end,
    'header'    => $header,
    'usage'     => \@usage,
  };
}

sub order_pkg {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $status = $cust_main->status;
  #false laziness w/ClientAPI/Signup.pm

  my $cust_pkg = new FS::cust_pkg ( {
    'custnum' => $custnum,
    'pkgpart' => $p->{'pkgpart'},
  } );
  my $error = $cust_pkg->check;
  return { 'error' => $error } if $error;

  my @svc = ();
  unless ( $p->{'svcpart'} eq 'none' ) {

    my $svcdb;
    my $svcpart = '';
    if ( $p->{'svcpart'} =~ /^(\d+)$/ ) {
      $svcpart = $1;
      my $part_svc = qsearchs('part_svc', { 'svcpart' => $svcpart } );
      return { 'error' => "Unknown svcpart $svcpart" } unless $part_svc;
      $svcdb = $part_svc->svcdb;
    } else {
      $svcdb = 'svc_acct';
    }
    $svcpart ||= $cust_pkg->part_pkg->svcpart($svcdb);

    my %fields = (
      'svc_acct'     => [ qw( username domsvc _password sec_phrase popnum ) ],
      'svc_domain'   => [ qw( domain ) ],
      'svc_phone'    => [ qw( phonenum pin sip_password phone_name ) ],
      'svc_external' => [ qw( id title ) ],
    );
  
    my $svc_x = "FS::$svcdb"->new( {
      'svcpart'   => $svcpart,
      map { $_ => $p->{$_} } @{$fields{$svcdb}}
    } );
    
    if ( $svcdb eq 'svc_acct' ) {
      my @acct_snarf;
      my $snarfnum = 1;
      while ( length($p->{"snarf_machine$snarfnum"}) ) {
        my $acct_snarf = new FS::acct_snarf ( {
          'machine'   => $p->{"snarf_machine$snarfnum"},
          'protocol'  => $p->{"snarf_protocol$snarfnum"},
          'username'  => $p->{"snarf_username$snarfnum"},
          '_password' => $p->{"snarf_password$snarfnum"},
        } );
        $snarfnum++;
        push @acct_snarf, $acct_snarf;
      }
      $svc_x->child_objects( \@acct_snarf );
    }
    
    my $y = $svc_x->setdefault; # arguably should be in new method
    return { 'error' => $y } if $y && !ref($y);
  
    $error = $svc_x->check;
    return { 'error' => $error } if $error;

    push @svc, $svc_x;

  }

  use Tie::RefHash;
  tie my %hash, 'Tie::RefHash';
  %hash = ( $cust_pkg => \@svc );
  #msgcat
  $error = $cust_main->order_pkgs( \%hash, '', 'noexport' => 1 );
  return { 'error' => $error } if $error;

  my $conf = new FS::Conf;
  if ( $conf->exists('signup_server-realtime') ) {

    my $bill_error = _do_bop_realtime( $cust_main, $status );

    if ($bill_error) {
      $cust_pkg->cancel('quiet'=>1);
      return $bill_error;
    } else {
      $cust_pkg->reexport;
    }

  } else {
    $cust_pkg->reexport;
  }

  return { error => '', pkgnum => $cust_pkg->pkgnum };

}

sub change_pkg {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $status = $cust_main->status;
  my $cust_pkg = qsearchs('cust_pkg', { 'pkgnum' => $p->{pkgnum} } )
    or return { 'error' => "unknown package $p->{pkgnum}" };

  my @newpkg;
  my $error = FS::cust_pkg::order( $custnum,
                                   [$p->{pkgpart}],
                                   [$p->{pkgnum}],
                                   \@newpkg,
                                 );

  my $conf = new FS::Conf;
  if ( $conf->exists('signup_server-realtime') ) {

    my $bill_error = _do_bop_realtime( $cust_main, $status );

    if ($bill_error) {
      $newpkg[0]->suspend;
      return $bill_error;
    } else {
      $newpkg[0]->reexport;
    }

  } else {  
    $newpkg[0]->reexport;
  }

  return { error => '', pkgnum => $cust_pkg->pkgnum };

}

sub order_recharge {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $status = $cust_main->status;
  my $cust_svc = qsearchs( 'cust_svc', { 'svcnum' => $p->{'svcnum'} } )
    or return { 'error' => "unknown service " . $p->{'svcnum'} };

  my $svc_x = $cust_svc->svc_x;
  my $part_pkg = $cust_svc->cust_pkg->part_pkg;

  my %vhash =
    map { $_ =~ /^recharge_(.*)$/; $1, $part_pkg->option($_, 1) } 
    qw ( recharge_seconds recharge_upbytes recharge_downbytes
         recharge_totalbytes );
  my $amount = $part_pkg->option('recharge_amount', 1); 
  
  my ($l, $v, $d) = $cust_svc->label;  # blah
  my $pkg = "Recharge $v"; 

  my $bill_error = $cust_main->charge($amount, $pkg,
     "time: $vhash{seconds}, up: $vhash{upbytes}," . 
     "down: $vhash{downbytes}, total: $vhash{totalbytes}",
     $part_pkg->taxclass); #meh

  my $conf = new FS::Conf;
  if ( $conf->exists('signup_server-realtime') && !$bill_error ) {

    $bill_error = _do_bop_realtime( $cust_main, $status );

    if ($bill_error) {
      return $bill_error;
    } else {
      my $error = $svc_x->recharge (\%vhash);
      return { 'error' => $error } if $error;
    }

  } else {  
    my $error = $bill_error;
    $error ||= $svc_x->recharge (\%vhash);
    return { 'error' => $error } if $error;
  }

  return { error => '', svc => $cust_svc->part_svc->svc };

}

sub _do_bop_realtime {
  my ($cust_main, $status) = (shift, shift);

    my $old_balance = $cust_main->balance;

    my $bill_error =    $cust_main->bill
                     || $cust_main->apply_payments_and_credits
                     || $cust_main->collect('realtime' => 1);

    if (    $cust_main->balance > $old_balance
         && $cust_main->balance > 0
         && ( $cust_main->payby !~ /^(BILL|DCRD|DCHK)$/ ?
              1 : $status eq 'suspended' ) ) {
      #this makes sense.  credit is "un-doing" the invoice
      my $conf = new FS::Conf;
      $cust_main->credit( sprintf("%.2f", $cust_main->balance - $old_balance ),
                          'self-service decline',
                          'reason_type' => $conf->config('signup_credit_type'),
                        );
      $cust_main->apply_credits( 'order' => 'newest' );

      return { 'error' => '_decline', 'bill_error' => $bill_error };
    }

    '';
}

sub renew_info {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my @cust_pkg = sort { $a->bill <=> $b->bill }
                 grep { $_->part_pkg->freq ne '0' }
                 $cust_main->ncancelled_pkgs;

  #return { 'error' => 'No active packages to renew.' } unless @cust_pkg;

  my $total = $cust_main->balance;

  my @array = map {
                    my $bill = $_->bill;
                    $total += $_->part_pkg->base_recur($_, \$bill);
                    my $renew_date = $_->part_pkg->add_freq($_->bill);
                    {
                      'pkgnum'             => $_->pkgnum,
                      'amount'             => sprintf('%.2f', $total),
                      'bill_date'          => $_->bill,
                      'bill_date_pretty'   => time2str('%x', $_->bill),
                      'renew_date'         => $renew_date,
                      'renew_date_pretty'  => time2str('%x', $renew_date),
                      'expire_date'        => $_->expire,
                      'expire_date_pretty' => time2str('%x', $_->expire),
                    };
                  }
                  @cust_pkg;

  return { 'dates' => \@array };

}

sub payment_info_renew_info {
  my $p = shift;
  my $renew_info   = renew_info($p);
  my $payment_info = payment_info($p);
  return { %$renew_info,
           %$payment_info,
         };
}

sub order_renew {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $date = $p->{'date'};

  my $now = time;

  #freeside-daily -n -d $date fs_daily $custnum
  $cust_main->bill_and_collect( 'time'         => $date,
                                'invoice_time' => $now,
                                'actual_time'  => $now,
                                'check_freq'   => '1d',
                              );

  return { 'error' => '' };

}

sub cancel_pkg {
  my $p = shift;
  my $session = _cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $pkgnum = $p->{'pkgnum'};

  my $cust_pkg = qsearchs('cust_pkg', { 'custnum' => $custnum,
                                        'pkgnum'  => $pkgnum,   } )
    or return { 'error' => "unknown pkgnum $pkgnum" };

  my $error = $cust_pkg->cancel( 'quiet'=>1 );
  return { 'error' => $error };

}

sub provision_acct {
  my $p = shift;
  warn "provision_acct called\n"
    if $DEBUG;

  return { 'error' => gettext('passwords_dont_match') }
    if $p->{'_password'} ne $p->{'_password2'};
  return { 'error' => gettext('empty_password') }
    unless length($p->{'_password'});
 
  if ($p->{'domsvc'}) {
    my %domains = domain_select_hash FS::svc_acct(map { $_ => $p->{$_} }
                                                  qw ( svcpart pkgnum ) );
    return { 'error' => gettext('invalid_domain') }
      unless ($domains{$p->{'domsvc'}});
  }

  warn "provision_acct calling _provision\n"
    if $DEBUG;
  _provision( 'FS::svc_acct',
              [qw(username _password domsvc)],
              [qw(username _password domsvc)],
              $p,
              @_
            );
}

sub provision_external {
  my $p = shift;
  #_provision( 'FS::svc_external', [qw(id title)], [qw(id title)], $p, @_ );
  _provision( 'FS::svc_external',
              [],
              [qw(id title)],
              $p,
              @_
            );
}

sub _provision {
  my( $class, $fields, $return_fields, $p ) = splice(@_, 0, 4);
  warn "_provision called for $class\n"
    if $DEBUG;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $pkgnum = $p->{'pkgnum'};

  warn "searching for custnum $custnum pkgnum $pkgnum\n"
    if $DEBUG;
  my $cust_pkg = qsearchs('cust_pkg', { 'custnum' => $custnum,
                                        'pkgnum'  => $pkgnum,
                                                               } )
    or return { 'error' => "unknown pkgnum $pkgnum" };

  warn "searching for svcpart ". $p->{'svcpart'}. "\n"
    if $DEBUG;
  my $part_svc = qsearchs('part_svc', { 'svcpart' => $p->{'svcpart'} } )
    or return { 'error' => "unknown svcpart $p->{'svcpart'}" };

  warn "creating $class record\n"
    if $DEBUG;
  my $svc_x = $class->new( {
    'pkgnum'  => $p->{'pkgnum'},
    'svcpart' => $p->{'svcpart'},
    map { $_ => $p->{$_} } @$fields
  } );
  warn "inserting $class record\n"
    if $DEBUG;
  my $error = $svc_x->insert;

  unless ( $error ) {
    warn "finding inserted record for svcnum ". $svc_x->svcnum. "\n"
      if $DEBUG;
    $svc_x = qsearchs($svc_x->table, { 'svcnum' => $svc_x->svcnum })
  }

  my $return = { 'svc'   => $part_svc->svc,
                 'error' => $error,
                 map { $_ => $svc_x->get($_) } @$return_fields
               };
  warn "_provision returning ". Dumper($return). "\n"
    if $DEBUG;
  return $return;

}

sub part_svc_info {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $pkgnum = $p->{'pkgnum'};

  my $cust_pkg = qsearchs('cust_pkg', { 'custnum' => $custnum,
                                        'pkgnum'  => $pkgnum,
                                                               } )
    or return { 'error' => "unknown pkgnum $pkgnum" };

  my $svcpart = $p->{'svcpart'};

  my $pkg_svc = qsearchs('pkg_svc', { 'pkgpart' => $cust_pkg->pkgpart,
                                      'svcpart' => $svcpart,           } )
    or return { 'error' => "unknown svcpart $svcpart for pkgnum $pkgnum" };
  my $part_svc = $pkg_svc->part_svc;

  my $conf = new FS::Conf;

  return {
    'svc'     => $part_svc->svc,
    'svcdb'   => $part_svc->svcdb,
    'pkgnum'  => $pkgnum,
    'svcpart' => $svcpart,
    'custnum' => $custnum,

    'security_phrase' => 0, #XXX !
    'svc_acct_pop'    => [], #XXX !
    'popnum'          => '',
    'init_popstate'   => '',
    'popac'           => '',
    'acstate'         => '',

    'small_custview' =>
      small_custview( $cust_main, $conf->config('countrydefault') ),

  };

}

sub unprovision_svc {
  my $p = shift;

  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  my $search = { 'custnum' => $custnum };
  $search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  my $cust_main = qsearchs('cust_main', $search )
    or return { 'error' => "unknown custnum $custnum" };

  my $svcnum = $p->{'svcnum'};

  my $cust_svc = qsearchs('cust_svc', { 'svcnum'  => $svcnum, } )
    or return { 'error' => "unknown svcnum $svcnum" };

  return { 'error' => "Service $svcnum does not belong to customer $custnum" }
    unless $cust_svc->cust_pkg->custnum == $custnum;

  my $conf = new FS::Conf;

  return { 'svc'   => $cust_svc->part_svc->svc,
           'error' => $cust_svc->cancel,
           'small_custview' =>
             small_custview( $cust_main, $conf->config('countrydefault') ),
         };

}

sub myaccount_passwd {
  my $p = shift;
  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  return { 'error' => "New passwords don't match." }
    if $p->{'new_password'} ne $p->{'new_password2'};

  return { 'error' => 'Enter new password' }
    unless length($p->{'new_password'});

  #my $search = { 'custnum' => $custnum };
  #$search->{'agentnum'} = $session->{'agentnum'} if $context eq 'agent';
  $custnum =~ /^(\d+)$/ or die "illegal custnum";
  my $search = " AND custnum = $1";
  $search .= " AND agentnum = ". $session->{'agentnum'} if $context eq 'agent';

  my $svc_acct = qsearchs( {
    'table'     => 'svc_acct',
    'addl_from' => 'LEFT JOIN cust_svc  USING ( svcnum  ) '.
                   'LEFT JOIN cust_pkg  USING ( pkgnum  ) '.
                   'LEFT JOIN cust_main USING ( custnum ) ',
    'hashref'   => { 'svcnum' => $p->{'svcnum'}, },
    'extra_sql' => $search, #important
  } )
    or return { 'error' => "Service not found" };

  $svc_acct->_password($p->{'new_password'});
  my $error = $svc_acct->replace();

  my($label, $value) = $svc_acct->cust_svc->label;

  return { 'error' => $error,
           'label' => $label,
           'value' => $value,
         };

}

sub create_ticket {
  my $p = shift;
  my($context, $session, $custnum) = _custoragent_session_custnum($p);
  return { 'error' => $session } if $context eq 'error';

  warn "$me create_ticket: initializing ticket system\n" if $DEBUG;
  FS::TicketSystem->init();

  my $conf = new FS::Conf;
  my $queue = $p->{'queue'}
              || $conf->config('ticket_system-selfservice_queueid')
              || $conf->config('ticket_system-default_queueid');

  warn "$me create_ticket: creating ticket\n" if $DEBUG;
  my $err_or_ticket = FS::TicketSystem->create_ticket(
    '', #create RT session based on FS CurrentUser (fs_selfservice)
    'queue'   => $queue,
    'custnum' => $custnum,
    'svcnum'  => $session->{'svcnum'},
    map { $_ => $p->{$_} } qw( requestor cc subject message )
  );

  if ( ref($err_or_ticket) ) {
    warn "$me create_ticket: sucessful: ". $err_or_ticket->id. "\n"
      if $DEBUG;
    return { 'error'     => '',
             'ticket_id' => $err_or_ticket->id,
           };
  } else {
    warn "$me create_ticket: unsucessful: $err_or_ticket\n"
      if $DEBUG;
    return { 'error' => $err_or_ticket };
  }


}

#--

sub _custoragent_session_custnum {
  my $p = shift;

  my($context, $session, $custnum);
  if ( $p->{'session_id'} ) {

    $context = 'customer';
    $session = _cache->get($p->{'session_id'})
      or return ( 'error' => "Can't resume session" ); #better error message
    $custnum = $session->{'custnum'};

  } elsif ( $p->{'agent_session_id'} ) {

    $context = 'agent';
    my $agent_cache = new FS::ClientAPI_SessionCache( {
      'namespace' => 'FS::ClientAPI::Agent',
    } );
    $session = $agent_cache->get($p->{'agent_session_id'})
      or return ( 'error' => "Can't resume session" ); #better error message
    $custnum = $p->{'custnum'};

  } else {
    return ( 'error' => "Can't resume session" ); #better error message
  }

  ($context, $session, $custnum);

}

1;

