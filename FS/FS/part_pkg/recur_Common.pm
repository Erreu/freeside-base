package FS::part_pkg::recur_Common;

use strict;
use vars qw( @ISA %info %recur_method );
use Tie::IxHash;
use Time::Local;
use FS::part_pkg::flat;

@ISA = qw(FS::part_pkg::flat);

%info = ( 'disabled' => 1 ); #recur_Common not a usable price plan directly

tie %recur_method, 'Tie::IxHash',
  'anniversary'  => 'Charge the recurring fee at the frequency specified above',
  'prorate'      => 'Charge a prorated fee the first time (selectable billing date)',
  'subscription' => 'Charge the full fee for the first partial period (selectable billing date)',
;

sub base_recur {
  my $self = shift;
  $self->option('recur_fee', 1) || 0;
}

sub calc_recur_Common {
  my $self = shift;
  my($cust_pkg, $sdate, $details, $param ) = @_; #only need $sdate & $param

  my $charges = 0;

  if ( $param->{'increment_next_bill'} ) {

    my $recur_method = $self->option('recur_method', 1) || 'anniversary';
    
    $charges = $self->base_recur;
    $charges += $param->{'override_charges'} if $param->{'override_charges'};

    if ( $recur_method eq 'prorate' ) {
      my $cutoff_day = $self->option('cutoff_day') || 1;
      $charges = $self->calc_prorate(@_, $cutoff_day);
      $charges += $param->{'override_charges'} if $param->{'override_charges'};
    }
    elsif ( $recur_method eq 'anniversary' and 
            $self->option('sync_bill_date',1) ) {
      my $next_bill = $cust_pkg->cust_main->next_bill_date;
      if ( defined($next_bill) ) {
        my $cutoff_day = (localtime($next_bill))[3];
        $charges = $self->calc_prorate(@_, $cutoff_day);
        $charges += $param->{'override_charges'} if $param->{'override_charges'};
      }
    } 
    elsif ( $recur_method eq 'subscription' ) {

      my $cutoff_day = $self->option('cutoff_day', 1) || 1;
      my ($day, $mon, $year) = ( localtime($$sdate) )[ 3..5 ];

      if ( $day < $cutoff_day ) {
        if ( $mon == 0 ) { $mon=11; $year--; }
        else { $mon--; }
      }

      $$sdate = timelocal(0, 0, 0, $cutoff_day, $mon, $year);

    }#$recur_method eq 'subscription'

    $charges -= $self->calc_discount( $cust_pkg, $sdate, $details, $param );

  }#increment_next_bill

  return $charges;

}

1;
