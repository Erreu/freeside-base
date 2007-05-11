package FS::svc_Common;

use strict;
use vars qw( @ISA $noexport_hack $DEBUG $me );
use Carp qw( cluck carp croak ); #specify cluck have to specify them all..
use FS::Record qw( qsearch qsearchs fields dbh );
use FS::cust_main_Mixin;
use FS::cust_svc;
use FS::part_svc;
use FS::queue;
use FS::cust_main;
use FS::inventory_item;
use FS::inventory_class;

@ISA = qw( FS::cust_main_Mixin FS::Record );

$me = '[FS::svc_Common]';
$DEBUG = 0;

=head1 NAME

FS::svc_Common - Object method for all svc_ records

=head1 SYNOPSIS

use FS::svc_Common;

@ISA = qw( FS::svc_Common );

=head1 DESCRIPTION

FS::svc_Common is intended as a base class for table-specific classes to
inherit from, i.e. FS::svc_acct.  FS::svc_Common inherits from FS::Record.

=head1 METHODS

=over 4

=item search_sql_field FIELD STRING

Class method which returns an SQL fragment to search for STRING in FIELD.

=cut

sub search_sql_field {
  my( $class, $field, $string ) = @_;
  my $table = $class->table;
  my $q_string = dbh->quote($string);
  "$table.$field = $q_string";
}

#fallback for services that don't provide a search... 
sub search_sql {
  #my( $class, $string ) = @_;
  '1 = 0'; #false
}

=item new

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);

  unless ( defined ( $self->table ) ) {
    $self->{'Table'} = shift;
    carp "warning: FS::Record::new called with table name ". $self->{'Table'};
  }
  
  #$self->{'Hash'} = shift;
  my $newhash = shift;
  $self->{'Hash'} = { map { $_ => $newhash->{$_} } qw(svcnum svcpart) };

  $self->setdefault( $self->_fieldhandlers )
    unless $self->svcnum;

  $self->{'Hash'}{$_} = $newhash->{$_}
    foreach grep { defined($newhash->{$_}) && length($newhash->{$_}) }
                 keys %$newhash;

  foreach my $field ( grep !defined($self->{'Hash'}{$_}), $self->fields ) { 
    $self->{'Hash'}{$field}='';
  }

  $self->_rebless if $self->can('_rebless');

  $self->{'modified'} = 0;

  $self->_cache($self->{'Hash'}, shift) if $self->can('_cache') && @_;

  $self;
}

#empty default
sub _fieldhandlers { {}; }

sub virtual_fields {

  # This restricts the fields based on part_svc_column and the svcpart of 
  # the service.  There are four possible cases:
  # 1.  svcpart passed as part of the svc_x hash.
  # 2.  svcpart fetched via cust_svc based on svcnum.
  # 3.  No svcnum or svcpart.  In this case, return ALL the fields with 
  #     dbtable eq $self->table.
  # 4.  Called via "fields('svc_acct')" or something similar.  In this case
  #     there is no $self object.

  my $self = shift;
  my $svcpart;
  my @vfields = $self->SUPER::virtual_fields;

  return @vfields unless (ref $self); # Case 4

  if ($self->svcpart) { # Case 1
    $svcpart = $self->svcpart;
  } elsif ( $self->svcnum
            && qsearchs('cust_svc',{'svcnum'=>$self->svcnum} )
          ) { #Case 2
    $svcpart = $self->cust_svc->svcpart;
  } else { # Case 3
    $svcpart = '';
  }

  if ($svcpart) { #Cases 1 and 2
    my %flags = map { $_->columnname, $_->columnflag } (
        qsearch ('part_svc_column', { svcpart => $svcpart } )
      );
    return grep { not ( defined($flags{$_}) && $flags{$_} eq 'X') } @vfields;
  } else { # Case 3
    return @vfields;
  } 
  return ();
}

=item label

svc_Common provides a fallback label subroutine that just returns the svcnum.

=cut

sub label {
  my $self = shift;
  cluck "warning: ". ref($self). " not loaded or missing label method; ".
        "using svcnum";
  $self->svcnum;
}

=item check

Checks the validity of fields in this record.

At present, this does nothing but call FS::Record::check (which, in turn, 
does nothing but run virtual field checks).

=cut

sub check {
  my $self = shift;
  $self->SUPER::check;
}

=item insert [ , OPTION => VALUE ... ]

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

The additional fields pkgnum and svcpart (see L<FS::cust_svc>) should be 
defined.  An FS::cust_svc record will be created and inserted.

Currently available options are: I<jobnums>, I<child_objects> and
I<depend_jobnum>.

If I<jobnum> is set to an array reference, the jobnums of any export jobs will
be added to the referenced array.

