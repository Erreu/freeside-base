package FS::router;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearchs qsearch );
use FS::addr_block;

@ISA = qw( FS::Record );

=head1 NAME

FS::router - Object methods for router records

=head1 SYNOPSIS

  use FS::router;

  $record = new FS::router \%hash;
  $record = new FS::router { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::router record describes a broadband router, such as a DSLAM or a wireless
 access point.  FS::router inherits from FS::Record.  The following 
fields are currently supported:

=over 4

=item routernum - primary key

=item routername - descriptive name for the router

=item svcnum - svcnum of the owning FS::svc_broadband, if appropriate

=back

=head1 METHODS

=over 4

=item new HASHREF

Create a new record.  To add the record to the database, see "insert".

=cut

sub table { 'router'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=item delete

Deletes this record from the database.  If there is an error, returns the
error, otherwise returns false.

=item replace OLD_RECORD

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=item check

Checks all fields to make sure this is a valid record.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

=cut

sub check {
  my $self = shift;

  my $error =
    $self->ut_numbern('routernum')
    || $self->ut_text('routername');
  return $error if $error;

  $self->SUPER::check;
}

=item addr_block

Returns a list of FS::addr_block objects (address blocks) associated
with this object.

=cut

sub addr_block {
  my $self = shift;
  return qsearch('addr_block', { routernum => $self->routernum });
}

=item part_svc_router

Returns a list of FS::part_svc_router objects associated with this 
object.  This is unlikely to be useful for any purpose other than retrieving 
the associated FS::part_svc objects.  See below.

=cut

sub part_svc_router {
  my $self = shift;
  return qsearch('part_svc_router', { routernum => $self->routernum });
}

=item part_svc

Returns a list of FS::part_svc objects associated with this object.

=cut

sub part_svc {
  my $self = shift;
  return map { qsearchs('part_svc', { svcpart => $_->svcpart }) }
      $self->part_svc_router;
}

=back

=head1 VERSION

$Id:

=head1 BUGS

=head1 SEE ALSO

FS::svc_broadband, FS::router, FS::addr_block, FS::part_svc,
schema.html from the base documentation.

=cut

1;

