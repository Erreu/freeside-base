package FS::part_pkg::residential_elec_generic;

use strict;
use vars qw(@ISA %info %penalty_fee $DEBUG);
use DBI;
use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;
use FS::usage_elec;

@ISA = qw(FS::part_pkg::flat);
$DEBUG = 0;

tie %penalty_fee,'Tie::IxHash',
  '0'=>0,
  '0.05'=>0.05,
;


%info = (
  'name' => 'Residential base package',
  'svc_elec_compatible' => 1,
  'fields' => {
    'setup_fee' => { 'name' => 'Setup fee for this package',
                     'default' => 0,
                   },
    'base_fee' => { 'name' => 'Base fee for this package',
                      'default' => 0,
                    },
    'rate' => { 'name' => 'Rate for customer',
                               'default' => 1,
                             },
    'rate1_discount' => { 'name'    => 'Discount rate #1 (blank=disable)',
                          'default' => '',
                        },
	'penalty' => { 'name'=>'Late fee',
                   'type' =>'select',
                  'select_options'=> \%penalty_fee,
        },
  },
  'fieldorder' => [ 'setup_fee', 'base_fee','rate', 'rate1_discount', 'penalty' ],
 'weight' => '70',
);

sub calc_recur {
  my($self, $cust_pkg ) = @_;
  my $date =0;
  # -cal 7/5/07 added debug comment to those line that tommy use for debugging
  #             then comment them out
  my  $cust_svc=qsearchs('cust_svc',{'pkgnum' => $cust_pkg->pkgnum});
  my $lastdate =$cust_pkg -> last_bill ||0;
  warn $lastdate."\n" if $DEBUG;
  warn $cust_svc->svcnum."\n" if $DEBUG;
  warn $cust_pkg->pkgnum."\n" if $DEBUG;
  my  @usage_elecs=qsearch('usage_elec',{'svcnum' => $cust_svc->svcnum,
					 '_date'=> { op=>'>', value=>$lastdate },
	                       'extra_sql' => 'ORDER BY _date_'});

  warn "test".@usage_elecs."\n" if $DEBUG;
  
  if(defined($usage_elecs[0])){
	warn "test2".$usage_elecs[0]->id."\n" if $DEBUG;
	warn $usage_elecs[0]->getUsage."usage\n" if $DEBUG;
	my $base=$self->option('base_fee');
	my $rate=$self->option('rate');
	my $sum= $base + ($usage_elecs[0]->getUsage)*$rate+$usage_elecs[0]->tdsp;
	warn $sum."\n" if $DEBUG;
	warn "$base * $rate = ".$base*$rate if $DEBUG;
	return round($sum);
	}
  return 0;  
  #$hours -= $self->option('recur_included_hours');
  #$hours = 0 if $hours < 0;

  #$self->option('recur_flat') + $hours * $self->option('recur_hourly_charge');
  #return 99;
}


sub is_free_options {
  qw( setup_fee recur_flat recur_unit_charge );
}

sub base_recur {
  my($self, $cust_pkg) = @_;
  $self->option('base_fee');
}

sub round {
    my($number) = shift;
    my $roundit= int($number*100 + .5);
	return sprintf('%.2f',$roundit/100)
}

1;
