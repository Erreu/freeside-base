package FS::part_pkg::sesmon_minute;

use strict;
use vars qw(@ISA %info);
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;

@ISA = qw(FS::part_pkg::flat);

%info = (
  'name' => 'Base charge plus charge per-minute from the session monitor',
  'fields' => {
    'setup_fee' => { 'name' => 'Setup fee for this package',
                     'default' => 0,
                   },
    'recur_flat' => { 'name' => 'Base recurring fee for this package',
                      'default' => 0,
                    },
    'unused_credit' => { 'name' => 'Credit the customer for the unused portion'.
                                   ' of service at cancellation',
                         'type' => 'checkbox',
                       },
    'recur_included_min' => { 'name' => 'Minutes included',
                              'default' => 0,
                              },
    'recur_minly_charge' => { 'name' => 'Additional charge per minute',
                              'default' => 0,
                            },
  },
  'fieldorder' => [ 'setup_fee', 'recur_flat', 'unused_credit', 'recur_included_min', 'recur_minly_charge' ],
  #'setup' => 'what.setup_fee.value',
  #'recur' => '\'my $min = $cust_pkg->seconds_since($cust_pkg->bill || 0) / 60 - \' + what.recur_included_min.value + \'; $min = 0 if $min < 0; \' + what.recur_flat.value + \' + \' + what.recur_minly_charge.value + \' * $min;\'',
  'weight' => 80,
);


sub calc_recur {
  my( $self, $cust_pkg ) = @);
  my $min = $cust_pkg->seconds_since($cust_pkg->bill || 0) / 60;
  $min -= $self->option('recur_included_min');
  $min = 0 if $min < 0;

  $self->option('recur_flat') + $min * $self->option('recur_minly_charge');
}

sub is_free_options {
  qw( setup_fee recur_fee recur_minly_charge );
}

sub base_recur {
  my($self, $cust_pkg) = @_;
  $self->option('recur_flat');
}

1;
