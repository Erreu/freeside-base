package FS::pkg_category;

use strict;
use vars qw( @ISA );
use FS::Record qw( qsearch );
use FS::part_pkg;

@ISA = qw( FS::Record );

=head1 NAME

FS::pkg_category - Object methods for pkg_category records

=head1 SYNOPSIS

  use FS::pkg_category;

  $record = new FS::pkg_category \%hash;
  $record = new FS::pkg_category { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::pkg_category object represents an package category.  Every package class
(see L<FS::pkg_class>) has, optionally, a package category. FS::pkg_category
inherits from FS::Record.  The following fields are currently supported:

=over 4

=item categorynum - primary key (assigned automatically for new package categoryes)

=item categoryname - Text name of this package category

=item disabled - Disabled flag, empty or 'Y'

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new package category.  To add the package category to the database, see
L<"insert">.

=cut

sub table { 'pkg_category'; }

=item insert

Adds this package category to the database.  If there is an error, returns the
error, otherwise returns false.

=item delete

Deletes this package category from the database.  Only package categoryes with no
associated package definitions can be deleted.  If there is an error, returns
the error, otherwise returns false.

=cut

sub delete {
  my $self = shift;

  return "Can't delete an pkg_category with pkg_class records!"
    if qsearch( 'pkg_class', { 'categorynum' => $self->categorynum } );

  $self->SUPER::delete;
}

=item replace OLD_RECORD

Replaces OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=item check

Checks all fields to make sure this is a valid package category.  If there is an
error, returns the error, otherwise returns false.  Called by the insert and
replace methods.

=cut

sub check {
  my $self = shift;

  $self->ut_numbern('categorynum')
  or $self->ut_text('categoryname')
  or $self->SUPER::check;

}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, L<FS::part_pkg>, schema.html from the base documentation.

=cut

1;