If I<child_objects> is set to an array reference of FS::tablename objects (for
example, FS::acct_snarf objects), they will have their svcnum field set and
will be inserted after this record, but before any exports are run.  Each
element of the array can also optionally be a two-element array reference
containing the child object and the name of an alternate field to be filled in
with the newly-inserted svcnum, for example C<[ $svc_forward, 'srcsvc' ]>

If I<depend_jobnum> is set (to a scalar jobnum or an array reference of
jobnums), all provisioning jobs will have a dependancy on the supplied
jobnum(s) (they will not run until the specific job(s) complete(s)).

=cut

sub insert {
  my $self = shift;
  my %options = @_;
  warn "[$me] insert called with options ".
       join(', ', map { "$_: $options{$_}" } keys %options ). "\n"
    if $DEBUG;

  my @jobnums = ();
  local $FS::queue::jobnums = \@jobnums;
  warn "[$me] insert: set \$FS::queue::jobnums to $FS::queue::jobnums\n"
    if $DEBUG;
  my $objects = $options{'child_objects'} || [];
  my $depend_jobnums = $options{'depend_jobnum'} || [];
  $depend_jobnums = [ $depend_jobnums ] unless ref($depend_jobnums);
  my $error;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $error = $self->check;
  return $error if $error;

  my $svcnum = $self->svcnum;
  my $cust_svc = $svcnum ? qsearchs('cust_svc',{'svcnum'=>$self->svcnum}) : '';
  #unless ( $svcnum ) {
  if ( !$svcnum or !$cust_svc ) {
    $cust_svc = new FS::cust_svc ( {
      #hua?# 'svcnum'  => $svcnum,
      'svcnum'  => $self->svcnum,
      'pkgnum'  => $self->pkgnum,
      'svcpart' => $self->svcpart,
    } );
    $error = $cust_svc->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
    $svcnum = $self->svcnum($cust_svc->svcnum);
  } else {
    #$cust_svc = qsearchs('cust_svc',{'svcnum'=>$self->svcnum});
    unless ( $cust_svc ) {
      $dbh->rollback if $oldAutoCommit;
      return "no cust_svc record found for svcnum ". $self->svcnum;
    }
    $self->pkgnum($cust_svc->pkgnum);
    $self->svcpart($cust_svc->svcpart);
  }

  $error = $self->set_auto_inventory;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  $error = $self->SUPER::insert;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  foreach my $object ( @$objects ) {
    my($field, $obj);
    if ( ref($object) eq 'ARRAY' ) {
      ($obj, $field) = @$object;
    } else {
      $obj = $object;
      $field = 'svcnum';
    }
    $obj->$field($self->svcnum);
    $error = $obj->insert;
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return $error;
    }
  }

  #new-style exports!
  unless ( $noexport_hack ) {

    warn "[$me] insert: \$FS::queue::jobnums is $FS::queue::jobnums\n"
      if $DEBUG;

    foreach my $part_export ( $self->cust_svc->part_svc->part_export ) {
      my $error = $part_export->export_insert($self);
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "exporting to ". $part_export->exporttype.
               " (transaction rolled back): $error";
      }
    }

    foreach my $depend_jobnum ( @$depend_jobnums ) {
      warn "[$me] inserting dependancies on supplied job $depend_jobnum\n"
        if $DEBUG;
      foreach my $jobnum ( @jobnums ) {
        my $queue = qsearchs('queue', { 'jobnum' => $jobnum } );
        warn "[$me] inserting dependancy for job $jobnum on $depend_jobnum\n"
          if $DEBUG;
        my $error = $queue->depend_insert($depend_jobnum);
        if ( $error ) {
          $dbh->rollback if $oldAutoCommit;
          return "error queuing job dependancy: $error";
        }
      }
    }

  }

  if ( exists $options{'jobnums'} ) {
    push @{ $options{'jobnums'} }, @jobnums;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';
}

=item delete

Deletes this account from the database.  If there is an error, returns the
error, otherwise returns false.

The corresponding FS::cust_svc record will be deleted as well.

=cut

sub delete {
  my $self = shift;
  my $error;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  $error =    $self->SUPER::delete
           || $self->export('delete')
	   || $self->return_inventory
	   || $self->cust_svc->delete
  ;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';
}

=item replace OLD_RECORD

Replaces OLD_RECORD with this one.  If there is an error, returns the error,
otherwise returns false.

=cut

