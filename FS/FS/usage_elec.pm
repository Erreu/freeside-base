package FS::usage_elec;

use strict;
use vars qw( @ISA @EXPORT_OK $me);
use FS::Record qw( qsearch qsearchs );
use FS::UID qw( getotaker dbh );
use FS::usage_elec_transaction867;
#use FS::cust_main;
use Exporter;
use List::Util qw[min max];
use Date::Format;
use HTTP::Date qw( str2time );
use Data::Dumper;
use Date::Calc qw(Delta_Days);
@ISA = qw(FS::Record Exporter);

@EXPORT_OK = qw( most_current_date curr_read edi_to_usage );

=head1 NAME

FS::usage_elec - Object methods for usage_elec records

=head1 SYNOPSIS

  use FS::usage_elec;

  $record = new FS::usage_elec \%hash;
  $record = new FS::usage_elec { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::usage_elec object represents an example.  FS::usage_elec inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item id - primary key

=item prev_date - 

=item curr_date - 

=item prev_read - 

=item curr_read - 

=item tdsp - 

=item svcnum - 

=item _date - 


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'usage_elec'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

# the insert method can be inherited from FS::Record

=item delete

Delete this record from the database.

=cut

# the delete method can be inherited from FS::Record

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

# the replace method can be inherited from FS::Record

=item check

Checks all fields to make sure this is a valid example.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('id')
    || $self->ut_numbern('prev_date')
    || $self->ut_numbern('curr_date')
    || $self->ut_number('prev_read')
    || $self->ut_number('curr_read')
    || $self->ut_money('tdsp')
    || $self->ut_number('svcnum')
    || $self->ut_numbern('_date')
    || $self->ut_float('meter_multiplier')
    || $self->ut_numbern('demand_measure')
    || $self->ut_numbern('demand_bill')
  ;
  return $error if $error;

  $self->SUPER::check;
}

=back

=head1 BUGS

The author forgot to customize this manpage.

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut
sub most_current_date {
 # my $self = shift;
  my $cust_nr=shift;
  my @custs = qsearch('usage_elec',{ 'cust_nr' => $cust_nr});

  my $most_current_date  = 0;
  
  if (@custs) {
    
    foreach my $cust (@custs) {
       if ($cust->curr_date > $most_current_date){
		$most_current_date = $cust;   
	}
    }
  }
  
  return $most_current_date;

}

sub getUsage{
        my $self = shift;
	return $self->total_usage;
}
#sub getUsage{
#	my $self = shift;
#    my $prev_read=$self->prev_read;
#	my $curr_read=$self->curr_read;
#        my $usage;
#	if ($prev_read<=$curr_read) {
#		$usage= ($curr_read-$prev_read);
#	}
#	else{
#		$usage=(($curr_read+10**max(length($prev_read),length($curr_read)))-$prev_read);
#	}
#	return $usage*$self->meter_multiplier;
#}

sub getNumberOfDays {
  my $self = shift;
  return Date::Calc::Delta_Days( time2str('%Y', $self->prev_date), 
                                 time2str('%L', $self->prev_date),
                                 time2str('%e', $self->prev_date), 
                                 time2str('%Y', $self->curr_date),
			         time2str('%L', $self->curr_date), 
                                 time2str('%e', $self->curr_date)
                               );
}


### insert into table
#
sub insert_usage {
  my $self = shift;
 
  my $debug = 0;
  my $error;
  
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';
 
  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $error = $self->check;
  return $error if $error;

  $error = $self->SUPER::insert;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    my $msg = "error: Can't insert data into usage_elec : $error\n"
             .Dumper($self);
    return $msg;
  }
 
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  return;
}

### Take in a time and convert it to time string to be entered into usage_elec
### the function use is str2time from module "HTTP::Date qw( str2time )"
sub to_usage_elec_time {
  my ($time) = shift;

  ### becareful using time2str, year allows are 1970-jan2038

  return str2time($time);
}


# Get the past 10 usage for a particular svcnum and return the object
# return:
#  array of usages object
#  undef otherwise
#
#

