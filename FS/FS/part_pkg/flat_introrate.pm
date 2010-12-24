package FS::part_pkg::flat_introrate;

use strict;
use vars qw(@ISA %info $DEBUG $me);
use FS::part_pkg::flat;

use Date::Manip qw(DateCalc UnixDate ParseDate);

@ISA = qw(FS::part_pkg::flat);
$me = '[' . __PACKAGE__ . ']';
$DEBUG = 0;

%info = (
  'name' => 'Introductory price for X months, then flat rate,'.
            'relative to setup date (anniversary billing)',
  'shortname' => 'Anniversary, with intro price',
  'inherit_fields' => [ 'flat', 'usage_Mixin', 'global_Mixin' ],
  'fields' => {
    'intro_fee' => { 'name' => 'Introductory recurring fee for this package',
                     'default' => 0,
                   },
    'intro_duration' =>
         { 'name' => 'Duration of the introductory period, in number of months',
           'default' => 0,
         },
  },
  'fieldorder' => [ qw(intro_duration intro_fee) ],
  'weight' => 14,
);

sub base_recur {
  my($self, $cust_pkg, $time ) = @_;

  my $now = $time ? $$time : time;

  my ($duration) = ($self->option('intro_duration') =~ /^(\d+)$/);
  unless ($duration) {
    die "Invalid intro_duration: " . $self->option('intro_duration');
  }

  my $setup = &ParseDate('epoch ' . $cust_pkg->getfield('setup'));
  my $intro_end = &DateCalc($setup, "+${duration} month");
  my $recur;

  warn "$me: \$duration = ${duration}" if $DEBUG;
  warn "$me: \$intro_end = ${intro_end}" if $DEBUG;
  warn "$me: $now < " . &UnixDate($intro_end, '%s') if $DEBUG;

  if ($now < &UnixDate($intro_end, '%s')) {
    $recur = $self->option('intro_fee');
  } else {
    $recur = $self->option('recur_fee');
  }

  $recur;

}


1;
