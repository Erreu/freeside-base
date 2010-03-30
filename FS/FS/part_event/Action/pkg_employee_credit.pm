package FS::part_event::Action::pkg_employee_credit;

use strict;
use base qw( FS::part_event::Action::pkg_referral_credit );
use FS::Record qw(qsearchs);
use FS::access_user;

sub description { 'Credit the ordering employee a specific amount'; }

#a little false laziness w/pkg_referral_credit
sub do_action {
  my( $self, $cust_pkg ) = @_;

  my $cust_main = $self->cust_main($cust_pkg);

  #yuck.  this is why text $otaker is gone in 2.1
  my $otaker = $cust_pkg->otaker;
  my $employee = qsearchs('access_user', { 'username' => $otaker } )
    or return "No employee for username $otaker";
  return "No customer record for employee ". $employee->username
    unless $employee->user_custnum;

  my $employee_cust_main = $employee->user_cust_main;
    #? or return "No customer record for employee ". $employee->username;

  my $amount    = $self->_calc_credit($cust_pkg);
  return '' unless $amount > 0;

  my $reasonnum = $self->option('reasonnum');

  my $error = $employee_cust_main->credit(
    $amount, 
    \$reasonnum,
    'addlinfo' =>
      'for customer #'. $cust_main->display_custnum. ': '.$cust_main->name,
  );
  die "Error crediting customer ". $employee_cust_main->custnum.
      " for employee commission: $error"
    if $error;

}

1;
