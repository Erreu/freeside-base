package FS::Cron::bill;

use strict;
use vars qw( @ISA @EXPORT_OK );
use Exporter;
use Date::Parse;
use DBI 1.33; #The "clone" method was added in DBI 1.33. 
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

  push @search, "( cust_main.archived != 'Y' OR archived IS NULL )"; #disable?

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
    EXISTS( SELECT 1 FROM cust_pkg
              WHERE cust_main.custnum = cust_pkg.custnum
                AND (       cancel IS NULL     OR  cancel   = 0 )
                AND (      setup   IS NULL     OR  setup    = 0
                      OR   bill    IS NULL     OR  bill    <= $time 
                      OR ( expire  IS NOT NULL AND expire  <= $^T   )
                      OR ( adjourn IS NOT NULL AND adjourn <= $^T   )
                    )
          )
END
  
  # or
  my $where_bill_event = <<"END";
    EXISTS(
      SELECT 1 FROM cust_bill
        WHERE cust_main.custnum = cust_bill.custnum
          AND 0 < charged
                  - COALESCE(
                      ( SELECT SUM(amount) FROM cust_bill_pay
                          WHERE cust_bill.invnum = cust_bill_pay.invnum
                      ),0
                    )
                  - COALESCE(
                      ( SELECT SUM(amount) FROM cust_credit_bill
                          WHERE cust_bill.invnum = cust_credit_bill.invnum
                      ),0
                    )
          AND EXISTS(
            SELECT 1 FROM part_bill_event
              WHERE payby = cust_main.payby
                AND ( disabled is null or disabled = '' )
                AND seconds <= $time - cust_bill._date
                AND NOT EXISTS (
                  SELECT 1 FROM cust_bill_event
                    WHERE cust_bill.invnum = cust_bill_event.invnum
                      AND part_bill_event.eventpart = cust_bill_event.eventpart
                      AND status = 'done'
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

  my $cursor_dbh = dbh->clone;

  $cursor_dbh->do(
    "DECLARE cron_bill_cursor CURSOR FOR ".
    "  SELECT custnum FROM cust_main WHERE ". join(' AND ', @search)
  ) or die $cursor_dbh->errstr;
  
  while ( 1 ) {
  
    my $sth = $cursor_dbh->prepare('FETCH 1000 FROM cron_bill_cursor'); #mysql?
  
    $sth->execute or die $sth->errstr;

    my @custnums = map { $_->[0] } @{ $sth->fetchall_arrayref };

    last unless scalar(@custnums);

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

        if ( $opt{'r'} ) {
          warn "DRY RUN: would add custnum $custnum for queued_bill\n";
        } else {
          #add job to queue that calls bill_and_collect with options
          my $queue = new FS::queue {
            'job'      => 'FS::cust_main::queued_bill',
            'priority' => 99, #don't get in the way of provisioning jobs
          };
          my $error = $queue->insert( 'custnum'=>$custnum, %args );
        }

      } else {

        my $cust_main = qsearchs( 'cust_main', { 'custnum' => $custnum } );
        $cust_main->bill_and_collect( %args, 'debug' => $debug );

      }

    }

  }

  $cursor_dbh->commit or die $cursor_dbh->errstr;

}

1;