sub query_usage {
  my ($svcnum, $how_many) = @_;

  #$how_many = 10 unless $how_many; # default to 10 usages

#  my @usages  = qsearch ( 
#                          'usage_elec', 
#                          {
#
#                           'svcnum' => $svcnum,
#                           # sort in DESCending order so it easier to splice
#                           # the array in the next step
#                           'extra_sql' => 'ORDER BY _date DESC'
#                          }
#                        );

  my @usages = qsearch ( {
                          'table'   => 'usage_elec',
                          'hashref' => { 'svcnum' => $svcnum },
                          'extra_sql' => 'ORDER BY _date DESC'
                         } );

  # shrink the array to $how_many index if it over the requested number
  $#usages = $how_many - 1 if ( @usages && $how_many && (@usages > $how_many) );
    

  if (@usages) {
    # since we query the usage by DESCending order, it a good idea to put it 
    # in ascending order before a return.
    @usages = reverse @usages;
    return @usages;
  }

  return;
}


# sub routine that go through the transaction810 and transaction867 table
# to put data into usage_elec table
#
#
# some note
# to input data into usage_elect, all condition below must be meet
# 1. there is unprocess data from transaction810 table
# 2. there is unprocess data from transaction867 table
# 3. the unprocess data from transaction867 match transaction810
#    data.

sub edi_to_usage {
  my $self = shift;

  my $debug = 1;
  #my @invoices_to_generate; # store usage_elec svcnum 

  # Only send data to usage_elec if a transactin from 810 & 867 match up
  #
 
  # first thing first.  Let get all edi from transaction_810 table that haven't
  # been process
  my @edi_810_processeds = qsearch ( 
                            'transaction810', 
                            {'processed' => '0'}
                          );

  unless (@edi_810_processeds) {
    return "There were no un-process 810 to input into usage_elec.\n"
          ."Run again when there is 810 data to process\n";
  }

  # second, let get all edi from transaction_867 table that haven't been 
  # process
  my @edi_867_processeds = qsearch ( 
                            'transaction867', 
                            {'processed' => '0'}
                          );

  unless (@edi_867_processeds) {
    return "There were no un-process 867 to match up with 810 data.\n"
          ."Run again when there is 867 data to process\n";
  }

  # third, match up the 810 and 867 data.  Those data that match up, goes
  # into usage_elec table.

  ### for efficientcy we will use the smaller list to traverse
  if (@edi_810_processeds < @edi_867_processeds) {
    
    print "debug: using 810\n" if $debug;

    foreach my $edi_810 (@edi_810_processeds) {
      # find matching 867
      my $ref_identification_810 = $edi_810->ref_identification;
      my $srv_from_810 = $edi_810->srvc_from_date;
      my $srv_to_810 = $edi_810->srvc_to_date;
      ### search for the edi that match exactly with the 810
      my $edi_867 = qsearchs ( 'transaction867',
                               { 'ref_identification' => $ref_identification_810,
                                 'srvc_from_date'     => $srv_from_810,
                                 'srvc_to_date'       => $srv_to_810,
                               }
                            );
      if ($edi_867) {
        ### we have a match, extract the data and put into usage
        my $usage_elec_obj = extract_data_to_usage_elec ($edi_810, $edi_867);
        if ($usage_elec_obj) {

          ### mark the 810 and 867 as already process
          $edi_810->setfield('processed',1);
          $edi_867->setfield('processed',1);

          ### go ahead and billed 
          my $rtnval = billing_call($usage_elec_obj);
          if ($rtnval) {
            print "Oh! Oh!.. unable to bill svcnum: $usage_elec_obj->svcnum\n";
            print $rtnval;
            $edi_810->setfield('processed',0);
            $edi_867->setfield('processed',0);
            $usage_elec_obj->delete;
            return;
          }

        }
        else {
          print "RED ALERT.. something went wrong when inserting data\n"
               ."into usage_elec (810)\n";
          print "ref_identification of 810 : " . $edi_867->ref_identification
               ."\n";
          return;
        }

      }
    }
    
  }
  else {

    print "debug: using 867\n" if $debug;

    foreach my $edi_867 (@edi_867_processeds) {
      # find matching 810
      my $ref_identification_867 = $edi_867->ref_identification;
      my $srv_from_867 = $edi_867->srvc_period_start_date;
      my $srv_to_867 = $edi_867->srvc_period_end_date;
      print "(debug) ref_identification: $ref_identification_867\n" if $debug;
      ### search for the edi that match exactly with the 867
      my $edi_810 = qsearchs ( 'transaction810',
                               { 'ref_identification' => $ref_identification_867,
                                 'srvc_from_date'     => $srv_from_867,
                                 'srvc_to_date'       => $srv_to_867,
                               }
                             );
      if ($edi_810) {

        print "(debug) found an 810 that match the 867: esiid "
             .$edi_810->esiid."\n" if $debug;

        ### we have a match, extract the data and put into usage
        my $usage_elec_obj = extract_data_to_usage_elec($edi_810, $edi_867);
        if ($usage_elec_obj) {

          ### mark the 810 and 867 as already process
          my $edi_810_new = new FS::transaction810( { $edi_810->hash } );
          $edi_810_new->setfield('processed',1);
          my $error = $edi_810_new->replace($edi_810);
          if ($error) {
            print "there is an error changing column 'processed' of transaction810 table\n";
            print "error: $error\n";
          }

          my $edi_867_new = new FS::transaction867( { $edi_867->hash } );
          $edi_867->setfield('processed',1);
          $error = $edi_867_new->replace($edi_867);
          if ($error) {
            print "there is an error changing column 'processed' of transaction867 table\n";
            print "error: $error\n";
          }

          ### go ahead and billed 
          my $rtnval = billing_call($usage_elec_obj);
          if ($rtnval) {
            print "Oh! Oh!.. unable to bill svcnum: $usage_elec_obj->svcnum\n";
            print "$rtnval";
            $edi_810->setfield('processed',0);
            $edi_867->setfield('processed',0);
            $usage_elec_obj->delete;
            return;
          }
        }
        else {
          print "RED ALERT.. something went wrong when inserting data\n"
               ."into usage_elec (810)\n";
          print "ref_identification of 810 : " . $edi_810->ref_identification
               ."\n";
          #return;
        }
      }
    }

  }


}

