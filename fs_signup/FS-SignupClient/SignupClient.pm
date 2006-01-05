package FS::SignupClient;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK $init_data); # $fs_signupd_socket);
use Exporter;
#use Socket;
#use FileHandle;
#use IO::Handle;
#use Storable qw(nstore_fd fd_retrieve);
use FS::SelfService; # qw( new_customer signup_info );

$VERSION = '0.04';

@ISA = qw( Exporter );
@EXPORT_OK = qw( signup_info new_customer regionselector expselect popselector);

=head1 NAME

FS::SignupClient - Freeside signup client API

=head1 SYNOPSIS

  use FS::SignupClient qw( signup_info new_customer );

  #this is the backwards-compatibility bit
  ( $locales, $packages, $pops, $real_signup_info ) = signup_info;

  #this is compatible with FS::SelfService::new_customer
  $error = new_customer ( {
    'first'            => $first,
    'last'             => $last,
    'ss'               => $ss,
    'comapny'          => $company,
    'address1'         => $address1,
    'address2'         => $address2,
    'city'             => $city,
    'county'           => $county,
    'state'            => $state,
    'zip'              => $zip,
    'country'          => $country,
    'daytime'          => $daytime,
    'night'            => $night,
    'fax'              => $fax,
    'payby'            => $payby,
    'payinfo'          => $payinfo,
    'paycvv'           => $paycvv,
    'paydate'          => $paydate,
    'payname'          => $payname,
    'invoicing_list'   => $invoicing_list,
    'referral_custnum' => $referral_custnum,
    'comments'         => $comments,
    'pkgpart'          => $pkgpart,
    'username'         => $username,
    '_password'        => $password,
    'sec_phrase'       => $sec_phrase,
    'popnum'           => $popnum,
    'agentnum'         => $agentnum, #optional
  } );

=head1 DESCRIPTION

This module provides an API for a remote signup server.

It needs to be run as the freeside user.  Because of this, the program which
calls these subroutines should be written very carefully.

=head1 SUBROUTINES

=over 4

=item signup_info

Returns three array references of hash references.

The first set of hash references is of allowable locales.  Each hash reference
has the following keys:
  taxnum
  state
  county
  country

The second set of hash references is of allowable packages.  Each hash
reference has the following keys:
  pkgpart
  pkg

The third set of hash references is of allowable POPs (Points Of Presence).
Each hash reference has the following keys:
  popnum
  city
  state
  ac
  exch

(Future expansion: fourth argument is the $init_data hash reference)

=cut

#compatibility bit
sub signup_info {

  $init_data = FS::SelfService::signup_info();

  (map { $init_data->{$_} } qw( cust_main_county part_pkg svc_acct_pop ) ),
  $init_data;

}

=item new_customer HASHREF

Adds a customer to the remote Freeside system.  Requires a hash reference as
a paramater with the following keys:
  first
  last
  ss
  comapny
  address1
  address2
  city
  county
  state
  zip
  country
  daytime
  night
  fax
  payby
  payinfo
  paycvv
  paydate
  payname
  invoicing_list
  referral_custnum
  comments
  pkgpart
  username
  _password
  sec_phrase
  popnum

Returns a scalar error message, or the empty string for success.

=cut

#compatibility bit
sub new_customer { 
  my $hash = FS::SelfService::new_customer(@_);
  $hash->{'error'};
}

=item regionselector SELECTED_COUNTY, SELECTED_STATE, SELECTED_COUNTRY, PREFIX, ONCHANGE

=cut

sub regionselector {
  my ( $selected_county, $selected_state, $selected_country,
       $prefix, $onchange ) = @_;
  signup_info() unless $init_data;
  FS::SelfService::regionselector({
    selected_county  => $selected_county,
    selected_state   => $selected_state,
    selected_country => $selected_country,
    prefix           => $prefix,
    onchange         => $onchange,
    default_country  => $init_data->{countrydefault},
    locales          => $init_data->{cust_main_county},
  });
    #default_state    => $init_data->{statedefault},
}

=item expselect PREFIX, DATE

=cut

sub expselect {
  FS::SelfService::expselect(@_);
}

=item popselector 

=cut

sub popselector {
  my( $popnum ) = @_;
  signup_info() unless $init_data;
  FS::SelfService::popselector({
    popnum => $popnum,
    pops   => $init_data->{svc_acct_pop},
  });
    #popac =>
    #acstate =>
}

=back

=head1 BUGS

This is just a wrapper around FS::SelfService functions for backwards
compatibility.  It is only necessary if you're using a signup.cgi from before
1.5.0pre7.

=head1 SEE ALSO

L<fs_signupd>, L<FS::cust_main>

=cut

1;

