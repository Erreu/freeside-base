package FS::cust_main_county;

use strict;
use vars qw( @ISA );
use FS::Record;

@ISA = qw( FS::Record );

=head1 NAME

FS::cust_main_county - Object methods for cust_main_county objects

=head1 SYNOPSIS

  use FS::cust_main_county;

  $record = new FS::cust_main_county \%hash;
  $record = new FS::cust_main_county { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::cust_main_county object represents a tax rate, defined by locale.
FS::cust_main_county inherits from FS::Record.  The following fields are
currently supported:

=over 4

=item taxnum - primary key (assigned automatically for new tax rates)

=item state

=item county

=item country

=item tax - percentage

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new tax rate.  To add the tax rate to the database, see L<"insert">.

=cut

sub table { 'cust_main_county'; }

=item insert

Adds this tax rate to the database.  If there is an error, returns the error,
otherwise returns false.

=item delete

Deletes this tax rate from the database.  If there is an error, returns the
error, otherwise returns false.

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=item check

Checks all fields to make sure this is a valid tax rate.  If there is an error,
returns the error, otherwise returns false.  Called by the insert and replace
methods.

=cut

sub check {
  my $self = shift;

  $self->ut_numbern('taxnum')
    || $self->ut_textn('state')
    || $self->ut_textn('county')
    || $self->ut_text('country')
    || $self->ut_float('tax')
  ;

}

=back

=head1 VERSION

$Id: cust_main_county.pm,v 1.4 1999-07-20 10:37:05 ivan Exp $

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, L<FS::cust_main>, L<FS::cust_bill>, schema.html from the base
documentation.

=head1 HISTORY

ivan@voicenet.com 97-dec-16

Changed check for 'tax' to use the new ut_float subroutine
	bmccane@maxbaud.net	98-apr-3

pod ivan@sisd.com 98-sep-21

$Log: cust_main_county.pm,v $
Revision 1.4  1999-07-20 10:37:05  ivan
cleaned up the new one-screen signup bits in htdocs/edit/cust_main.cgi to
prepare for a signup server

Revision 1.3  1998/12/29 11:59:41  ivan
mostly properly OO, some work still to be done with svc_ stuff

Revision 1.2  1998/11/18 09:01:43  ivan
i18n! i18n!


=cut

1;

