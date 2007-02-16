package FS::rate_detail;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearch qsearchs );
use FS::rate;
use FS::rate_region;

@ISA = qw(FS::Record);

=head1 NAME

FS::rate_detail - Object methods for rate_detail records

=head1 SYNOPSIS

  use FS::rate_detail;

  $record = new FS::rate_detail \%hash;
  $record = new FS::rate_detail { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::rate_detail object represents an call plan rate.  FS::rate_detail
inherits from FS::Record.  The following fields are currently supported:

=over 4

=item ratedetailnum - primary key

=item ratenum - rate plan (see L<FS::rate>)

=item orig_regionnum - call origination region

=item dest_regionnum - call destination region

=item min_included - included minutes

=item min_charge - charge per minute

=item sec_granularity - granularity in seconds, i.e. 6 or 60

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new call plan rate.  To add the call plan rate to the database, see
L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'rate_detail'; }

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

Checks all fields to make sure this is a valid call plan rate.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
       $self->ut_numbern('ratedetailnum')
    || $self->ut_foreign_key('ratenum', 'rate', 'ratenum')
    || $self->ut_foreign_keyn('orig_regionnum', 'rate_region', 'regionnum' )
    || $self->ut_foreign_key('dest_regionnum', 'rate_region', 'regionnum' )
    || $self->ut_number('min_included')

    #|| $self->ut_money('min_charge')
    #good enough for now...
    || $self->ut_float('min_charge')

    || $self->ut_number('sec_granularity')
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item orig_region 

Returns the origination region (see L<FS::rate_region>) associated with this
call plan rate.

=cut

sub orig_region {
  my $self = shift;
  qsearchs('rate_region', { 'regionnum' => $self->orig_regionnum } );
}

=item dest_region 

Returns the destination region (see L<FS::rate_region>) associated with this
call plan rate.

=cut

sub dest_region {
  my $self = shift;
  qsearchs('rate_region', { 'regionnum' => $self->dest_regionnum } );
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::rate>, L<FS::rate_region>, L<FS::Record>,
schema.html from the base documentation.

=cut

1;

