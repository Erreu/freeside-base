package FS::part_pkg::flat_delayed;

use strict;
use vars qw(@ISA %info);
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg;

@ISA = qw(FS::part_pkg);

%info = (
    'name' => 'Free (or setup fee) for X days, then flat rate'.
              ' (anniversary billing)',
    'fields' =>  {
      'setup_fee' => { 'name' => 'Setup fee for this package',
                       'default' => 0,
                     },
      'free_days' => { 'name' => 'Initial free days',
                       'default' => 0,
                     },
      'recur_fee' => { 'name' => 'Recurring fee for this package',
                       'default' => 0,
                      },
    },
    'fieldorder' => [ 'free_days', 'setup_fee', 'recur_fee' ],
    #'setup' => '\'my $d = $cust_pkg->bill || $time; $d += 86400 * \' + what.free_days.value + \'; $cust_pkg->bill($d); $cust_pkg_mod_flag=1; \' + what.setup_fee.value',
    #'recur' => 'what.recur_fee.value',
    'weight' => 50,
);

sub calc_setup {
  my($self, $cust_pkg, $time ) = @_;

  my $d = $cust_pkg->bill || $time;
  $d += 86400 * $self->option('free_days');
  $cust_pkg->bill($d);
  
  $self->option('setup_fee');
}

sub calc_recur {
  my($self, $cust_pkg ) = @_;
  $self->option('recur_fee');
}

1;
