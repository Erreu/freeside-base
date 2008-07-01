package FS::Cron::bill;

use strict;
use vars qw( @ISA @EXPORT_OK );
use Exporter;
use Date::Parse;
use FS::Record qw(qsearch qsearchs);
use FS::cust_main;

@ISA = qw( Exporter );
@EXPORT_OK = qw ( bill );

sub bill {

  my %opt = @_;

  $FS::cust_main::DEBUG = 1 if $opt{'v'};
  
  my %search = ();
  $search{'payby'}    = $opt{'p'} if $opt{'p'};
  $search{'agentnum'} = $opt{'a'} if $opt{'a'};
  
  #we're at now now (and later).
  my($time)= $opt{'d'} ? str2time($opt{'d'}) : $^T;
  $time += $opt{'y'} * 86400 if $opt{'y'};

  my $invoice_time = $opt{'n'} ? $^T : $time;

  # select * from cust_main where
  my $where_pkg = <<"END";
    0 < ( select count(*) from cust_pkg
            where cust_main.custnum = cust_pkg.custnum
              and ( cancel is null or cancel = 0 )
              and (    setup is null or setup =  0
                    or bill  is null or bill  <= $time 
                    or ( expire is not null and expire <= $^T )
                    or ( adjourn is not null and adjourn <= $^T )
                  )
        )
END
  
  # or
  my $where_bill_event = <<"END";
    0 < ( select count(*) from cust_bill
            where cust_main.custnum = cust_bill.custnum
              and 0 < charged
                      - coalesce(
                                  ( select sum(amount) from cust_bill_pay
                                      where cust_bill.invnum = cust_bill_pay.invnum )
                                  ,0
                                )
                      - coalesce(
                                  ( select sum(amount) from cust_credit_bill
                                      where cust_bill.invnum = cust_credit_bill.invnum )
                                  ,0
                                )
              and 0 < ( select count(*) from part_bill_event
                          where payby = cust_main.payby
                            and ( disabled is null or disabled = '' )
                            and seconds <= $time - cust_bill._date
                            and 0 = ( select count(*) from cust_bill_event
                                       where cust_bill.invnum = cust_bill_event.invnum
                                         and part_bill_event.eventpart = cust_bill_event.eventpart
                                         and status = 'done'
                                    )
  
                      )
        )
END
  
  my $extra_sql = ( scalar(%search) ? ' AND ' : ' WHERE ' ). "( $where_pkg OR $where_bill_event )";
  
  my @cust_main;
  if ( @ARGV ) {
    @cust_main = map { qsearchs('cust_main', { custnum => $_, %search } ) } @ARGV
  } else {
    @cust_main = qsearch('cust_main', \%search, '', $extra_sql );
  }
  ;
  
  my($cust_main,%saw);
  foreach $cust_main ( @cust_main ) {

    my $custnum = $cust_main->custnum;
  
    # $^T not $time because -d is for pre-printing invoices
    foreach my $cust_pkg (
      grep { $_->expire && $_->expire <= $^T } $cust_main->ncancelled_pkgs
    ) {
      my $cpr = $cust_pkg->last_cust_pkg_reason('expire');
      my $error = $cust_pkg->cancel($cpr ? ( 'reason' => $cpr->reasonnum,
                                             'reason_otaker' => $cpr->otaker
                                           )
                                         : ()
                                   );
      warn "Error cancelling expired pkg ". $cust_pkg->pkgnum.
           " for custnum $custnum: $error"
        if $error;
    }
    # $^T not $time because -d is for pre-printing invoices
    foreach my $cust_pkg (
      grep { (    $_->part_pkg->is_prepaid && $_->bill && $_->bill < $^T
               || $_->adjourn && $_->adjourn <= $^T
             )
             && ! $_->susp
           }
           $cust_main->ncancelled_pkgs
    ) {
      my $cpr = $cust_pkg->last_cust_pkg_reason('adjourn')
        if ($cust_pkg->adjourn && $cust_pkg->adjourn < $^T);
      my $error = $cust_pkg->suspend($cpr ? ( 'reason' => $cpr->reasonnum,
                                              'reason_otaker' => $cpr->otaker
                                            )
                                          : ()
                                    );
      warn "Error suspending package ". $cust_pkg->pkgnum.
           " for custnum $custnum: $error"
        if $error;
    }
  
    my $error = $cust_main->bill( 'time'         => $time,
                                  'invoice_time' => $invoice_time,
                                  'resetup'      => $opt{'s'},
                                );
    warn "Error billing, custnum $custnum: $error" if $error;
  
    $error = $cust_main->apply_payments_and_credits;
    warn "Error applying payments and credits, custnum $custnum: $error"
      if $error;
  
    $error = $cust_main->collect( 'invoice_time' => $time,
                                  'freq'         => $opt{'freq'},
                                );
    warn "Error collecting, custnum $custnum: $error" if $error;
  
  }

}
