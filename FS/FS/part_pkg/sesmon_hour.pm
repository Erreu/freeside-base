package FS::part_pkg::sesmon_hour;

use strict;
use vars qw(@ISA %info);
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg;

@ISA = qw(FS::part_pkg);

%info = (
    'name' => 'Base charge plus charge per-hour from the session monitor',
    'fields' => {
      'setup_fee' => { 'name' => 'Setup fee for this package',
                       'default' => 0,
                     },
      'recur_flat' => { 'name' => 'Base monthly charge for this package',
                        'default' => 0,
                      },
      'recur_included_hours' => { 'name' => 'Hours included',
                                  'default' => 0,
                                },
      'recur_hourly_charge' => { 'name' => 'Additional charge per hour',
                                 'default' => 0,
                               },
    },
    'fieldorder' => [ 'setup_fee', 'recur_flat', 'recur_included_hours', 'recur_hourly_charge' ],
    #'setup' => 'what.setup_fee.value',
    #'recur' => '\'my $hours = $cust_pkg->seconds_since($cust_pkg->bill || 0) / 3600 - \' + what.recur_included_hours.value + \'; $hours = 0 if $hours < 0; \' + what.recur_flat.value + \' + \' + what.recur_hourly_charge.value + \' * $hours;\'',
    'weight' => 80,
);

sub calc_setup {
  my($self, $cust_pkg ) = @_;
  $self->option('setup_fee');
}

sub calc_recur {
  my($self, $cust_pkg ) = @_;

  my $hours = $cust_pkg->seconds_since($cust_pkg->bill || 0) / 3600;
  $hours -= $self->option('recur_included_hours');
  $hours = 0 if $hours < 0;

  $self->option('recur_flat') + $hours * $self->option('recur_hourly_charge');

}

1;
