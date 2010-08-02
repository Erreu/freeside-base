package FS::part_pkg::energy_base_discount_tiers;

use strict;
use vars qw(@ISA %info %penalty_fee);
use DBI;
use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;
use FS::usage_elec;
use Date::Format;
use Date::Parse;
use Data::Dumper;


@ISA = qw(FS::part_pkg::flat);

tie %penalty_fee,'Tie::IxHash',
  '0'=>0,
  '0.05'=>0.05,
;


%info = (
  'name'       => 'Energy base discount tiers',
  'svc_elec_compatible' => 1,
  'fields'     => 
       {
         'description'    => 
             { 'name'    => 'Description printed on bill',
               'default' => 'SPECIAL BASE CHARGE DISCOUNT FOR TIERS USAGE',
             },
         'rate'=>
             { 'name'    => 'Tiers Discount Amount',
               'default' => '0-499:0.00;500-999:3.00;1000-:7.95',
             },
         'penalty'        => 
             { 'name'=>'Late fee',
               'type' =>'select',
               'select_options'=> \%penalty_fee,
             },
       },
  'fieldorder' => [ 'description', 'rate' ],
  'weight' => '70',
);

sub calc_recur {
  my($self, $cust_pkg ) = @_;
  my $date =0;

  # this fee is dependent on the existence of a base elecusage package existence
  # so let check if it exist.
  my $custnum = $cust_pkg->custnum;
  my $basic_engpkg_exist;
  my $usage_svcnum;
  my $lastdate;

  foreach my $cust_pkg_tmp ( qsearch(
                              {
                               'table'  => 'cust_pkg',
                               'hashref'=> { 'custnum' => $custnum },
                               'extra_sql' => 'ORDER BY pkgnum ASC' 
                              } )
                           ) {
    next if $cust_pkg_tmp->getfield('cancel');
    # -ctran 06/09/08
    # updated liteup
    next if $cust_pkg_tmp->getfield('susp');
    next if ($cust_pkg_tmp->getfield('pkgnum') == $cust_pkg->pkgnum);

    my $pkgnum = $cust_pkg_tmp->getfield('pkgnum');

    my $cust_svc_tmp = qsearchs('cust_svc',{'pkgnum' => $pkgnum});

    #check for keyword ESIID from svc_external
    if ($cust_svc_tmp) {
      my $svc_external = qsearchs('svc_external',{'svcnum'=>$cust_svc_tmp->svcnum});

      if ($svc_external) {
        if (!$basic_engpkg_exist && ($svc_external->title =~ /^ESIID$/i)) {
          $basic_engpkg_exist = 1;
          $usage_svcnum = $cust_svc_tmp->getfield('svcnum');
          $lastdate =$cust_pkg_tmp->last_bill ||0;
        }
      }
    }
    
  }

  # now let get the usage if a energy package exist
  if ($basic_engpkg_exist) {
    my  @usage_elecs=qsearch(
                       {
                        'table'    => 'usage_elec',
                        'hashref'  => { 'svcnum'  => $usage_svcnum,
    #                                    '_date'   => { 'op' => '>',
    #                                                   'value' => $lastdate
    #                                                 }
                                      },
                        'extra_sql' => 'ORDER BY _date DESC'
                       });

    
    if(defined($usage_elecs[0])) {
      my $usage = $usage_elecs[0]->getUsage;
      if ($usage) {
        my $rate = $self->option('rate');
        foreach my $tier (split(';',$rate)) {
          my ($range, $disc_val) = split(':',$tier);
          my ($min,$max) = split('-',$range); 
          #set default value
          #$min = 0 unless defined $min; 
	  if ($min) {
            if ($min <= $usage) {
              if ($max) {
                if ($usage <= $max) {
                  return (round($disc_val) * -1);
                }
              }
              else {
                #there no max
                return (round($disc_val) * -1);
              }
            }
          }
	  else {
            if ($max) {
              if ($usage <= $max) {
                return (round($disc_val) * -1);
             }
            }
            else {
              #there no max
              return (round($disc_val) * -1);
            }
	  }
        }#for 
      }
    }
  }

  return 0;  

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
