package FS::banned_pay;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearch qsearchs );
use FS::UID qw( getotaker );

@ISA = qw(FS::Record);

=head1 NAME

FS::banned_pay - Object methods for banned_pay records

=head1 SYNOPSIS

  use FS::banned_pay;

  $record = new FS::banned_pay \%hash;
  $record = new FS::banned_pay { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::banned_pay object represents an banned credit card or ACH account.
FS::banned_pay inherits from FS::Record.  The following fields are currently
supported:

=over 4

=item bannum - primary key

=item payby - I<CARD> or I<CHEK>

=item payinfo - fingerprint of banned card (base64-encoded MD5 digest)

=item _date - specified as a UNIX timestamp; see L<perlfunc/"time">.  Also see
L<Time::Local> and L<Date::Parse> for conversion functions.

=item otaker - order taker (assigned automatically, see L<FS::UID>)

=item reason - reason (text)

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new ban.  To add the ban to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'banned_pay'; }

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

Checks all fields to make sure this is a valid ban.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('bannum')
    || $self->ut_enum('payby', [ 'CARD', 'CHEK' ] )
    || $self->ut_text('payinfo')
    || $self->ut_numbern('_date')
    || $self->ut_textn('reason')
  ;
  return $error if $error;

  $self->_date(time) unless $self->_date;

  $self->otaker(getotaker);

  $self->SUPER::check;
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

