package FS::transaction867;

use strict;
use vars qw( @ISA @EXPORT_OK );
use FS::Record qw( qsearch qsearchs );
use FS::UID qw( getotaker dbh );
use Exporter;
use Data::Dumper;

@ISA = qw(FS::Record);
@EXPORT_OK = qw(batch_867data_import);

=head1 NAME

FS::transaction867 - Object methods for transaction867 records

=head1 SYNOPSIS

  use FS::transaction867;

  $record = new FS::transaction867 \%hash;
  $record = new FS::transaction867 { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::transaction867 object represents an example.  FS::transaction867 inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item id - primary key

=item tdsp_duns - 

=item ref_identification - 

=item esiid - 

=item trans_creation_date - 

=item meter_no - 

=item srvc_period_start_date - 

=item srvc_period_end_date - 

=item prev_read_kwatts - 

=item curr_read_kwatts - 

=item meter_multiplier - 

=item usage_kwatts - 

=item measured_demand - 

=item ack_997 - 

=item processed - 


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'transaction867'; }

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
    || $self->ut_number('tdsp_duns')
    || $self->ut_text('ref_identification')
    || $self->ut_text('esiid')
    || $self->ut_number('trans_creation_date')
    || $self->ut_text('meter_no')
    || $self->ut_number('srvc_period_start_date')
    || $self->ut_number('srvc_period_end_date')
    || $self->ut_float('prev_read_kwatts')
    || $self->ut_float('curr_read_kwatts')
    || $self->ut_float('meter_multiplier')
    || $self->ut_float('usage_kwatts')
    || $self->ut_floatn('measured_demand')
    || $self->ut_number('ack_997')
    || $self->ut_number('processed')
  ;
  return $error if $error;

  $self->SUPER::check;
}




=item batch_867data_import


Importing a CVS file with the following column:
  867_usage esiid date meter srvc_from_date srvc_to_date previous_read_kwatts 
  current_read_kwatts mult usage_kwatts measure_demand 997_ack

=cut

#@EXPORT_OK=qw(batch_867data_import);
sub batch_867data_import {
  #my $param = shift;
  my ($fh,$format) = @_;

#  print "\n\n****************** the cvs file\n\n";
#  print (<$fh>);
#  print ("\n$format\n");
#  return "done\n";

  #my $fh = $param->{filehandle};
  #my $format = $param->{'format'};
  my $error;
  my $debug = 0;
  
  my @fields;
  if ( $format eq 'extended' ) {
    @fields = qw( 
		  tdsp_duns ref_identification esiid trans_creation_date
                  meter_no srvc_period_start_date srvc_period_end_date
                  prev_read_kwatts curr_read_kwatts meter_multiplier
                  usage_kwatts measured_demand ack_997 processed
                );
  } else {
    die "unknown format $format";
  }

  eval "use Text::CSV_XS;";
  die $@ if $@;

  my $csv = new Text::CSV_XS;
  #warn $csv;
  #warn $fh;

  my $imported = 0;
  #my $columns;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;
  
  #while ( $columns = $csv->getline($fh) ) {
  my $line;
  while ( defined($line=<$fh>) ) {

    $csv->parse($line) or do {
      $dbh->rollback if $oldAutoCommit;
      return "can't parse: ". $csv->error_input();
    };

    my @columns = $csv->fields();
    #warn join('-',@columns);

    # this hash will hold each CVS line
    my %transaction867_data;

    my $billtime = time;
#    my %cust_pkg = ( pkgpart => $pkgpart );
    my %svc_acct = ();
    foreach my $field ( @fields ) {
	# -cal  this section is ignored by the 867 import 
	$transaction867_data{$field} = shift @columns;
    }

    # make sure to set the 'ack_997' column
    $transaction867_data{'ack_997'} = 0;

    # make sure to set the 'processed' column
    $transaction867_data{'processed'} = 0;

    print Dumper(\%transaction867_data) if $debug;

    ### Check to see if the invoice is already in transaction810 table
    # if so then print a warning

    my $ref_identification = $transaction867_data{'ref_identification'};
    my $search_res = qsearchs ( 'transaction867',
                                {'ref_identification' => $ref_identification}
                              );

    if ($search_res) {

      ### 
      # place some code here to fix the problme of trying to insert
      # data that have the same references identification number

      print "$line\n";
      print "OOps! a transaction with the same references identification"
           ." number $ref_identification\n"
           ."\tis in the transaction867 table already!!\n";

    }
    else {

      my $transaction867_obj = new FS::transaction867( \%transaction867_data );
      $error = $transaction867_obj->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "can't bill customer for $line: $error";
      }

      $imported++;

    }

  } #end while

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  return "Empty file!" unless $imported;

  ''; #no error

}



=back

=head1 BUGS

The author forgot to customize this manpage.

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

