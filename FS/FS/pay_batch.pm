package FS::pay_batch;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearch qsearchs );

@ISA = qw(FS::Record);

=head1 NAME

FS::pay_batch - Object methods for pay_batch records

=head1 SYNOPSIS

  use FS::pay_batch;

  $record = new FS::pay_batch \%hash;
  $record = new FS::pay_batch { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::pay_batch object represents an example.  FS::pay_batch inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item batchnum - primary key

=item status -  

=item download - 

=item upload - 


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'pay_batch'; }

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
    $self->ut_numbern('batchnum')
    || $self->ut_enum('status', [ 'O', 'I', 'R' ])
  ;
  return $error if $error;

  $self->SUPER::check;
}

=back

=head1 BUGS

status is somewhat redundant now that download and upload exist

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