# This subroutine does the physical adding of data into usage_elec
# using the transaction810 and transaction867 table

sub extract_data_to_usage_elec {
  my ($edi_810, $edi_867) = @_;

  ### variables declaration
  ### following decl are column of usage_elec
  my ($prev_date, $curr_date, $prev_read, $curr_read, $tdsp, $svcnum, $_date,
      $meter_multiplier, $total_usage, $measured_demand, $billed_demand,
      $meter_number);

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  ### this message will print in the year 2038 because their is a limitation
  #   with str2time ( cpan.org package Icwa-1.0.0.tar.gz )
  if ( int(time2str('%Y',time)) > 2037 ) {
    print "Bug: Try to use function 'time2str' has generate an error because"
         ."\n\tit can't handle year greter than 2037.\n";
    return;
  }   

  # data from 867
  $prev_date = str2time($edi_867->srvc_period_start_date);
  $curr_date = str2time($edi_867->srvc_period_end_date);
  $prev_read = $edi_867->prev_read_kwatts;
  $curr_read = $edi_867->curr_read_kwatts;
  $meter_multiplier = $edi_867->meter_multiplier;
  $total_usage = $edi_867->usage_kwatts;
  $measured_demand = $edi_867->measured_demand;
  $meter_number = $edi_867->meter_no;

  # data from 810
  $tdsp = sprintf('%.2f',$edi_810->tdsp/100);
  $billed_demand = $edi_810->billed_demand;

 
  ### obtain the svcnum
  my $esiid = $edi_810->esiid;
  my $svc_obj = qsearchs (  'svc_external',
                           { 'id' => $esiid
                           }
                         );
  return unless ($svc_obj); #debug
  $svcnum = $svc_obj->svcnum;

  ### obtain _date
  $_date = time;


  ### got everything we needed
  #   now let insert it into usage_elec
  my %usage = (
                'prev_date'        =>   $prev_date,
                'curr_date'        =>   $curr_date,
                'prev_read'        =>   $prev_read,
                'curr_read'        =>   $curr_read,
                'tdsp'             =>   $tdsp,       
                'svcnum'           =>   $svcnum,
                '_date'            =>   $_date,
                #'meter_multiplier' =>   $meter_multiplier,
                'meter_multiplier' =>   $meter_multiplier,
                'total_usage'      =>   $total_usage,
                'measured_demand'  =>   $measured_demand,
                'billed_demand'    =>   $billed_demand,
                'meter_number'     =>   $meter_number,
              );
  print "usage_elect Dumping". Dumper(\%usage);
 
  if ( $edi_810->esiid != '10443720004466311' &&
       $edi_810->esiid != '10443720004264904') {
    return; #for testing
  }
  
  my $usage_elec_obj = new FS::usage_elec( \%usage );
  my $error = $usage_elec_obj->insert;
  print "I'm inserting something into usage_elec\n";
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    my $msg = "Can't insert data into usage_elec : $error\n"
             .Dumper(\%usage);
    print "$msg";
    return; 
  }
 
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  ### for testing purpose.. put a message into usage_elec_transaction_867
  #
  my $usage_elec_transaction867_obj = new FS::usage_elec_transaction867( 
         {'usage_elec_id' => $usage_elec_obj->id,
          'note' => "Attention: a meter change out has occured at"
                   ." your location\n"
         } 
        );

  $error = $usage_elec_transaction867_obj->insert;
  print "Adding note into usage_elec_transaction867\n";
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    my $msg = "Can't insert data into usage_elec_transaction867 : $error\n";
    print "$msg";
    return; 
  }
 
  $dbh->commit or die $dbh->errstr if $oldAutoCommit;


  #exit;
  return $usage_elec_obj;

} # end extract_data_to_usage_elec 

