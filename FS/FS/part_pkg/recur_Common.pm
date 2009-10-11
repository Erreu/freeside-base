package FS::part_pkg::recur_Common;

use strict;
use vars qw( @ISA %info %recur_method );
use Tie::IxHash;
use Time::Local;
use FS::part_pkg::prorate;

@ISA = qw(FS::part_pkg::prorate);

%info = ( 'disabled' => 1 ); #recur_Common not a usable price plan directly

tie %recur_method, 'Tie::IxHash',
  'anniversary'  => 'Charge the recurring fee at the frequency specified above',
  'prorate'      => 'Charge a prorated fee the first time (selectable billing date)',
  'subscription' => 'Charge the full fee for the first partial period (selectable billing date)',
;

sub calc_recur_Common {
  my $self = shift;
  my($cust_pkg, $sdate, $details, $param ) = @_; #only need $sdate & $param

  my $charges = 0;

  if ( $param->{'increment_next_bill'} ) {

    my $recur_method = $self->option('recur_method', 1) || 'anniversary';
                  
    if ( $recur_method eq 'prorate' ) {

      $charges = $self->SUPER::calc_recur(@_);

    } else {

      $charges = $self->option('recur_fee');

      if ( $recur_method eq 'subscription' ) {

        my $cutoff_day = $self->option('cutoff_day', 1) || 1;
        my ($day, $mon, $year) = ( localtime($$sdate) )[ 3..5 ];

        if ( $day < $cutoff_day ) {
          if ( $mon == 0 ) { $mon=11; $year--; }
          else { $mon--; }
        }

        $$sdate = timelocal(0, 0, 0, $cutoff_day, $mon, $year);

      }#$recur_method eq 'subscription'

    }#$recur_method eq 'prorate'

  }#increment_next_bill

  $charges;

}

1;