sub replace {
  my ($new, $old) = (shift, shift);

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  # We absolutely have to have an old vs. new record to make this work.
  $old = $new->replace_old unless defined($old);

  my $error = $new->set_auto_inventory;
  if ( $error ) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  $error = $new->SUPER::replace($old);
  if ($error) {
    $dbh->rollback if $oldAutoCommit;
    return $error;
  }

  #new-style exports!
  unless ( $noexport_hack ) {

    #not quite false laziness, but same pattern as FS::svc_acct::replace and
    #FS::part_export::sqlradius::_export_replace.  List::Compare or something
    #would be useful but too much of a pain in the ass to deploy

    my @old_part_export = $old->cust_svc->part_svc->part_export;
    my %old_exportnum = map { $_->exportnum => 1 } @old_part_export;
    my @new_part_export = 
      $new->svcpart
        ? qsearchs('part_svc', { svcpart=>$new->svcpart } )->part_export
        : $new->cust_svc->part_svc->part_export;
    my %new_exportnum = map { $_->exportnum => 1 } @new_part_export;

    foreach my $delete_part_export (
      grep { ! $new_exportnum{$_->exportnum} } @old_part_export
    ) {
      my $error = $delete_part_export->export_delete($old);
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error deleting, export to ". $delete_part_export->exporttype.
               " (transaction rolled back): $error";
      }
    }

    foreach my $replace_part_export (
      grep { $old_exportnum{$_->exportnum} } @new_part_export
    ) {
      my $error = $replace_part_export->export_replace($new,$old);
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error exporting to ". $replace_part_export->exporttype.
               " (transaction rolled back): $error";
      }
    }

    foreach my $insert_part_export (
      grep { ! $old_exportnum{$_->exportnum} } @new_part_export
    ) {
      my $error = $insert_part_export->export_insert($new);
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error inserting export to ". $insert_part_export->exporttype.
               " (transaction rolled back): $error";
      }
    }

  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';
}


=item setfixed

Sets any fixed fields for this service (see L<FS::part_svc>).  If there is an
error, returns the error, otherwise returns the FS::part_svc object (use ref()
to test the return).  Usually called by the check method.

=cut

sub setfixed {
  my $self = shift;
  $self->setx('F', @_);
}

=item setdefault

Sets all fields to their defaults (see L<FS::part_svc>), overriding their
current values.  If there is an error, returns the error, otherwise returns
the FS::part_svc object (use ref() to test the return).

=cut

sub setdefault {
  my $self = shift;
  $self->setx('D', @_ );
}

=item set_default_and_fixed

=cut

sub set_default_and_fixed {
  my $self = shift;
  $self->setx( [ 'D', 'F' ], @_ );
}

=item setx FLAG | FLAG_ARRAYREF , [ CALLBACK_HASHREF ]

Sets fields according to the passed in flag or arrayref of flags.

Optionally, a hashref of field names and callback coderefs can be passed.
If a coderef exists for a given field name, instead of setting the field,
the coderef is called with the column value (part_svc_column.columnvalue)
as the single parameter.

=cut

sub setx {
  my $self = shift;
  my $x = shift;
  my @x = ref($x) ? @$x : ($x);
  my $coderef = scalar(@_) ? shift : $self->_fieldhandlers;

  my $error =
    $self->ut_numbern('svcnum')
  ;
  return $error if $error;

  my $part_svc = $self->part_svc;
  return "Unkonwn svcpart" unless $part_svc;

  #set default/fixed/whatever fields from part_svc

  foreach my $part_svc_column (
    grep { my $f = $_->columnflag; grep { $f eq $_ } @x } #columnflag in @x
    $part_svc->all_part_svc_column
  ) {

    my $columnname  = $part_svc_column->columnname;
    my $columnvalue = $part_svc_column->columnvalue;

    $columnvalue = &{ $coderef->{$columnname} }( $self, $columnvalue )
      if exists( $coderef->{$columnname} );
    $self->setfield( $columnname, $columnvalue );

  }

 $part_svc;

}

sub part_svc {
  my $self = shift;

  #get part_svc
  my $svcpart;
  if ( $self->get('svcpart') ) {
    $svcpart = $self->get('svcpart');
  } elsif ( $self->svcnum && qsearchs('cust_svc', {'svcnum'=>$self->svcnum}) ) {
    my $cust_svc = $self->cust_svc;
    return "Unknown svcnum" unless $cust_svc; 
    $svcpart = $cust_svc->svcpart;
  }

  qsearchs( 'part_svc', { 'svcpart' => $svcpart } );

}

=item set_auto_inventory

Sets any fields which auto-populate from inventory (see L<FS::part_svc>).
If there is an error, returns the error, otherwise returns false.

=cut