### do the billing call
### return: if there is an error, returns the error, otherwise
###         returns false.
sub billing_call {
  my $usage_elec_obj = shift;

  my $debug = 0;

  my $svcnum = $usage_elec_obj->svcnum;
  print "svcnum = $svcnum\n" if $debug;

  my $package = qsearchs (  'cust_svc', 
                           { 'svcnum' => $svcnum
                           }
                         );
  unless ($package) {
    return "error: sub billing_call: unable to acquire the package\n";
  }
  my $pkgnum = $package->pkgnum;
  print "pkgnum = $pkgnum\n" if $debug;

  my $custpkg = qsearchs (  'cust_pkg',
                           { 'pkgnum'  => $pkgnum
                           }
                         ); 
  unless ($custpkg) {
    return "error: sub billing_call: unable to acquire the custpkg\n";
  }
  my $custnum = $custpkg->custnum;
  print "custnum = $custnum\n" if $debug;

  my $cust_main_obj = qsearchs (  'cust_main',
                                 { 'custnum'  => $custnum
                                 }
                               );  
  unless ($cust_main_obj) {
    return "error: sub billing_call: unable to acquire the cust_main_obj\n";
  }

  my $rtnval = $cust_main_obj->bill();
  if ($rtnval) {
    return "error: calling billing command\n\t$rtnval";
  }

  ### now let generate the invoice for the customer
  if ($debug) { #debug
    my $heading = "\tid\tprev_date\tcurr_date\tprev_read\tcurr_read"
                . "\ttdsp\tsvcnum\t_date\n";

    print "$heading";
    print "\t" . $usage_elec_obj->id; 
    print "\t" . $usage_elec_obj->prev_date; 
    print "\t" . $usage_elec_obj->curr_date; 
    print "\t" . $usage_elec_obj->prev_read; 
    print "\t" . $usage_elec_obj->curr_read; 
    print "\t" . $usage_elec_obj->tdsp; 
    print "\t" . $usage_elec_obj->svcnum; 
    print "\t" . $usage_elec_obj->_date; 
    print "\t" . $usage_elec_obj->meter_multiplier;
    print "\t" . $usage_elec_obj->measured_demand;
    print "\t" . $usage_elec_obj->billed_demand;
    print "\n";
  }

  return;

} #end billing_call

1;

