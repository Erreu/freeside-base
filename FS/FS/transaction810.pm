package FS::transaction810;

use strict;
use vars qw( @ISA @EXPORT_OK );
use vars qw( @ISA );
use FS::Record qw( qsearch qsearchs );
use FS::UID qw( getotaker dbh );
use Exporter;
use Data::Dumper;
@ISA = qw(FS::Record);
@EXPORT_OK=qw(batch_810data_import);
=head1 NAME

FS::transaction810 - Object methods for transaction810 records

=head1 SYNOPSIS

  use FS::transaction810;

  $record = new FS::transaction810 \%hash;
  $record = new FS::transaction810 { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::transaction810 object represents an example.  FS::transaction810 inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item id - primary key

=item duns - 

=item inv_num - 

=item usage_867 - 

=item esiid - 

=item tdsp - 

=item due_date - 

=item inv_date - 

=item usage_kwatts - 

=item srvc_from_date - 

=item srvc_to_date - 

=item puct_fund - 

=item billed_demand - 

=item measured_demand - 

=item bill_status - 

=item type_of_bill - 

=item ack_997 - 


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'transaction810'; }

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
    || $self->ut_number('inv_num')
    || $self->ut_textn('ref_identification')
    || $self->ut_number('esiid')
    || $self->ut_number('tdsp')
    || $self->ut_number('due_date')
    || $self->ut_number('inv_date')
    || $self->ut_float('usage_kwatts')
    || $self->ut_number('srvc_from_date')
    || $self->ut_number('srvc_to_date')
    || $self->ut_number('puct_fund')
    || $self->ut_float('billed_demand')
    || $self->ut_floatn('measured_demand')
    || $self->ut_text('bill_status')
    || $self->ut_numbern('type_of_bill')
    || $self->ut_numbern('ack_997')
    || $self->ut_numbern('processed')
  ;
  return $error if $error;

  $self->SUPER::check;
}

sub testing {
  my $param = shift;

  my @usages = qsearch ( 'usage_elec' );

  foreach my $usage (@usages) {
    print "meter number: " . $usage->meter_number . "\n";
  }

  return "Successful sub read\n";
}

=item batch_810data_import


Importing a CVS file with the following column:
  duns inv_num 867_usage esiid tdsp due_date inv_date usage_kwatts 
  srvc_from_date srvc_to_date puct_fund billed_demand 
  measured_demand bill_status type_of_bill 997_ack

=cut

#@EXPORT_OK=qw(batch_810data_import);
sub batch_810data_import {
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
		  tdsp_duns inv_num ref_identification esiid tdsp due_date
		  inv_date usage_kwatts srvc_from_date srvc_to_date
		  puct_fund billed_demand measured_demand bill_status
		  type_of_bill
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
    my %transaction810_data;

    my $billtime = time;
#    my %cust_pkg = ( pkgpart => $pkgpart );
    my %svc_acct = ();
    foreach my $field ( @fields ) {
	# -cal  this section is ignored by the 810 import 
	$transaction810_data{$field} = shift @columns;
    }

    # initialize the column 'ack_997' to 0 (not yet sent ack)
    $transaction810_data{'ack_997'} = 0;

    # initialize the column 'processed' to 0 (not process yet)
    $transaction810_data{'processed'} = 0;

   print Dumper(\%transaction810_data) if $debug;
   #return ("done\n");

    ### check to see if the invoice is already in transaction810 table
    # if so then print a warning
    my $inv_num = $transaction810_data{'inv_num'};
    my $search_res = qsearchs ( 'transaction810',
                                {'inv_num' => $inv_num}
                              );
    if ( $search_res ) {
      ###
      #place some code to fix this problem here
      #
      print "$line\n";
      print "OOps! a transaction with invoice number "
           ."$transaction810_data{'inv_num'}\n"
           ."\t is in the table already!!\n";
    }
    else {
      my $transaction810_obj = new FS::transaction810( \%transaction810_data );
      $error = $transaction810_obj->insert;
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "can't bill customer for $line: $error";
      }
      $imported++;
    }
  }

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