sub set_auto_inventory {
  my $self = shift;

  my $error =
    $self->ut_numbern('svcnum')
  ;
  return $error if $error;

  my $part_svc = $self->part_svc;
  return "Unkonwn svcpart" unless $part_svc;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  #set default/fixed/whatever fields from part_svc
  my $table = $self->table;
  foreach my $field ( grep { $_ ne 'svcnum' } $self->fields ) {
    my $part_svc_column = $part_svc->part_svc_column($field);
    if ( $part_svc_column->columnflag eq 'A' && $self->$field() eq '' ) {

      my $classnum = $part_svc_column->columnvalue;
      my $inventory_item = qsearchs({
        'table'     => 'inventory_item',
        'hashref'   => { 'classnum' => $classnum, 
                         'svcnum'   => '',
                       },
        'extra_sql' => 'LIMIT 1 FOR UPDATE',
      });

      unless ( $inventory_item ) {
        $dbh->rollback if $oldAutoCommit;
        my $inventory_class =
          qsearchs('inventory_class', { 'classnum' => $classnum } );
        return "Can't find inventory_class.classnum $classnum"
          unless $inventory_class;
        return "Out of ". $inventory_class->classname. "s\n"; #Lingua:: BS
                                                              #for pluralizing
      }

      $inventory_item->svcnum( $self->svcnum );
      my $ierror = $inventory_item->replace();
      if ( $ierror ) {
        $dbh->rollback if $oldAutoCommit;
        return "Error provisioning inventory: $ierror";
        
      }

      $self->setfield( $field, $inventory_item->item );

    }
  }

 $dbh->commit or die $dbh->errstr if $oldAutoCommit;

 '';

}

=item return_inventory

=cut

sub return_inventory {
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

  foreach my $inventory_item ( $self->inventory_item ) {
    $inventory_item->svcnum('');
    my $error = $inventory_item->replace();
    if ( $error ) {
      $dbh->rollback if $oldAutoCommit;
      return "Error returning inventory: $error";
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;

  '';
}

=item inventory_item

Returns the inventory items associated with this svc_ record, as
FS::inventory_item objects (see L<FS::inventory_item>.

=cut

sub inventory_item {
  my $self = shift;
  qsearch({
    'table'     => 'inventory_item',
    'hashref'   => { 'svcnum' => $self->svcnum, },
  });
}

=item cust_svc

Returns the cust_svc record associated with this svc_ record, as a FS::cust_svc
object (see L<FS::cust_svc>).

=cut

sub cust_svc {
  my $self = shift;
  qsearchs('cust_svc', { 'svcnum' => $self->svcnum } );
}

=item suspend

Runs export_suspend callbacks.

=cut

sub suspend {
  my $self = shift;
  $self->export('suspend');
}

=item unsuspend

Runs export_unsuspend callbacks.

=cut

sub unsuspend {
  my $self = shift;
  $self->export('unsuspend');
}

=item export HOOK [ EXPORT_ARGS ]

Runs the provided export hook (i.e. "suspend", "unsuspend") for this service.

=cut

sub export {
  my( $self, $method ) = ( shift, shift );

  $method = "export_$method" unless $method =~ /^export_/;

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE';
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $oldAutoCommit = $FS::UID::AutoCommit;
  local $FS::UID::AutoCommit = 0;
  my $dbh = dbh;

  #new-style exports!
  unless ( $noexport_hack ) {
    foreach my $part_export ( $self->cust_svc->part_svc->part_export ) {
      next unless $part_export->can($method);
      my $error = $part_export->$method($self, @_);
      if ( $error ) {
        $dbh->rollback if $oldAutoCommit;
        return "error exporting $method event to ". $part_export->exporttype.
               " (transaction rolled back): $error";
      }
    }
  }

  $dbh->commit or die $dbh->errstr if $oldAutoCommit;
  '';

}

=item overlimit

Sets or retrieves overlimit date.

=cut

sub overlimit {
  my $self = shift;
  $self->cust_svc->overlimit(@_);
}

=item cancel

Stub - returns false (no error) so derived classes don't need to define this
methods.  Called by the cancel method of FS::cust_pkg (see L<FS::cust_pkg>).

This method is called *before* the deletion step which actually deletes the
services.  This method should therefore only be used for "pre-deletion"
cancellation steps, if necessary.

=cut

sub cancel { ''; }

=item clone_suspended

Constructor used by FS::part_export::_export_suspend fallback.  Stub returning
same object for svc_ classes which don't implement a suspension fallback
(everything except svc_acct at the moment).  Document better.

=cut

sub clone_suspended {
  shift;
}

=item clone_kludge_unsuspend 

Constructor used by FS::part_export::_export_unsuspend fallback.  Stub returning
same object for svc_ classes which don't implement a suspension fallback
(everything except svc_acct at the moment).  Document better.

=cut

sub clone_kludge_unsuspend {
  shift;
}

=back

=head1 BUGS

The setfixed method return value.

B<export> method isn't used by insert and replace methods yet.

=head1 SEE ALSO

L<FS::Record>, L<FS::cust_svc>, L<FS::part_svc>, L<FS::cust_pkg>, schema.html
from the base documentation.

=cut

1;

