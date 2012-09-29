package FS::radius_group;

use strict;
use base qw( FS::o2m_Common FS::Record );
use FS::Record qw( qsearch qsearchs dbh );
use FS::radius_attr;

=head1 NAME

FS::radius_group - Object methods for radius_group records

=head1 SYNOPSIS

  use FS::radius_group;

  $record = new FS::radius_group \%hash;
  $record = new FS::radius_group { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::radius_group object represents a RADIUS group.  FS::radius_group inherits from
FS::Record.  The following fields are currently supported:

=over 4

=item groupnum

primary key

=item groupname

groupname

=item description

description

=item priority

priority - for export

=item speed_up, speed_down - connection speeds in bits per second.  Some 
exports may use this to generate appropriate RADIUS attributes.

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new RADIUS group.  To add the RADIUS group to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'radius_group'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

# the insert method can be inherited from FS::Record

=item delete

Delete this record from the database.

=cut

sub delete {
  # okay, I guess we support it now
  my $self = shift;
  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  my $groupnum = $self->groupnum;
  my $error = $self->process_o2m(
                'table' => 'radius_usergroup',
                'num_col' => 'groupnum',
                'fields' => ['groupnum'], # just delete them
                'params' => {},
              ) || $self->SUPER::delete(@_);

  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $part_svc_column (
    qsearch('part_svc_column', { columnname => 'usergroup' }) 
  ) {
    my $new_values = join(',', 
      grep { $_ != $groupnum } split(',', $part_svc_column->columnvalue)
    );
    next if $new_values eq $part_svc_column->columnvalue;
    $part_svc_column->set(columnvalue => $new_values);
    $error = $part_svc_column->replace;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }
  dbh->commit;
  '';
}

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

# To keep these things from proliferating, we will follow the same 
# export/noexport switches that radius_attr uses.  If you _don't_ use
# Freeside to maintain your RADIUS group attributes, then it probably 
# shouldn't try to rename groups either.

sub replace {
  my ($self, $old) = @_;
  $old ||= $self->replace_old;

  my $error = $self->check;
  return $error if $error;

  if ( !$FS::radius_attr::noexport_hack ) {
    foreach ( qsearch('part_export', {}) ) {
      next if !$_->option('export_attrs',1);
      $error = $_->export_group_replace($self, $old);
      return $error if $error;
    }
  }

  $self->SUPER::replace($old);
}

=item check

Checks all fields to make sure this is a valid RADIUS group.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

# the check method should currently be supplied - FS::Record contains some
# data checking routines

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('groupnum')
    || $self->ut_text('groupname')
    || $self->ut_textn('description')
    || $self->ut_numbern('priority')
    || $self->ut_numbern('speed_up')
    || $self->ut_numbern('speed_down')
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item long_description

Returns a description for this group consisting of its description field, 
if any, and the RADIUS group name.

=cut

sub long_description {
    my $self = shift;
    $self->description ? $self->description . " (". $self->groupname . ")"
                       : $self->groupname;
}

=item radius_attr

Returns all L<FS::radius_attr> objects (check and reply attributes) for 
this group.

=cut

sub radius_attr {
  my $self = shift;
  qsearch({
      table   => 'radius_attr', 
      hashref => {'groupnum' => $self->groupnum },
      order_by  => 'ORDER BY attrtype, attrname',
  })
}

=back

=head1 BUGS

This isn't export-specific (i.e. groups are globally unique, as opposed to being
unique per-export).

=head1 SEE ALSO

L<FS::radius_usergroup>, L<FS::Record>, schema.html from the base documentation.

=cut

1;

