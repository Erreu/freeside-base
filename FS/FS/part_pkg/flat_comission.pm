package FS::part_pkg::flat_comission;

use strict;
use vars qw(@ISA %info);
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg;

@ISA = qw(FS::part_pkg);

%info = (
    'name' => 'Flat rate with recurring commission per (any) active package',
    'fields' => {
      'setup_fee' => { 'name' => 'Setup fee for this package',
                       'default' => 0,
                     },
      'recur_fee' => { 'name' => 'Recurring fee for this package',
                       'default' => 0,
                     },
      'comission_amount' => { 'name' => 'Commission amount per month (per active package)',
                              'default' => 0,
                            },
      'comission_depth'  => { 'name' => 'Number of layers',
                              'default' => 1,
                            },
    },
    'fieldorder' => [ 'setup_fee', 'recur_fee', 'comission_depth', 'comission_amount' ],
    #'setup' => 'what.setup_fee.value',
    #'recur' => '\'my $error = $cust_pkg->cust_main->credit( \' + what.comission_amount.value + \' * scalar($cust_pkg->cust_main->referral_cust_pkg(\' + what.comission_depth.value+ \')), "commission" ); die $error if $error; \' + what.recur_fee.value + \';\'',
    'weight' => 62,
);

sub calc_setup {
  my($self, $cust_pkg ) = @_;
  $self->option('setup_fee');
}

sub calc_recur {
  my($self, $cust_pkg ) = @_;

  my $amount = $self->option('comission_amount');
  my $num_active = scalar(
    $cust_pkg->cust_main->referral_cust_pkg( $self->option('comission_depth') )
  );

  my $error = $cust_pkg->cust_main->credit( $amount*$num_active, "commission" );
  die $error if $error;

  $self->option('recur_fee');
}

1;
