package FS::contact_phone;

use strict;
use base qw( FS::Record );
use FS::Record qw( qsearch qsearchs );

=head1 NAME

FS::contact_phone - Object methods for contact_phone records

=head1 SYNOPSIS

  use FS::contact_phone;

  $record = new FS::contact_phone \%hash;
  $record = new FS::contact_phone { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::contact_phone object represents an example.  FS::contact_phone inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item contactphonenum

primary key

=item contactnum

contactnum

=item phonetypenum

phonetypenum

=item countrycode

countrycode

=item phonenum

phonenum

=item extension

extension


=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new example.  To add the example to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'contact_phone'; }

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
    $self->ut_numbern('contactphonenum')
    || $self->ut_number('contactnum')
    || $self->ut_number('phonetypenum')
    || $self->ut_text('countrycode')
    || $self->ut_text('phonenum')
    || $self->ut_text('extension')
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

