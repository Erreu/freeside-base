package FS::ClientAPI::MyAccount;

use strict;
use vars qw($cache);
use Digest::MD5 qw(md5_hex);
use Date::Format;
use Cache::SharedMemoryCache; #store in db?
use FS::CGI qw(small_custview); #doh
use FS::Conf;
use FS::Record qw(qsearchs);
use FS::svc_acct;
use FS::svc_domain;
use FS::cust_main;
use FS::cust_bill;
use FS::cust_pkg;

use FS::ClientAPI; #hmm
FS::ClientAPI->register_handlers(
  'MyAccount/login'            => \&login,
  'MyAccount/customer_info'    => \&customer_info,
  'MyAccount/edit_info'        => \&edit_info,
  'MyAccount/invoice'          => \&invoice,
  'MyAccount/cancel'           => \&cancel,
  'MyAccount/list_pkgs'        => \&list_pkgs,
  'MyAccount/order_pkg'        => \&order_pkg,
  'MyAccount/cancel_pkg'       => \&cancel_pkg,
  'MyAccount/charge'           => \&charge,
);

use vars qw( @cust_main_editable_fields );
@cust_main_editable_fields = qw(
  first last company address1 address2 city
    county state zip country daytime night fax
  ship_first ship_last ship_company ship_address1 ship_address2 ship_city
    ship_state ship_zip ship_country ship_daytime ship_night ship_fax
);

#store in db?
my $cache = new Cache::SharedMemoryCache( {
   'namespace' => 'FS::ClientAPI::MyAccount',
} );

#false laziness w/FS::ClientAPI::passwd::passwd
sub login {
  my $p = shift;

  my $svc_domain = qsearchs('svc_domain', { 'domain' => $p->{'domain'} } )
    or return { error => 'Domain '. $p->{'domain'}. ' not found' };

  my $svc_acct = qsearchs( 'svc_acct', { 'username'  => $p->{'username'},
                                         'domsvc'    => $svc_domain->svcnum, }
                         );
  return { error => 'User not found.' } unless $svc_acct;
  return { error => 'Incorrect password.' }
    unless $svc_acct->check_password($p->{'password'});

  my $session = {
    'svcnum' => $svc_acct->svcnum,
  };

  my $cust_pkg = $svc_acct->cust_svc->cust_pkg;
  if ( $cust_pkg ) {
    my $cust_main = $cust_pkg->cust_main;
    $session->{'custnum'} = $cust_main->custnum;
  }

  my $session_id;
  do {
    $session_id = md5_hex(md5_hex(time(). {}. rand(). $$))
  } until ( ! defined $cache->get($session_id) ); #just in case

  $cache->set( $session_id, $session, '1 hour' );

  return { 'error'      => '',
           'session_id' => $session_id,
         };
}

sub customer_info {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my %return;

  my $custnum = $session->{'custnum'};

  if ( $custnum ) { #customer record

    my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
      or return { 'error' => "unknown custnum $custnum" };

    $return{balance} = $cust_main->balance;

    my @open = map {
                     {
                       invnum => $_->invnum,
                       date   => time2str("%b %o, %Y", $_->_date),
                       owed   => $_->owed,
                     };
                   } $cust_main->open_cust_bill;
    $return{open_invoices} = \@open;

    my $conf = new FS::Conf;
    $return{small_custview} =
      small_custview( $cust_main, $conf->config('defaultcountry') );

    $return{name} = $cust_main->first. ' '. $cust_main->get('last');

    for (@cust_main_editable_fields) {
      $return{$_} = $cust_main->get($_);
    }

  } else { #no customer record

    my $svc_acct = qsearchs('svc_acct', { 'svcnum' => $session->{'svcnum'} } )
      or die "unknown svcnum";
    $return{name} = $svc_acct->email;

  }


  return { 'error'          => '',
           'custnum'        => $custnum,
           %return,
         };

}

sub edit_info {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'}
    or return { 'error' => "no customer record" };

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $new = new FS::cust_main { $cust_main->hash };
  $new->set( $_ => $p->{$_} )
    foreach grep { exists $p->{$_} } @cust_main_editable_fields;
  my $error = $new->replace($cust_main);
  return { 'error' => $error } if $error;
  #$cust_main = $new;
  
  return { 'error' => '' };
}

sub invoice {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
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
         };

}

sub cancel {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
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
  my $session = $cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  return { 'cust_pkg' => [ map { $_->hashref } $cust_main->ncancelled_pkgs ] };

}

sub order_pkg {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  #false laziness w/ClientAPI/Signup.pm

  my $cust_pkg = new FS::cust_pkg ( {
    'custnum' => $custnum,
    'pkgpart' => $p->{'pkgpart'},
  } );
  my $error = $cust_pkg->check;
  return { 'error' => $error } if $error;

  my $svc_acct = new FS::svc_acct ( {
    'svcpart'   => $p->{'svcpart'} || $cust_pkg->part_pkg->svcpart('svc_acct'),
    map { $_ => $p->{$_} }
      qw( username _password sec_phrase popnum ),
  } );

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
  $svc_acct->child_objects( \@acct_snarf );

  my $y = $svc_acct->setdefault; # arguably should be in new method
  return { 'error' => $y } if $y && !ref($y);

  $error = $svc_acct->check;
  return { 'error' => $error } if $error;

  use Tie::RefHash;
  tie my %hash, 'Tie::RefHash';
  %hash = ( $cust_pkg => [ $svc_acct ] );
  #msgcat
  $error = $cust_main->order_pkgs( \%hash, '', 'noexport' => 1 );
  return { 'error' => $error } if $error;

  my $conf = new FS::Conf;
  if ( $conf->exists('signup_server-realtime') ) {

    my $old_balance = $cust_main->balance;

    my $bill_error = $cust_main->bill;
    $cust_main->apply_payments;
    $cust_main->apply_credits;
    $bill_error = $cust_main->collect;

    if ( $cust_main->balance > $old_balance ) {
      $cust_pkg->cancel('quiet'=>1);
      return { 'error' => '_decline' };
    } else {
      $cust_pkg->reexport;
    }

  } else {
    $cust_pkg->reexport;
  }

  return { error => '', pkgnum => $cust_pkg->pkgnum };

}

sub cancel_pkg {
  my $p = shift;
  my $session = $cache->get($p->{'session_id'})
    or return { 'error' => "Can't resume session" }; #better error message

  my $custnum = $session->{'custnum'};

  my $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } )
    or return { 'error' => "unknown custnum $custnum" };

  my $pkgnum = $session->{'pkgnum'};

  my $cust_pkg = qsearchs('cust_pkg', { 'custnum' => $custnum,
                                        'pkgnum'  => $pkgnum,   } )
    or return { 'error' => "unknown pkgnum $pkgnum" };

  my $error = $cust_main->cancel( 'quiet'=>1 );
  return { 'error' => $error };

}

1;

