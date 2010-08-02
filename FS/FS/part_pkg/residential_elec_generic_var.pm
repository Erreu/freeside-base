package FS::part_pkg::residential_elec_generic_var;

use strict;
use vars qw(@ISA %info %penalty_fee);
use Date::Format;
use Data::Dumper;
use DBI;
use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;
use FS::usage_elec;

@ISA = qw(FS::part_pkg::flat);

tie %penalty_fee,'Tie::IxHash',
  '0'=>0,
  '0.05'=>0.05,
;


%info = (
  'name' => 'Residential base package var',
  'svc_elec_compatible' => 1,
  'fields' => {
    'setup_fee' => { 'name' => 'Setup fee for this package',
                     'default' => 0,
                   },
    'base_fee' => { 'name' => 'Base fee for this package',
                      'default' => 0,
                    },
    'rate' => { 'name' => 'Default Rate for customer',
                          'default' => '0.12',
                             },
    'vrate' => { 'name' => 'Variable Rate (blank=disable)',
                          'default' => '2008-01:0.12;2009-01:0.12',
                             },
    'rate1_discount' => { 'name'    => 'Discount rate #1 (blank=disable)',
                          'default' => '',
                        },
	'penalty' => { 'name'=>'Late fee',
                   'type' =>'select',
                  'select_options'=> \%penalty_fee,
        },
  },
  'fieldorder' => [ 'setup_fee', 'base_fee','rate', 'vrate', 'rate1_discount', 'penalty' ],
 'weight' => '70',
);

sub calc_recur {
  my($self, $cust_pkg ) = @_;
  my $date =0;
  # -cal 7/5/07 added debug comment to those line that tommy use for debugging
  #             then comment them out

  # generate the variable rate hash
  my $vrate=$self->option('vrate');
  my %var_rate;
  if ($vrate) {
    foreach my $rate_frame (split(';',$vrate)) {
      my ($period, $period_rate) = split(':',$rate_frame);
      my ($yr,$mo) = split('-',$period);
      $var_rate{$yr}{$mo} = $period_rate;
    }
  }
  

  my  $cust_svc=qsearchs('cust_svc',{'pkgnum' => $cust_pkg->pkgnum});
  my $lastdate =$cust_pkg -> last_bill ||0;
  my  @usage_elecs=qsearch('usage_elec',{'svcnum' => $cust_svc->svcnum,
					 '_date'=> { op=>'>', value=>$lastdate },
	                       'extra_sql' => 'ORDER BY _date_'});

  if(defined($usage_elecs[0])){
	my $base=$self->option('base_fee');
	my $rate=$self->option('rate');
	# usage end date
	my $usage_enddate_year = time2str('%Y',$usage_elecs[0]->curr_date);
	my $usage_enddate_month = time2str('%m',$usage_elecs[0]->curr_date);
        #my $v_rate = $rate;
	if ($vrate) {
	  # if a variable rate
       	  $rate = $var_rate{$usage_enddate_year}{$usage_enddate_month} 
	            if (exists $var_rate{$usage_enddate_year}{$usage_enddate_month});
	}

        my $sum= $base + ($usage_elecs[0]->getUsage)*$rate+$usage_elecs[0]->tdsp;

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
