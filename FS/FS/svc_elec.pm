package FS::svc_elec;

use strict;
use vars qw( @ISA );
#use FS::Record qw( qsearch qsearchs );
use FS::svc_Common;

#@ISA = qw(FS::Record);
@ISA = qw( FS::svc_Common );

=head1 NAME

FS::svc_elec - Object methods for svc_elec records

=head1 SYNOPSIS

  use FS::svc_elec;

  $record = new FS::svc_elec \%hash;
  $record = new FS::svc_elec { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

  $error = $record->suspend;
  $error = $record->unsuspend;
  $error = $record->cancel;

=head1 DESCRIPTION

An FS::svc_elec object represents an example.  FS::svc_elec inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item id - 

=item esiid - 

=item svcnum - primary key

=item countrycode - 

=item phonenum - 

=item pin - 


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'svc_elec'; }

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
    $self->ut_numbern('svcnum')
    || $self->ut_number('id')
    || $self->ut_number('esiid')
    || $self->ut_text('countrycode')
    || $self->ut_text('phonenum')
    || $self->ut_textn('pin')
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

1;
