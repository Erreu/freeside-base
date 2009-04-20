package FS::Cron::bill;

use strict;
use vars qw( @ISA @EXPORT_OK );
use Exporter;
use Date::Parse;
use FS::UID qw(dbh);
use FS::Record qw(qsearchs);
use FS::cust_main;

@ISA = qw( Exporter );
@EXPORT_OK = qw ( bill );

sub bill {

  my %opt = @_;

  my $debug = 0;
  $debug = 1 if $opt{'v'};
  $debug = $opt{'l'} if $opt{'l'};
 
  $FS::cust_main::DEBUG = $debug;
  #$FS::cust_event::DEBUG = $opt{'l'} if $opt{'l'};

  my @search = ();

  push @search, "cust_main.archived != 'Y' "; #disable?

  push @search, "cust_main.payby    = '". $opt{'p'}. "'"
    if $opt{'p'};
  push @search, "cust_main.agentnum =  ". $opt{'a'}
    if $opt{'a'};

  if ( @ARGV ) {
    push @search, "( ".
      join(' OR ', map "cust_main.custnum = $_", @ARGV ).
    " )";
  }

  ###
  # generate where_pkg / where_bill_event search clause (1.7-style)
  ###

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
  
  push @search, "( $where_pkg OR $where_bill_event )";

  ###
  # get a list of custnums
  ###

  warn "searching for customers:\n". join("\n", @search). "\n"
    if $opt{'v'} || $opt{'l'};

  my $sth = dbh->prepare(
    "SELECT custnum FROM cust_main".
    " WHERE ". join(' AND ', @search)
  ) or die dbh->errstr;

  $sth->execute or die $sth->errstr;

  my @custnums = map { $_->[0] } @{ $sth->fetchall_arrayref };

  ###
  # for each custnum, queue or make one customer object and bill
  # (one at a time, to reduce memory footprint with large #s of customers)
  ###
  
  foreach my $custnum ( @custnums ) {
  
    my %args = (
        'time'         => $time,
        'invoice_time' => $invoice_time,
        'actual_time'  => $^T, #when freeside-bill was started
                               #(not, when using -m, freeside-queued)
        'resetup'      => ( $opt{'s'} ? $opt{'s'} : 0 ),
    );

    if ( $opt{'m'} ) {

      #add job to queue that calls bill_and_collect with options
      my $queue = new FS::queue {
        'job'      => 'FS::cust_main::queued_bill',
        'priority' => 99, #don't get in the way of provisioning jobs
      };
      my $error = $queue->insert( 'custnum'=>$custnum, %args );

    } else {

      my $cust_main = qsearchs( 'cust_main', { 'custnum' => $custnum } );
      $cust_main->bill_and_collect( %args, 'debug' => $debug );

    }

  }

}

1;
