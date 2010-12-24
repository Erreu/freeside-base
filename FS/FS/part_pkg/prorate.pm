package FS::part_pkg::prorate;

use strict;
use vars qw(@ISA %info);
use Time::Local qw(timelocal);
#use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;

@ISA = qw(FS::part_pkg::flat);

%info = (
  'name' => 'First partial month pro-rated, then flat-rate (selectable billing day)',
  'shortname' => 'Prorate (Nth of month billing)',
  'inherit_fields' => [ 'flat', 'usage_Mixin', 'global_Mixin' ],
  'fields' => {
    'recur_temporality' => {'disabled' => 1},
    'sync_bill_date' => {'disabled' => 1},
    'cutoff_day' => { 'name' => 'Billing Day (1 - 28)',
                      'default' => 1,
                    },

    'add_full_period'=> { 'name' => 'When prorating first month, also bill '.
                                    'for one full period after that',
                          'type' => 'checkbox',
                        },
    'prorate_round_day'=> {
                          'name' => 'When prorating first month, round to '.
                                    'the nearest full day',
                          'type' => 'checkbox',
                        },
  },
  'fieldorder' => [ 'cutoff_day', 'add_full_period', 'prorate_round_day' ],
  'freq' => 'm',
  'weight' => 20,
);

sub calc_recur {
  my $self = shift;
  my $cutoff_day = $self->option('cutoff_day') || 1;
  return $self->calc_prorate(@_, $cutoff_day) - $self->calc_discount(@_);
}

1;
