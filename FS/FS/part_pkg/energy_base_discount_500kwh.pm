package FS::part_pkg::energy_base_discount_500kwh;

use strict;
use vars qw(@ISA %info %penalty_fee $DEBUG);
use DBI;
use FS::Record qw(qsearch qsearchs);
use FS::part_pkg::flat;
use FS::usage_elec;
use Date::Format;
use Date::Parse;
use Data::Dumper;


@ISA = qw(FS::part_pkg::flat);
$DEBUG = 0;

tie %penalty_fee,'Tie::IxHash',
  '0'=>0,
  '0.05'=>0.05,
;


%info = (
  'name'       => 'Energy base discount 500KWH',
  'svc_elec_compatible' => 1,
  'fields'     => 
       {
         'description'    => 
             { 'name'    => 'Description printed on bill',
               'default' => 'SPECIAL BASE CHARGE DISCOUNT FOR USAGE > 500KWH',
             },
         'rate'=>
             { 'name'    => 'Discount Amount',
               'default' => 4.95,
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

  warn "cust_pkg = '\n" .Dumper($cust_pkg). "'\n" if $DEBUG;

  #my  $cust_svc=qsearchs('cust_svc',{'pkgnum' => $cust_pkg->pkgnum});
  #my $lastdate =$cust_pkg -> last_bill ||0;

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
    warn "\tpkgnum = ". $pkgnum . "\n" if $DEBUG;

    my $cust_svc_tmp = qsearchs('cust_svc',{'pkgnum' => $pkgnum});
    warn "\t\tcust_svc_tmp = '" . Dumper($cust_pkg_tmp) . "'\n" if $DEBUG;

    #check for keyword ESIID from svc_external
    if ($cust_svc_tmp) {
      my $svc_external = qsearchs('svc_external',{'svcnum'=>$cust_svc_tmp->svcnum});

      if ($svc_external) {
        warn "\t\t\tsvc_external = '" . Dumper($svc_external) . "'\n" if $DEBUG;
        if (!$basic_engpkg_exist && ($svc_external->title =~ /^ESIID$/i)) {
          $basic_engpkg_exist = 1;
          $usage_svcnum = $cust_svc_tmp->getfield('svcnum');
          $lastdate =$cust_pkg_tmp->last_bill ||0;
        }
      }
    }
    
  }

  warn "custnum = " . $custnum . "\n" if $DEBUG;
  warn "lastdate='".time2str("%C",$lastdate)."'\n" if $DEBUG;
  warn "lastdate='".$lastdate."'\n" if $DEBUG;
  warn "usage_svcnum=".$usage_svcnum."\n" if $DEBUG;
  warn "basic_engpkg_exist = " . $basic_engpkg_exist . "\n" if $DEBUG;

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
	#warn "test2".@usage_elecs[0]->id."\n" if $DEBUG;
	warn "usage = " . $usage_elecs[0]->getUsage."\n" if $DEBUG;
	#my   $base=$self->option('base_fee');
	#my   $rate=$self->option('rate');
	#my   $sum= $base + (@usage_elecs[0]->getUsage)*$rate+@usage_elecs[0]->tdsp;
          if ($usage_elecs[0]->getUsage >= 500) {
            my $discount = $self->option('rate');
	    return (round($discount) * -1);
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
